#!/usr/bin/env bash

# Author: Naimul Islam
# Date: 7 February, 2025

# ASCII Escape for colors
RED='\e[31m'
GREEN='\e[32m'
BLUE='\e[34m'
CYAN='\e[36m'
RESET='\e[0m'

# Ensure script is run as root
[[ $EUID -ne 0 ]] && { echo -e "${RED}Error${RESET}: ${CYAN}This must be run as root!${RESET}"; exit 1; }

# Network namespaces and bridges
namespaces=(ns1 ns2 router-ns)
bridges=(br0 br1)

# IP address assignments (with CIDR)
declare -A ns_cidrs=(
    [ns1]="10.10.1.2/24"
    [ns2]="10.10.2.2/24"
)
declare -A router_cidrs=(
    [0]="10.10.1.4/24"
    [1]="10.10.2.4/24"
)
declare -A bridge_cidrs=(
    [br0]="10.10.1.3/24"
    [br1]="10.10.2.3/24"
)

# NAT config and testing IPs
NAT_RANGE="10.10.0.0/16"

get_ip() { echo "$1" | cut -d'/' -f1; }

TARGET1=$(get_ip "${ns_cidrs[ns1]}")
TARGET2=$(get_ip "${ns_cidrs[ns2]}")
TARGET3="1.1.1.1"

# Define veth pairs in the form: "namespace veth_name bridge"
veth_pairs=(
    "ns1 veth-ns1 br0"
    "ns2 veth-ns2 br1"
    "router-ns veth-rns-0 br0"
    "router-ns veth-rns-1 br1"
)

build() {
    echo -e "${BLUE}[+]${RESET} ${GREEN}Creating network namespaces...${RESET}"
    for ns in "${namespaces[@]}"; do
        ip netns add "${ns}"
    done

    echo -e "${BLUE}[+]${RESET} ${GREEN}Creating network bridges...${RESET}"
    for br in "${bridges[@]}"; do
        ip link add "${br}" type bridge
    done

    echo -e "${BLUE}[+]${RESET} ${GREEN}Setting up veth interfaces and attaching them to bridges...${RESET}"
    for entry in "${veth_pairs[@]}"; do
        read -r ns veth br <<< "${entry}"
        # Create a veth pair: one end in the namespace, one attached to the bridge
        ip link add "${veth}" netns "${ns}" type veth peer name "${veth}-br"
        ip link set "${veth}-br" master "${br}"
    done

    echo -e "${BLUE}[+]${RESET} ${GREEN}Assigning IP addresses...${RESET}"
    # Assign IPs inside namespaces
    ip netns exec ns1 ip addr add "${ns_cidrs[ns1]}" dev veth-ns1
    ip netns exec ns2 ip addr add "${ns_cidrs[ns2]}" dev veth-ns2
    ip netns exec router-ns ip addr add "${router_cidrs[0]}" dev veth-rns-0
    ip netns exec router-ns ip addr add "${router_cidrs[1]}" dev veth-rns-1

    # Assign IPs to the bridges
    for br in "${bridges[@]}"; do
        ip addr add "${bridge_cidrs[${br}]}" dev "${br}"
    done

    echo -e "${BLUE}[+]${RESET} ${GREEN}Bringing up veth interfaces...${RESET}"
    for entry in "${veth_pairs[@]}"; do
        read -r ns veth br <<< "${entry}"
        ip netns exec "${ns}" ip link set "${veth}" up
        ip link set "${veth}-br" up
    done

    echo -e "${BLUE}[+]${RESET} ${GREEN}Bringing up bridges...${RESET}"
    for br in "${bridges[@]}"; do
        ip link set "${br}" up
    done

    echo -e "${BLUE}[+]${RESET} ${GREEN}Setting up routes...${RESET}"
    ip netns exec ns1 ip route add default via "$(get_ip "${bridge_cidrs[br0]}")"
    ip netns exec ns2 ip route add default via "$(get_ip "${bridge_cidrs[br1]}")"

    echo -e "${BLUE}[+]${RESET} ${GREEN}Enabling IP forwarding and setting up NAT...${RESET}"
    sysctl -w net.ipv4.ip_forward=1 1>/dev/null
    iptables -t nat -A POSTROUTING -s "$NAT_RANGE" -j MASQUERADE

    echo -e "${BLUE}[+]${RESET} ${GREEN}BUILD COMPLETE.${RESET}"
}

clean() {
    echo -e "${BLUE}[+]${RESET} ${GREEN}Cleaning up the setup...${RESET}"
    for ns in "${namespaces[@]}"; do
        ip netns del "${ns}" 2>/dev/null
    done
    for br in "${bridges[@]}"; do
        ip link del "${br}" 2>/dev/null
    done
    sysctl -w net.ipv4.ip_forward=0 1>/dev/null
    iptables -t nat -D POSTROUTING -s "${NAT_RANGE}" -j MASQUERADE
    echo -e "${BLUE}[+]${RESET} ${GREEN}CLEANED.${RESET}"
}

test_net() {
    echo -e "${BLUE}[+]${RESET} ${GREEN}Running connectivity tests...${RESET}"
    # Define tests as: "namespace target_ip"
    tests=(
        "ns1 ${TARGET2}"
        "ns2 ${TARGET1}"
        "ns1 ${TARGET3}"
        "ns2 ${TARGET3}"
    )
    for t in "${tests[@]}"; do
        read -r ns target <<< "${t}"
        echo -e "\n${BLUE}[+]${RESET} ${GREEN}Ping from ${ns} to ${target}...${RESET}"
        ip netns exec "${ns}" ping "${target}" -c 1 | grep time | head -1
    done
}


if [[ $1 == "build" ]]; then
    build
elif [[ $1 == "clean" ]]; then
    clean
elif [[ $1 == "test" ]]; then
    test_net
else
    echo "Usage: $0 {build|clean|test}"
    exit 1
fi
