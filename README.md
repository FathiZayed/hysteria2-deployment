# Hysteria2 Docker Deployment

Automated Hysteria2 proxy deployment using Docker and GitHub Container Registry.

## 🚀 One-Command Deploy

On any fresh Ubuntu/Debian server:
```bash
curl -sSL https://raw.githubusercontent.com/FathiZayed/hysteria2-deployment/main/quick-deploy.sh | sudo bash
```

This single command will:
- ✅ Install Docker
- ✅ Configure firewall (UDP ports 443, 8443)
- ✅ Generate random password
- ✅ Generate self-signed SSL certificate
- ✅ Deploy Hysteria2 container
- ✅ Display your connection credentials

## 📋 What You Get

After deployment, you'll see:
- Server IP and port
- Random password
- Connection string (hysteria2://)
- Client configuration (YAML)
- All credentials saved to `hysteria2-credentials.txt`

## 🔧 Manual Deployment
```bash
# Clone repository
git clone https://github.com/FathiZayed/hysteria2-deployment.git
cd hysteria2-deployment

# Deploy
sudo ./deploy.sh
```

## 📱 Client Configuration

### Quick Connect (URI)
```
hysteria2://PASSWORD@SERVER_IP:443/?sni=bing.com&insecure=1#Hysteria2
```

### Full Configuration (YAML)
```yaml
server: SERVER_IP:443
auth: PASSWORD
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
```

## 🔒 Security Features

- Random password generated on each deployment
- Self-signed SSL certificate (36500 days validity)
- UDP protocol (better for speed)
- 1 Gbps bandwidth limit
- Masquerade as news.ycombinator.com

## 📊 Useful Commands
```bash
# View logs
docker logs -f hysteria2-server

# View credentials
cat /opt/hysteria2/hysteria2-credentials.txt

# Restart service
docker restart hysteria2-server

# Check status
docker ps
```

## 🔄 Updating
```bash
cd /opt/hysteria2
git pull
sudo ./deploy.sh
```

## 📦 What Gets Installed

- Docker Engine
- Hysteria2 (latest version)
- iptables-persistent
- Firewall rules for UDP ports 443, 8443

## 🌍 Features

- **Ultra-fast** - Uses QUIC protocol (UDP)
- **High bandwidth** - 1 Gbps up/down
- **Automatic reconnection**
- **Traffic masquerading**
- **Self-signed certificates** (no need for domain)

## ⚠️ Important Notes

- Hysteria2 uses **UDP** protocol (not TCP)
- Self-signed certificate requires `insecure: true` in client
- Password is regenerated on each deploy
- Firewall rules persist across reboots

## 📱 Supported Clients

- [Hysteria2 CLI](https://v2.hysteria.network/) (All platforms)
- [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid) (Android)
- [V2Box](https://apps.apple.com/app/v2box-v2ray-client/id6446814690) (iOS)
- [Clash Meta](https://github.com/MetaCubeX/Clash.Meta) (All platforms)

## 📄 License

MIT
