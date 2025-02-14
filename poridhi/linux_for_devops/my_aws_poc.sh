#!/usr/bin/env bash

# set -x
DEBUG=false

REGION="ap-southeast-1"
VPC_NAME="kc-vpc-01"
VPC_LOG_FILE="vpc_logs.json"

INSTANCE_TYPE="t2.micro"
AMI_ID="ami-0672fd5b9210aa093" # Ubuntu 24.04 LTS

KEY_PAIR_NAME="kc-key"
SECURITY_GROUP_NAME="kc-ec2-sg"

VPC_CIDR="10.0.0.0/16"
declare -A SUBNETS=(
    ["kc-public-sub-01"]="10.0.1.0/24:public-rt-01:a"
    ["kc-public-sub-02"]="10.0.2.0/24:public-rt-02:b"
    ["kc-private-sub-01"]="10.0.3.0/24:private-rt-01:a"
    ["kc-private-sub-02"]="10.0.4.0/24:private-rt-02:b"
)
declare -A SUBNET_IDS=()

function execute_aws_command() {
    local aws_cmd="${1}"
    local description="${2}"
    local has_dryrun="${3}"

    if [[ $DEBUG == true ]] && (( has_dryrun == 1 )); then
        echo "[*] Dry running: ${description}" >&2
        dry_run_output=$(eval "${aws_cmd} --dry-run" 2>&1)

        if [[ ${dry_run_output} != *"DryRunOperation"* ]]; then
            echo "[-] Dry run failed for: ${description}" >&2
            echo "Error output: ${dry_run_output}" >&2
            return 1
        fi
    fi

    echo "[+] Executing command: ${description}" >&2
    local output=$(eval "${aws_cmd}")
    echo "${output}"
}

function parse_output() {
    local output="${1}"
    local jq_filter="${2}"

    if [[ -z "${output}" ]]; then
        echo "[-] Empty output to parse" >&2
        return 1
    fi

    echo "${output}" | jq -r "${jq_filter}"
}

function check_vpc_conflicts() {
    local result=$(jq -r --arg name "${VPC_NAME}" --arg cidr "${VPC_CIDR}" '
        {
            name_exists: (map(select(.vpc_name == $name)) | length),
            cidr_exists: (map(select(.cidr == $cidr)) | length)
        }' "${VPC_LOG_FILE}")

    local name_exists=$(echo "$result" | jq -r '.name_exists')
    local cidr_exists=$(echo "$result" | jq -r '.cidr_exists')

    if (( ${name_exists} > 0 )); then
        echo "Warning: VPC with name '${VPC_NAME}' already exists!"
        jq -r --arg name "${VPC_NAME}" 'map(select(.vpc_name == $name)) | .[]' "${VPC_LOG_FILE}"
        return 1
    fi

    if (( ${cidr_exists} > 0 )); then
        echo "Warning: VPC with CIDR '${VPC_CIDR}' already exists!"
        jq -r --arg cidr "${VPC_CIDR}" 'map(select(.cidr == $cidr)) | .[]' "${VPC_LOG_FILE}"
        return 1
    fi

    return 0
}

function update_vpc_log_file() {
    jq --arg vpc_name "${VPC_NAME}" --arg vpc_id "${VPC_ID}" --arg cidr "${VPC_CIDR}" --arg region "${REGION}" \
        '. += [{
            "vpc_name": $vpc_name,
            "vpc_id": $vpc_id,
            "cidr": $cidr,
            "region": $region,
            "created_at": (now | strftime("%Y-%m-%d %H:%M:%S"))
        }]' "${VPC_LOG_FILE}" > "/tmp/${VPC_LOG_FILE}.tmp" && mv "/tmp/${VPC_LOG_FILE}.tmp" "${VPC_LOG_FILE}"
}

function create_route_table() {
    local subnet_name="$1"
    local rt_name="$2"
    local is_public="$3"
    local rt_id=""

    # Create route table
    output=$(execute_aws_command "aws ec2 create-route-table \
        --vpc-id ${VPC_ID} \
        --tag-specifications '[{\"ResourceType\":\"route-table\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"${VPC_NAME}-${rt_name}\"}]}]' \
        --region ${REGION}" "Create Route Table for ${subnet_name}" 1)

    rt_id=$(parse_output "${output}" ".RouteTable.RouteTableId")

    if [[ -z "$rt_id" ]]; then
        echo "[-] Failed to create Route Table for ${subnet_name}" >&2
        return 1
    fi

    echo "[*] Route Table created with ID: ${rt_id}" >&2

    # Add routes based on subnet type
    if [[ "$is_public" == "true" ]]; then
        execute_aws_command "aws ec2 create-route \
            --route-table-id ${rt_id} \
            --destination-cidr-block '0.0.0.0/0' \
            --gateway-id ${IGW_ID} \
            --region ${REGION}" "Create Internet Gateway route for ${subnet_name}" 0 >&2
    else
        # For private subnets, add NAT Gateway route if NAT_GW_ID is defined
        if [[ -n "${NAT_GW_ID}" ]]; then
            execute_aws_command "aws ec2 create-route \
                --route-table-id ${rt_id} \
                --destination-cidr-block '0.0.0.0/0' \
                --nat-gateway-id ${NAT_GW_ID} \
                --region ${REGION}" "Create NAT Gateway route for ${subnet_name}" 0 >&2
        fi
    fi

    # Always return the route table ID
    echo "${rt_id}"
}


function check_jq() {
    if ! which jq &> /dev/null; then
        echo "[-] 'jq' is required to parse JSON output. Please install it." >&2
        exit 1
    fi
}

function init_vpc_log_file() {
    if [[ ! -f "${VPC_LOG_FILE}" ]]; then
        echo "[]" > "${VPC_LOG_FILE}"
    fi
}

echo "[*] Checking prerequisites"
check_jq
init_vpc_log_file

# 1. Create the VPC
if ! check_vpc_conflicts; then
    echo "[-] Skipping VPC creation due to conflicts."
    echo "[-] Please check ${VPC_LOG_FILE} for existing VPC details."
    exit 1
fi

create_vpc_cmd="aws ec2 create-vpc \
    --cidr-block ${VPC_CIDR} \
    --tag-specifications '[{\"ResourceType\":\"vpc\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"${VPC_NAME}\"}]}]' \
    --region ${REGION}"

output=$(execute_aws_command "${create_vpc_cmd}" "Create VPC" 1)
VPC_ID=$(parse_output "${output}" ".Vpc.VpcId")

if [[ -z "${VPC_ID}" ]]; then
    echo "[-] Failed to create VPC"
    exit 1
fi
echo "[*] VPC created with ID: ${VPC_ID}"

update_vpc_log_file

# 2. Enable DNS support
enable_vpc_dns_support_cmd="aws ec2 modify-vpc-attribute \
    --vpc-id ${VPC_ID} \
    --enable-dns-support '{\"Value\":true}' \
    --region ${REGION}"

execute_aws_command "${enable_vpc_dns_support_cmd}" "Enable DNS Support" 0

enable_vpc_dns_hostname_cmd="aws ec2 modify-vpc-attribute \
    --vpc-id ${VPC_ID} \
    --enable-dns-hostnames '{\"Value\":true}' \
    --region ${REGION}"

execute_aws_command "${enable_vpc_dns_hostname_cmd}" "Enable Hostname DNS Support" 0
echo "[*] DNS support enabled for the VPC."

# 3. Create Internet Gateway
create_igw_cmd="aws ec2 create-internet-gateway \
    --tag-specifications '[{\"ResourceType\":\"internet-gateway\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"${VPC_NAME}-igw\"}]}]' \
    --region ${REGION}"

output=$(execute_aws_command "${create_igw_cmd}" "Create Internet Gateway" 1)
IGW_ID=$(parse_output "${output}" ".InternetGateway.InternetGatewayId")

if [[ -z "${IGW_ID}" ]]; then
    echo "[-] Failed to create Internet Gateway"
    exit 1
fi
echo "[*] Internet Gateway created with ID: ${IGW_ID}"

# 4. Attach IGW to VPC
attach_igw_cmd="aws ec2 attach-internet-gateway \
    --vpc-id ${VPC_ID} \
    --internet-gateway-id ${IGW_ID} \
    --region ${REGION}"

execute_aws_command "${attach_igw_cmd}" "Attach Internet Gateway" 0
echo "[*] Internet Gateway attached to the VPC."

# Create subnets and route tables
# ${!SUBNETS[@]} - Gets all the KEYS of the array
# ${SUBNETS[@]} - Gets all the VALUES of the array

for subnet_name in "${!SUBNETS[@]}"; do
    # IFS is a special shell variable that determines how Bash splits strings
    # Default IFS is space, tab, and newline
    # Here we temporarily set it to ':' to split on colons
    IFS=':' read -r subnet_cidr rt_name az <<< "${SUBNETS[${subnet_name}]}"

    # Determine if subnet is public based on name
    is_public=false
    [[ ${subnet_name} == *"public"* ]] && is_public=true

    # Create subnet
    output=$(execute_aws_command "aws ec2 create-subnet \
        --vpc-id ${VPC_ID} \
        --cidr-block ${subnet_cidr} \
        --tag-specifications '[{\"ResourceType\":\"subnet\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"${VPC_NAME}-${subnet_name}\"}]}]' \
        --availability-zone ${REGION}${az} \
        --region ${REGION}" "Create Subnet ${subnet_name}" 1)

    subnet_id=$(parse_output "${output}" ".Subnet.SubnetId")

    if [[ -z "${subnet_id}" ]]; then
        echo "[-] Failed to create Subnet: ${subnet_name}"
        continue
    fi

    SUBNET_IDS["${subnet_name}"]="${subnet_id}"
    echo "[*] Subnet created with ID: ${subnet_id}"

    # Create and configure route table
    rt_id=$(create_route_table "${subnet_name}" "${rt_name}" "${is_public}")

    if [[ -n "${rt_id}" ]]; then
        # Associate route table with subnet
        execute_aws_command "aws ec2 associate-route-table \
            --subnet-id ${subnet_id} \
            --route-table-id ${rt_id} \
            --region ${REGION}" "Associate Route Table with Subnet ${subnet_name}" 0
    fi

    # Enable auto-assign public IP for public subnets
    if [[ "${is_public}" == "true" ]]; then
        execute_aws_command "aws ec2 modify-subnet-attribute \
            --subnet-id ${subnet_id} \
            --map-public-ip-on-launch \
            --region ${REGION}" "Enable auto-assign public IP for ${subnet_name}" 0
    fi
done

# Create Security Group
create_security_group_cmd="aws ec2 create-security-group \
    --group-name ${SECURITY_GROUP_NAME} \
    --description 'Security group for EC2 instance' \
    --vpc-id ${VPC_ID} \
    --tag-specifications '[{\"ResourceType\":\"security-group\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"${SECURITY_GROUP_NAME}\"},{\"Key\":\"Environment\",\"Value\":\"Production\"},{\"Key\":\"CreatedBy\",\"Value\":\"Naimul Islam\"}]}]' \
    --region ${REGION}"

output=$(execute_aws_command "${create_security_group_cmd}" "Create Security Group" 0)
SECURITY_GROUP_ID=$(parse_output "${output}" ".GroupId")

if [[ -z "${SECURITY_GROUP_ID}" ]]; then
    echo "[-] Failed to create Security Group"
    exit 1
fi
echo "[*] Security Group created with ID: ${SECURITY_GROUP_ID}"

# Add security group rules
authorize_sg_ingress_cmd="aws ec2 authorize-security-group-ingress \
    --group-id ${SECURITY_GROUP_ID} \
    --ip-permissions '[{\"IpProtocol\":\"tcp\",\"FromPort\":22,\"ToPort\":22,\"IpRanges\":[{\"CidrIp\":\"0.0.0.0/0\"}]},{\"IpProtocol\":\"tcp\",\"FromPort\":80,\"ToPort\":80,\"IpRanges\":[{\"CidrIp\":\"0.0.0.0/0\"}]},{\"IpProtocol\":\"tcp\",\"FromPort\":443,\"ToPort\":443,\"IpRanges\":[{\"CidrIp\":\"0.0.0.0/0\"}]}]' \
    --region ${REGION}"

execute_aws_command "${authorize_sg_ingress_cmd}" "Authorize SSH, HTTP & HTTPS Inbound" 0
echo "[*] Security Group rules added (SSH, HTTP, and HTTPS)."

# Get the one public subnet ID
for subnet_name in "${!SUBNET_IDS[@]}"; do
    [[ ${subnet_name} == *"public"* ]] && PUBLIC_SUBNET_ID="${SUBNET_IDS[${subnet_name}]}" && break
done

# Launch EC2 Instance
launch_instance_cmd="aws ec2 run-instances \
    --image-id ${AMI_ID} \
    --instance-type ${INSTANCE_TYPE} \
    --block-device-mappings '[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"Encrypted\":false,\"DeleteOnTermination\":true,\"Iops\":3000,\"SnapshotId\":\"snap-026b36c7d8fd55d61\",\"VolumeSize\":8,\"VolumeType\":\"gp3\",\"Throughput\":125}}]' \
    --network-interfaces '[{\"AssociatePublicIpAddress\":true,\"DeviceIndex\":0,\"Groups\":[\"${SECURITY_GROUP_ID}\"]}]' \
    --credit-specification '{\"CpuCredits\":\"standard\"}' \
    --metadata-options '{\"HttpEndpoint\":\"enabled\",\"HttpPutResponseHopLimit\":2,\"HttpTokens\":\"required\"}' \
    --private-dns-name-options '{\"HostnameType\":\"ip-name\",\"EnableResourceNameDnsARecord\":true,\"EnableResourceNameDnsAAAARecord\":false}' \
    --key-name ${KEY_PAIR_NAME} \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --subnet-id ${PUBLIC_SUBNET_ID} \
    --tag-specifications '[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"kc-ec2-pub-01\"}]}]' \
    --region ${REGION} \
    --count 1"

output=$(execute_aws_command "${launch_instance_cmd}" "Launch EC2 Instance" 1 | tee /dev/tty)
INSTANCE_ID=$(parse_output "${output}" ".Instances[0].InstanceId")

if [[ -z "${INSTANCE_ID}" ]]; then
    echo "[-] Failed to launch EC2 instance"
    exit 1
fi
echo "[*] EC2 instance launched with ID: ${INSTANCE_ID}"

# Wait for instance to be running and initialized
echo "[*] Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids ${INSTANCE_ID} --region ${REGION}

# Get the public DNS name
PUBLIC_DNS=$(aws ec2 describe-instances \
    --instance-ids ${INSTANCE_ID} \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text \
    --region ${REGION})

echo "[*] EC2 Instance Public DNS: ${PUBLIC_DNS}"

# For Ubuntu 24.04, the default username is 'ubuntu'
echo "[*] Default username: ubuntu"
echo "[*] You can connect using: ssh -i ${KEY_PAIR_NAME}.pem ubuntu@${PUBLIC_DNS}"

terminate_ec2=""
read -p "Do you want to terminate the EC2 instance? (y/n): " terminate_ec2

if [[ ${terminate_ec2} == "y" ]]; then
    # Terminate the instance
    terminate_ec2_cmd="aws ec2 terminate-instances \
        --instance-ids ${INSTANCE_ID} \
        --region ${REGION}"

    termination_output=$(execute_aws_command "${terminate_ec2_cmd}" "Terminate EC2 Instance" 0)

    # Check if the command succeeded
    if (( $? == 0 )); then
        echo "[+] Instance ${INSTANCE_ID} is being terminated."
        echo "Output: ${termination_output}"
    else
        echo "[-] Failed to terminate instance ${INSTANCE_ID}."
        echo "Error output: ${termination_output}" >&2
        exit 1
    fi
fi