#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════${NC}"
echo -e "${GREEN}Hysteria2 Auto-Deploy Script${NC}"
echo -e "${BLUE}════════════════════════════════${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

INSTALL_DIR="/opt/hysteria2"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# **NEW: Port selection**
echo -e "${CYAN}Port Configuration:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Select a port for Hysteria2:"
echo "  1) 443 (default, recommended)"
echo "  2) 8443"
echo "  3) 3000"
echo "  4) 4433"
echo "  5) Custom port"
echo ""
read -p "Enter your choice (1-5) [default: 1]: " port_choice

case $port_choice in
    2)
        SERVER_PORT=8443
        ;;
    3)
        SERVER_PORT=3000
        ;;
    4)
        SERVER_PORT=4433
        ;;
    5)
        read -p "Enter custom port number (1-65535): " custom_port
        if ! [[ "$custom_port" =~ ^[0-9]+$ ]] || [ "$custom_port" -lt 1 ] || [ "$custom_port" -gt 65535 ]; then
            echo -e "${RED}✗ Invalid port number. Using default 443${NC}"
            SERVER_PORT=443
        else
            SERVER_PORT=$custom_port
        fi
        ;;
    *)
        SERVER_PORT=443
        ;;
esac

echo -e "${GREEN}✓ Selected port: $SERVER_PORT${NC}"
echo ""

# Update system
echo -e "${YELLOW}[1/7] Updating system packages...${NC}"
apt-get update -qq

# Install required packages
echo -e "${YELLOW}[2/7] Installing required packages...${NC}"
apt-get install -y curl openssl jq wget > /dev/null 2>&1

# Install Docker if not installed
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh || {
        echo -e "${YELLOW}Trying alternative Docker installation...${NC}"
        apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -qq
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    }
    systemctl enable docker
    systemctl start docker
    rm -f get-docker.sh
    echo -e "${GREEN}✓ Docker installed${NC}"
else
    echo -e "${GREEN}✓ Docker already installed${NC}"
fi

# Verify Docker is working
if ! docker --version &> /dev/null; then
    echo -e "${RED}Docker installation failed. Please install manually.${NC}"
    exit 1
fi

# Configure firewall
echo -e "${YELLOW}[3/7] Configuring firewall rules...${NC}"

# Install iptables-persistent
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent > /dev/null 2>&1

# Add firewall rules for selected port (UDP)
iptables -I INPUT -p udp --dport "$SERVER_PORT" -j ACCEPT
iptables -I INPUT -p udp --dport 8443 -j ACCEPT
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p udp --dport 80 -j ACCEPT

# Save rules
netfilter-persistent save > /dev/null 2>&1

echo -e "${GREEN}✓ Firewall rules configured and saved${NC}"

# Configure IPv6
echo -e "${YELLOW}[4/7] Configuring IPv6 support...${NC}"

# Enable IPv6 forwarding
sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null 2>&1

# Persist IPv6 forwarding across reboots
if ! grep -q "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
fi

# Detect the default outbound network interface
DEFAULT_IFACE=$(ip -6 route show default | awk '/default/ {print $5}' | head -1)
if [ -z "$DEFAULT_IFACE" ]; then
    DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -1)
fi

# Add IPv6 MASQUERADE for host traffic
ip6tables -t nat -A POSTROUTING -o "$DEFAULT_IFACE" -j MASQUERADE 2>/dev/null || true

# Enable IPv6 in Docker daemon
DOCKER_DAEMON_FILE="/etc/docker/daemon.json"
if [ -f "$DOCKER_DAEMON_FILE" ]; then
    # Check if ipv6 is already configured
    if ! grep -q '"ipv6"' "$DOCKER_DAEMON_FILE"; then
        # Merge into existing daemon.json using python
        python3 -c "
import json
with open('$DOCKER_DAEMON_FILE', 'r') as f:
    d = json.load(f)
d['ipv6'] = True
d['fixed-cidr-v6'] = 'fd00::/80'
with open('$DOCKER_DAEMON_FILE', 'w') as f:
    json.dump(d, f, indent=2)
"
    fi
else
    cat > "$DOCKER_DAEMON_FILE" << 'EOF'
{
  "ipv6": true,
  "fixed-cidr-v6": "fd00::/80"
}
EOF
fi

# Restart Docker to apply IPv6 config
systemctl restart docker
sleep 2

# Add IPv6 MASQUERADE for Docker container traffic (fd00::/80 range)
ip6tables -t nat -A POSTROUTING -s fd00::/80 -o "$DEFAULT_IFACE" -j MASQUERADE 2>/dev/null || true

# Save ip6tables rules
netfilter-persistent save > /dev/null 2>&1

echo -e "${GREEN}✓ IPv6 configured (forwarding + NAT + Docker IPv6 enabled)${NC}"
echo -e "${GREEN}  Interface: $DEFAULT_IFACE${NC}"

# Generate new credentials and certificates
echo -e "${YELLOW}[5/7] Generating credentials and SSL certificates...${NC}"

# Generate random password (32 characters)
NEW_PASSWORD=$(openssl rand -hex 16)

# Get server IPs
SERVER_IP=$(curl -s https://api.ipify.org)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi

SERVER_IPV6=$(ip -6 addr show scope global | awk '/inet6/{print $2}' | cut -d'/' -f1 | head -1)

# Remove any existing cert files/directories before creating new ones
rm -rf "$INSTALL_DIR/server.key" "$INSTALL_DIR/server.crt" 2>/dev/null || true

# Generate self-signed certificate
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$INSTALL_DIR/server.key" \
    -out "$INSTALL_DIR/server.crt" \
    -subj "/CN=bing.com" \
    -days 36500 > /dev/null 2>&1

# Set proper permissions
chmod 644 "$INSTALL_DIR/server.crt"
chmod 600 "$INSTALL_DIR/server.key"

# Verify certificates were created as files
if [ ! -f "$INSTALL_DIR/server.key" ] || [ ! -f "$INSTALL_DIR/server.crt" ]; then
    echo -e "${RED}✗ Failed to create certificate files${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Credentials and certificates generated${NC}"

# Create config.yaml with selected port
echo -e "${YELLOW}[6/7] Updating configuration...${NC}"

cat > "$INSTALL_DIR/config.yaml" << EOF
listen: :$SERVER_PORT

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: $NEW_PASSWORD

masquerade:
  type: proxy
  proxy:
    url: https://news.ycombinator.com/
    rewriteHost: true

bandwidth:
  up: 1 gbps
  down: 1 gbps

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432
EOF

echo -e "${GREEN}✓ Configuration updated${NC}"

# Download Hysteria2 binary
echo -e "${YELLOW}[7/7] Deploying Hysteria2...${NC}"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    BINARY_URL="https://github.com/apernet/hysteria/releases/download/app%2Fv2.4.4/hysteria-linux-amd64"
elif [ "$ARCH" = "aarch64" ]; then
    BINARY_URL="https://github.com/apernet/hysteria/releases/download/app%2Fv2.4.4/hysteria-linux-arm64"
else
    echo -e "${RED}✗ Unsupported architecture: $ARCH${NC}"
    exit 1
fi

# Download binary
echo "Downloading Hysteria2 binary for $ARCH..."
wget -q -O "$INSTALL_DIR/hysteria" "$BINARY_URL"
chmod +x "$INSTALL_DIR/hysteria"

# Stop existing container if running
if [ "$(docker ps -aq -f name=hysteria2-server)" ]; then
    echo -e "${YELLOW}Stopping existing container...${NC}"
    docker stop hysteria2-server > /dev/null 2>&1
    docker rm hysteria2-server > /dev/null 2>&1
fi

# Run container with selected port
docker run -d \
    --name hysteria2-server \
    --restart unless-stopped \
    --privileged \
    -p "$SERVER_PORT:$SERVER_PORT/udp" \
    -v "$INSTALL_DIR/hysteria":/hysteria:ro \
    -v "$INSTALL_DIR/config.yaml":/etc/hysteria/config.yaml:ro \
    -v "$INSTALL_DIR/server.crt":/etc/hysteria/server.crt:ro \
    -v "$INSTALL_DIR/server.key":/etc/hysteria/server.key:ro \
    alpine:latest \
    /hysteria server -c /etc/hysteria/config.yaml > /dev/null 2>&1

# Wait for container to start
sleep 3

# Check if container is running
if docker ps | grep -q hysteria2-server; then
    echo -e "${GREEN}✓ Hysteria2 deployed successfully!${NC}"
else
    echo -e "${RED}✗ Container failed to start. Check logs with: docker logs hysteria2-server${NC}"
    exit 1
fi

# Save credentials to file
cat > "$INSTALL_DIR/hysteria2-credentials.txt" << EOL
╔════════════════════════════════════════════════════════════════╗
║              HYSTERIA2 SERVER CREDENTIALS                      ║
╚════════════════════════════════════════════════════════════════╝

Server Information:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Server IP (IPv4): $SERVER_IP
  Server IP (IPv6): ${SERVER_IPV6:-N/A}
  Port:             $SERVER_PORT (UDP)
  Protocol:         Hysteria2
  SNI:              bing.com
  ALPN:             h3

Authentication:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Password:         $NEW_PASSWORD

Bandwidth:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Upload:           1 Gbps
  Download:         1 Gbps

Masquerade:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  URL:              https://news.ycombinator.com/

Client Configuration String (IPv4):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
hysteria2://${NEW_PASSWORD}@${SERVER_IP}:${SERVER_PORT}/?sni=bing.com&insecure=1#Hysteria2

Client Configuration String (IPv6):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
hysteria2://${NEW_PASSWORD}@[${SERVER_IPV6}]:${SERVER_PORT}/?sni=bing.com&insecure=1#Hysteria2-IPv6

Client Configuration (YAML):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
server: ${SERVER_IP}:${SERVER_PORT}
auth: ${NEW_PASSWORD}
tls:
  sni: bing.com
  insecure: true
bandwidth:
  up: 100 mbps
  down: 100 mbps
socks5:
  listen: 127.0.0.1:1080
http:
  listen: 127.0.0.1:8080

Generated: $(date)
╚════════════════════════════════════════════════════════════════╝

⚠️  IMPORTANT: Keep this file secure!
💡 TIP: Use insecure=1 for self-signed certificates
📝 NOTE: IPv6 address may change on reboot (Oracle Cloud dynamic IPv6)
EOL

# Display credentials
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${GREEN}              HYSTERIA2 SERVER CREDENTIALS                      ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Server Information:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Server IP (IPv4):${NC} ${MAGENTA}$SERVER_IP${NC}"
echo -e "  ${GREEN}Server IP (IPv6):${NC} ${MAGENTA}${SERVER_IPV6:-N/A}${NC}"
echo -e "  ${GREEN}Port:${NC}             ${MAGENTA}$SERVER_PORT (UDP)${NC}"
echo -e "  ${GREEN}Protocol:${NC}         ${MAGENTA}Hysteria2${NC}"
echo -e "  ${GREEN}SNI:${NC}              ${MAGENTA}bing.com${NC}"
echo ""
echo -e "${CYAN}Authentication:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Password:${NC}         ${MAGENTA}$NEW_PASSWORD${NC}"
echo ""
echo -e "${CYAN}Client Configuration String (IPv4):${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}hysteria2://${NEW_PASSWORD}@${SERVER_IP}:${SERVER_PORT}/?sni=bing.com&insecure=1#Hysteria2${NC}"
echo ""
if [ -n "$SERVER_IPV6" ]; then
echo -e "${CYAN}Client Configuration String (IPv6):${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}hysteria2://${NEW_PASSWORD}@[${SERVER_IPV6}]:${SERVER_PORT}/?sni=bing.com&insecure=1#Hysteria2-IPv6${NC}"
echo ""
fi
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Credentials saved to:${NC} ${YELLOW}$INSTALL_DIR/hysteria2-credentials.txt${NC}"
echo ""
echo -e "${CYAN}Container Status:${NC}"
docker ps --filter name=hysteria2-server --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo -e "  View logs:        ${GREEN}docker logs -f hysteria2-server${NC}"
echo -e "  View credentials: ${GREEN}cat $INSTALL_DIR/hysteria2-credentials.txt${NC}"
echo -e "  Restart:          ${GREEN}docker restart hysteria2-server${NC}"
echo -e "  Stop:             ${GREEN}docker stop hysteria2-server${NC}"
echo ""
echo -e "${RED}⚠️  SECURITY WARNING:${NC}"
echo -e "${YELLOW}Keep 'hysteria2-credentials.txt' secure!${NC}"
echo -e "${YELLOW}Oracle Cloud IPv6 is dynamic — it may change on reboot.${NC}"
echo ""
