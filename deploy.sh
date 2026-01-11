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

# Update system
echo -e "${YELLOW}[1/6] Updating system packages...${NC}"
apt-get update -qq

# Install required packages
echo -e "${YELLOW}[2/6] Installing required packages...${NC}"
apt-get install -y curl openssl jq > /dev/null 2>&1

# Install Docker if not installed
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh || {
        # Fallback: manual Docker installation for older Ubuntu
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
echo -e "${YELLOW}[3/6] Configuring firewall rules...${NC}"

# Install iptables-persistent
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent > /dev/null 2>&1

# Add firewall rules for Hysteria2 (UDP protocol)
iptables -I INPUT -p udp --dport 443 -j ACCEPT
iptables -I INPUT -p udp --dport 8443 -j ACCEPT
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p udp --dport 80 -j ACCEPT

# Save rules
netfilter-persistent save > /dev/null 2>&1

echo -e "${GREEN}✓ Firewall rules configured and saved${NC}"

# Generate new credentials and certificates
echo -e "${YELLOW}[4/6] Generating credentials and SSL certificates...${NC}"

# Generate random password (32 characters, alphanumeric only to avoid special chars)
NEW_PASSWORD=$(openssl rand -hex 16)

# Get server IP
SERVER_IP=$(curl -s https://api.ipify.org)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi

# Create certs directory if it doesn't exist
mkdir -p certs

# Generate self-signed certificate
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout certs/server.key \
    -out certs/server.crt \
    -subj "/CN=bing.com" \
    -days 36500 > /dev/null 2>&1

chmod 644 certs/server.crt
chmod 600 certs/server.key

echo -e "${GREEN}✓ Credentials and certificates generated${NC}"

# Update config.yaml
echo -e "${YELLOW}[5/6] Updating configuration...${NC}"

if [ ! -f "config.yaml" ]; then
    echo -e "${RED}Error: config.yaml not found in current directory${NC}"
    exit 1
fi

# Backup original config
cp config.yaml config.yaml.bak

# Update config with new password (using | as delimiter to avoid issues with / in password)
sed -i "s|password: .*|password: $NEW_PASSWORD|g" config.yaml

echo -e "${GREEN}✓ Configuration updated${NC}"

# Stop existing container if running
if [ "$(docker ps -aq -f name=hysteria2-server)" ]; then
    echo -e "${YELLOW}Stopping existing container...${NC}"
    docker stop hysteria2-server > /dev/null 2>&1
    docker rm hysteria2-server > /dev/null 2>&1
fi

# Deploy container
echo -e "${YELLOW}[6/6] Deploying Hysteria2 from GHCR...${NC}"

# Pull latest image
docker pull ghcr.io/fathizayed/hysteria2-deployment:latest > /dev/null 2>&1

# Run container
docker run -d \
    --name hysteria2-server \
    --restart unless-stopped \
    --network host \
    -v $(pwd)/config.yaml:/etc/hysteria/config.yaml:ro \
    -v $(pwd)/certs:/etc/hysteria:ro \
    -v $(pwd)/logs:/var/log/hysteria \
    ghcr.io/fathizayed/hysteria2-deployment:latest

# Wait for container to start
sleep 3

echo -e "${GREEN}✓ Hysteria2 deployed successfully!${NC}"

# Save credentials to file
cat > hysteria2-credentials.txt << EOL
╔════════════════════════════════════════════════════════════════╗
║              HYSTERIA2 SERVER CREDENTIALS                      ║
╚════════════════════════════════════════════════════════════════╝

Server Information:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Server IP:        $SERVER_IP
  Port:             443 (UDP)
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

Client Configuration String (hysteria2://):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
hysteria2://${NEW_PASSWORD}@${SERVER_IP}:443/?sni=bing.com&insecure=1#Hysteria2

Client Configuration (YAML):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
server: ${SERVER_IP}:443
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
EOL

# Display credentials
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${GREEN}              HYSTERIA2 SERVER CREDENTIALS                      ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Server Information:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Server IP:${NC}        ${MAGENTA}$SERVER_IP${NC}"
echo -e "  ${GREEN}Port:${NC}             ${MAGENTA}443 (UDP)${NC}"
echo -e "  ${GREEN}Protocol:${NC}         ${MAGENTA}Hysteria2${NC}"
echo -e "  ${GREEN}SNI:${NC}              ${MAGENTA}bing.com${NC}"
echo ""
echo -e "${CYAN}Authentication:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Password:${NC}         ${MAGENTA}$NEW_PASSWORD${NC}"
echo ""
echo -e "${CYAN}Bandwidth:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Upload:${NC}           ${MAGENTA}1 Gbps${NC}"
echo -e "  ${GREEN}Download:${NC}         ${MAGENTA}1 Gbps${NC}"
echo ""
echo -e "${CYAN}Client Configuration String:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}hysteria2://${NEW_PASSWORD}@${SERVER_IP}:443/?sni=bing.com&insecure=1#Hysteria2${NC}"
echo ""
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Credentials saved to:${NC} ${YELLOW}hysteria2-credentials.txt${NC}"
echo ""
echo -e "${CYAN}Container Status:${NC}"
docker ps --filter name=hysteria2-server --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo -e "  View logs:        ${GREEN}docker logs -f hysteria2-server${NC}"
echo -e "  View credentials: ${GREEN}cat hysteria2-credentials.txt${NC}"
echo -e "  Restart:          ${GREEN}docker restart hysteria2-server${NC}"
echo -e "  Stop:             ${GREEN}docker stop hysteria2-server${NC}"
echo ""
echo -e "${RED}⚠️  SECURITY WARNING:${NC}"
echo -e "${YELLOW}Keep 'hysteria2-credentials.txt' secure!${NC}"
echo ""
