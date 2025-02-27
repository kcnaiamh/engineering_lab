import pulumi
import pulumi_aws as aws
import os
import requests
import sys

def download_file_as_string(url: str) -> str:
    """
    TODO: I'm quiting the execution if the code can not be download.
    In future I need need a fallback logic to continue execution in this case.
    """
    try:
        print(f"Downloading file from {url}...")
        response = requests.get(url=url, timeout=10)

        if response.status_code == 200:
            return response.text

        print(f"Failed to download. HTTP Status Code: {response.status_code}")
        sys.exit(1)

    except requests.exceptions.RequestException as e:
        print(f"Failed to download the file: {e}")
        sys.exit(1)


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

db = aws.ec2.Instance(
    resource_name = 'db-server',
    instance_type = 't2.micro',
    ami = 'ami-01811d4912b4ccb26',
    subnet_id = private_subnet.id,
    key_name = 'db-cluster',
    vpc_security_group_ids=[
        db_security_group.id
    ],
    tags = {
        'Name': 'db-server'
    }
)


mysql_check_script = download_file_as_string("https://raw.githubusercontent.com/kcnaiamh/devops_homelab/refs/heads/dev/kc-poc-pulumi/deploy/check-mysql.sh")


# will write check-mysql.sh file in the nodejs ec2
def generate_nodejs_user_data(db_private_ip):
    return download_file_as_string(
        "https://raw.githubusercontent.com/kcnaiamh/devops_homelab/refs/heads/dev/kc-poc-pulumi/deploy/nodejs-user-data.sh"
    ).format(db_private_ip=db_private_ip, mysql_check_script=mysql_check_script)

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