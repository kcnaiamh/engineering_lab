import pulumi
import pulumi_aws as aws
import os

def read_file(file_path: str) -> str:
    with open(f'./{file_path}', 'r') as fd:
        return fd.read()

vpc = aws.ec2.Vpc(
    resource_name='nodejs-db-vpc',
    cidr_block='10.0.0.0/16',
    enable_dns_support=True,
    enable_dns_hostnames=True,
    tags={
        'Name': 'nodejs-db-vpc',
    }
)

public_subnet = aws.ec2.Subnet(
    resource_name='nodejs-public-subnet',
    vpc_id=vpc.id,
    cidr_block='10.0.1.0/24',
    map_public_ip_on_launch=True,
    availability_zone='ap-southeast-1a',
    tags={
        'Name': 'nodejs-public-subnet'
    }
)

private_subnet = aws.ec2.Subnet(
    resource_name='db-private-subnet',
    vpc_id=vpc.id,
    cidr_block='10.0.2.0/24',
    map_public_ip_on_launch=False,
    availability_zone='ap-southeast-1a',
    tags={
        'Name': 'db-private-subnet'
    }
)

internet_gateway = aws.ec2.InternetGateway(
    resource_name='nodejs-db-internet-gateway',
    vpc_id=vpc.id,
    tags={
        'Name': 'nodejs-db-internet-gateway'
    }
)

elastic_ip = aws.ec2.Eip(
    resource_name='nat-eip'
)

nat_gateway = aws.ec2.NatGateway(
    resource_name='nat-gateway',
    allocation_id=elastic_ip.id,
    subnet_id=public_subnet.id,
    tags={
        'Name': 'nodejs-db-nat-gateway'
    }
)

public_route_table = aws.ec2.RouteTable(
    resource_name='public-route-table',
    vpc_id=vpc.id,
    routes=[
        aws.ec2.RouteTableRouteArgs(
            cidr_block='0.0.0.0/0',
            gateway_id=internet_gateway.id
        )
    ],
    tags={
        'Name': 'nodejs-public-route-table'
    }
)

private_route_table = aws.ec2.RouteTable(
    resource_name='private-route-table',
    vpc_id=vpc.id,
    routes=[
        aws.ec2.RouteTableRouteArgs(
            cidr_block='0.0.0.0/0',
            nat_gateway_id=nat_gateway.id
        )
    ],
    tags={
        'Name': 'db-private-route-table'
    }
)

public_route_table_association = aws.ec2.RouteTableAssociation(
    resource_name='public-route-table-association',
    subnet_id=public_subnet.id,
    route_table_id=public_route_table.id
)

private_route_table_association = aws.ec2.RouteTableAssociation(
    resource_name='private-route-table-association',
    subnet_id=private_subnet.id,
    route_table_id=private_route_table.id
)

nodejs_security_group = aws.ec2.SecurityGroup(
    resource_name='nodejs-security-group',
    vpc_id=vpc.id,
    description="Security group for Node.js application",
    ingress=[
        aws.ec2.SecurityGroupIngressArgs(
            protocol='tcp',
            from_port=22,
            to_port=22,
            cidr_blocks=['0.0.0.0/0']
        ),
        aws.ec2.SecurityGroupIngressArgs(
            protocol='tcp',
            from_port=3000,
            to_port=3000,
            cidr_blocks=['0.0.0.0/0']
        )
    ],
    egress=[
        aws.ec2.SecurityGroupEgressArgs(
            protocol='-1',
            from_port=0,
            to_port=0,
            cidr_blocks=['0.0.0.0/0']
        )
    ],
    tags={
        'Name': 'nodejs-security-group'
    }
)

db_security_group = aws.ec2.SecurityGroup(
    resource_name='db-security-group',
    vpc_id=vpc.id,
    description='Security group for MySQL database',
    ingress=[
        aws.ec2.SecurityGroupIngressArgs(
            protocol='tcp',
            from_port=22,
            to_port=22,
            cidr_blocks=[public_subnet.cidr_block],
        ),
        aws.ec2.SecurityGroupIngressArgs(
            protocol='tcp',
            from_port=3306,
            to_port=3306,
            cidr_blocks=[public_subnet.cidr_block]
        )
    ],
    egress=[
        aws.ec2.SecurityGroupEgressArgs(
            protocol='-1',
            from_port=0,
            to_port=0,
            cidr_blocks=['0.0.0.0/0']
        )
    ],
    tags={
        'Name': 'db-security-group'
    }
)




mysql_setup_script = read_file('scripts/mysql-setup.sh')

def generate_mysql_user_data():
    return f'''\
#!/usr/bin/env bash
exec > >(tee /var/log/mysql-user-data.log) 2>&1

apt update

mkdir -p /usr/local/bin

cat > /usr/local/bin/mysql-setup.sh << 'EOF'
{mysql_setup_script}
EOF

chmod +x /usr/local/bin/mysql-setup.sh

/usr/local/bin/mysql-setup.sh
'''

db = aws.ec2.Instance(
    resource_name = 'db-server',
    instance_type = 't2.micro',
    ami = 'ami-01811d4912b4ccb26',
    subnet_id = private_subnet.id,
    key_name = 'db-cluster',
    vpc_security_group_ids=[
        db_security_group.id
    ],
    user_data=generate_mysql_user_data(),
    user_data_replace_on_change=True,
    tags = {
        'Name': 'db-server'
    },
    opts=pulumi.ResourceOptions(
        depends_on=[
            nat_gateway,
            private_route_table_association,
            private_subnet
        ]
    )
)

nodejs_app_code = read_file('src/app.js')
nodejs_setup_script = read_file('scripts/nodejs-setup.sh')
mysql_check_script = read_file('scripts/mysql-check.sh')
mysql_check_service = read_file('scripts/mysql-check.service')
nodejs_app_service = read_file('scripts/nodejs-app.service')


def generate_nodejs_user_data(db_private_ip):
    return f'''\
#!/usr/bin/env bash
exec > >(tee /var/log/nodejs-user-data.log) 2>&1

apt update

echo "DB_PRIVATE_IP={db_private_ip}" >> /etc/environment
source /etc/environment

mkdir -p /usr/local/bin
mkdir -p /opt/app

cat > /usr/local/bin/nodejs-setup.sh << 'EOF'
{nodejs_setup_script}
EOF

cat > /usr/local/bin/mysql-check.sh << 'EOF'
{mysql_check_script}
EOF

cat > /etc/systemd/system/mysql-check.service << 'EOF'
{mysql_check_service}
EOF

cat > /etc/systemd/system/nodejs-app.service << 'EOF'
{nodejs_app_service}
EOF

cat > /opt/app/app.js << 'EOF'
{nodejs_app_code}
EOF

chmod +x /usr/local/bin/nodejs-setup.sh
chmod +x /usr/local/bin/mysql-check.sh

/usr/local/bin/nodejs-setup.sh
'''


nodejs = aws.ec2.Instance(
    resource_name='nodejs-server',
    instance_type='t2.micro',
    ami='ami-01811d4912b4ccb26',
    subnet_id=public_subnet.id,
    key_name='db-cluster',
    vpc_security_group_ids=[
        nodejs_security_group.id
    ],
    associate_public_ip_address=True,
    user_data=pulumi.Output.all(db.private_ip).apply(
        lambda args: generate_nodejs_user_data(args[0])
    ),
    user_data_replace_on_change=True,
    tags={
        'Name': 'nodejs-server'
    }
)

all_ips = [nodejs.public_ip, db.private_ip]

def create_config_file(all_ips):
    config_content = f'''\
Host nodejs-server
    HostName {all_ips[0]}
    User ubuntu
    IdentityFile ~/.ssh/db-cluster.id_rsa

Host db-server
    ProxyJump nodejs-server
    HostName {all_ips[1]}
    User ubuntu
    IdentityFile ~/.ssh/db-cluster.id_rsa
'''
    config_path = os.path.expanduser("~/.ssh/config")
    with open(config_path, "w") as config_file:
        config_file.write(config_content)

pulumi.Output.all(*all_ips).apply(create_config_file)

pulumi.export('nodejs_public_ip', nodejs.public_ip)
pulumi.export('nodejs_private_ip', nodejs.private_ip)
pulumi.export('db_private_ip', db.private_ip)

pulumi.export('vpc_id', vpc.id)
pulumi.export('public_subnet_id', public_subnet.id)
pulumi.export('private_subnet_id', private_subnet.id)
