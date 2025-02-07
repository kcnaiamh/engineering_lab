# Network Namespaces
NS1 = ns1
NS2 = ns2
ROUTER_NS = router-ns

# Bridges
BRIDGE0 = br0
BRIDGE1 = br1

# Interface Names
VETH_NS1 = veth-ns1
VETH_NS2 = veth-ns2
VETH_ROUTER0 = veth-rns-0
VETH_ROUTER1 = veth-rns-1

# CIDRs
NS1_CIDR = 10.10.1.2/24
NS2_CIDR = 10.10.2.2/24
ROUTER_CIDR_0 = 10.10.1.4/24
ROUTER_CIDR_1 = 10.10.2.4/24
BRIDGE0_CIDR = 10.10.1.3/24
BRIDGE1_CIDR = 10.10.2.3/24

# Network Range for SNAT
NAT_RANGE = 10.10.0.0/16

# IPS for testing
TARGET1 = $(shell echo $(NS1_CIDR) | sed 's/\/[0-9]*//')
TARGET2 = $(shell echo $(NS2_CIDR) | sed 's/\/[0-9]*//')
TARGET3 = 1.1.1.1

# ASCII Escape for colors
RED=\033[31m
GREEN=\033[32m
BLUE=\033[34m
CYAN=\033[36m
RESET=\033[0m

build:
	@if [ "$$(id -u)" -ne 0 ]; then echo "$(RED)Error$(RESET): $(CYAN)This must be run as root!$(RESET)"; exit 1; fi

	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Creating network namespaces...$(RESET)"
	ip netns add $(NS1)
	ip netns add $(NS2)
	ip netns add $(ROUTER_NS)

	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Creating network bridges...$(RESET)"
	ip link add $(BRIDGE0) type bridge
	ip link add $(BRIDGE1) type bridge

# Setup veth pairs and connect namespaces to bridges
	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Setting up veth interfaces...$(RESET)"
	# Connect $(NS1) to $(BRIDGE0)
	ip link add $(VETH_NS1) netns $(NS1) type veth peer name $(VETH_NS1)-br
	ip link set $(VETH_NS1)-br master $(BRIDGE0)

	# Connect $(NS2) to $(BRIDGE1)
	ip link add $(VETH_NS2) netns $(NS2) type veth peer name $(VETH_NS2)-br
	ip link set $(VETH_NS2)-br master $(BRIDGE1)

	# Connect $(ROUTER_NS) to $(BRIDGE0)
	ip link add $(VETH_ROUTER0) netns $(ROUTER_NS) type veth peer name $(VETH_ROUTER0)-br
	ip link set $(VETH_ROUTER0)-br master $(BRIDGE0)

	# Connect $(ROUTER_NS) to $(BRIDGE1)
	ip link add $(VETH_ROUTER1) netns $(ROUTER_NS) type veth peer name $(VETH_ROUTER1)-br
	ip link set $(VETH_ROUTER1)-br master $(BRIDGE1)

# Assign IP addresses to namespaces and bridges
	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Assigning IP addresses...$(RESET)"
	ip netns exec $(NS1) ip addr add $(NS1_CIDR) dev $(VETH_NS1)
	ip netns exec $(NS2) ip addr add $(NS2_CIDR) dev $(VETH_NS2)
	ip netns exec $(ROUTER_NS) ip addr add $(ROUTER_CIDR_0) dev $(VETH_ROUTER0)
	ip netns exec $(ROUTER_NS) ip addr add $(ROUTER_CIDR_1) dev $(VETH_ROUTER1)

	ip addr add $(BRIDGE0_CIDR) dev $(BRIDGE0)
	ip addr add $(BRIDGE1_CIDR) dev $(BRIDGE1)

	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Bringing up interfaces...$(RESET)"
	ip netns exec $(NS1) ip link set $(VETH_NS1) up
	ip link set $(VETH_NS1)-br up

	ip netns exec $(NS2) ip link set $(VETH_NS2) up
	ip link set $(VETH_NS2)-br up

	ip netns exec $(ROUTER_NS) ip link set $(VETH_ROUTER0) up
	ip link set $(VETH_ROUTER0)-br up

	ip netns exec $(ROUTER_NS) ip link set $(VETH_ROUTER1) up
	ip link set $(VETH_ROUTER1)-br up

	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Bringing up bridges...$(RESET)"
	ip link set $(BRIDGE0) up
	ip link set $(BRIDGE1) up

	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Setting up routes...$(RESET)"
	ip netns exec $(NS1) ip route add default via $(shell echo $(BRIDGE0_CIDR) | sed 's/\/[0-9]*//')
	ip netns exec $(NS2) ip route add default via $(shell echo $(BRIDGE1_CIDR) | sed 's/\/[0-9]*//')

	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Enabling IP forwarding and NAT...$(RESET)"
	sysctl -w net.ipv4.ip_forward=1
	iptables -t nat -A POSTROUTING -s $(NAT_RANGE) -j MASQUERADE

clean:
	@if [ "$$(id -u)" -ne 0 ]; then echo "$(RED)Error$(RESET): $(CYAN)This must be run as root!$(RESET)"; exit 1; fi

	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Cleaning up the setup...$(RESET)"
	ip netns del $(NS1) || true
	ip netns del $(NS2) || true
	ip netns del $(ROUTER_NS) || true
	ip link del $(BRIDGE0) || true
	ip link del $(BRIDGE1) || true

	sysctl -w net.ipv4.ip_forward=0
	iptables -t nat -D POSTROUTING $$(expr $$(iptables -t nat -L POSTROUTING | wc -l) - 2) || true

test:
	@if [ "$$(id -u)" -ne 0 ]; then echo "$(RED)Error$(RESET): $(CYAN)This must be run as root!$(RESET)"; exit 1; fi

	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Ping from $(NS1) network namespace to $(TARGET2)...$(RESET)"
	ip netns exec $(NS1) ping $(TARGET2) -c 1 | grep time | head -1

	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Ping from $(NS2) network namespace to $(TARGET1)...$(RESET)"
	ip netns exec $(NS2) ping $(TARGET1) -c 1 | grep time | head -1

	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Ping from $(NS1) network namespace to $(TARGET3)...$(RESET)"
	ip netns exec $(NS1) ping $(TARGET3) -c 1 | grep time | head -1

	@echo "\n$(BLUE)[+]$(RESET) $(GREEN)Ping from $(NS2) network namespace to $(TARGET3)...$(RESET)"
	ip netns exec $(NS2) ping $(TARGET3) -c 1 | grep time | head -1
