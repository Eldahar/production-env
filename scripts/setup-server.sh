#!/bin/bash
# Hetzner CPX42 szerver első beállítása.
# Futtatás: curl -sSL <raw-url> | bash
# VAGY: chmod +x setup-server.sh && ./setup-server.sh
set -euo pipefail

echo "=== Server Setup ==="

# 1. Csomagok
echo "-- Installing packages --"
apt update && apt upgrade -y
apt install -y docker.io docker-compose-v2 git ufw fail2ban unattended-upgrades

# 2. Docker
echo "-- Configuring Docker --"
systemctl enable docker
systemctl start docker

# Docker log rotation
cat > /etc/docker/daemon.json << 'DAEMON_JSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DAEMON_JSON
systemctl restart docker

# 3. Firewall
echo "-- Configuring firewall --"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# 4. Automatikus biztonsági frissítések
echo "-- Enabling unattended upgrades --"
dpkg-reconfigure -plow unattended-upgrades

# 5. SSH hardening
echo "-- Hardening SSH --"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
systemctl restart sshd

echo ""
echo "=== Server setup complete ==="
echo ""
echo "Következő lépések:"
echo "  1. GHCR auth: docker login ghcr.io -u Eldahar"
echo "  2. cp .env.prod.example .env.prod && nano .env.prod"
echo "  3. ./scripts/generate-secrets.sh"
echo "  4. JWT kulcspár generálás (lásd generate-secrets.sh kimenet)"
echo "  5. docker compose pull && docker compose up -d"
echo "  6. DNS beállítás: pm.maturin.hu + loginautonom.maturin.hu → szerver IP"
