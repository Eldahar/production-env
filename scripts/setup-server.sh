#!/bin/bash
# Hetzner CPX42 szerver első beállítása.
# Futtatás root-ként:
#   git clone git@github.com:Eldahar/production-env.git /root/production-env
#   cd /root/production-env
#   chmod +x scripts/setup-server.sh
#   ./scripts/setup-server.sh
#
# A script létrehozza a 'deploy' felhasználót és átmozgatja a repo-t
# a /home/deploy/production-env/ könyvtárba.
set -euo pipefail

DEPLOY_USER="deploy"
DEPLOY_HOME="/home/$DEPLOY_USER"
DEPLOY_DIR="$DEPLOY_HOME/production-env"

# Root check
if [ "$(id -u)" -ne 0 ]; then
    echo "Ez a script root jogot igényel. Futtasd root-ként!" >&2
    exit 1
fi

echo "=== Server Setup ==="
echo ""

# ── 1. Csomagok ──
echo "-- 1/7 Installing packages --"
apt update && apt upgrade -y
apt install -y docker.io docker-compose-v2 git ufw fail2ban unattended-upgrades

# ── 2. Docker ──
echo "-- 2/7 Configuring Docker --"
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

# ── 3. Firewall ──
echo "-- 3/7 Configuring firewall --"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# ── 4. Automatikus biztonsági frissítések ──
echo "-- 4/7 Enabling unattended upgrades --"
dpkg-reconfigure -plow unattended-upgrades

# ── 5. SSH hardening ──
echo "-- 5/7 Hardening SSH --"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
# FONTOS: sshd restart a script végén, miután a deploy user SSH kulcsa be van állítva

# ── 6. Deploy user létrehozása ──
echo "-- 6/7 Creating deploy user --"
if id "$DEPLOY_USER" &>/dev/null; then
    echo "  User '$DEPLOY_USER' already exists, skipping creation"
else
    useradd -m -s /bin/bash "$DEPLOY_USER"
    echo "  User '$DEPLOY_USER' created"
fi

# Docker csoport
usermod -aG docker "$DEPLOY_USER"
echo "  Added '$DEPLOY_USER' to docker group"

# SSH kulcs — a root authorized_keys-ből másolja (a Hetzner-en root-ként lépünk be)
mkdir -p "$DEPLOY_HOME/.ssh"
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys "$DEPLOY_HOME/.ssh/authorized_keys"
    echo "  SSH keys copied from root"
else
    echo "  WARNING: /root/.ssh/authorized_keys not found — manuálisan kell SSH kulcsot beállítani!"
fi
chmod 700 "$DEPLOY_HOME/.ssh"
chmod 600 "$DEPLOY_HOME/.ssh/authorized_keys" 2>/dev/null || true
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_HOME/.ssh"

# ── 7. Repo átmozgatás a deploy user-hez ──
echo "-- 7/7 Moving repo to deploy user home --"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$SCRIPT_DIR" != "$DEPLOY_DIR" ]; then
    # Ha már létezik a cél, töröljük (friss clone)
    rm -rf "$DEPLOY_DIR"
    cp -a "$SCRIPT_DIR" "$DEPLOY_DIR"
    chown -R "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_DIR"
    echo "  Repo copied to $DEPLOY_DIR"
    echo "  (az eredeti $SCRIPT_DIR törölhető)"
else
    chown -R "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_DIR"
    echo "  Repo already at $DEPLOY_DIR"
fi

# SSH restart (most már a deploy user-nek is van SSH kulcsa)
systemctl restart sshd

echo ""
echo "=== Server setup complete ==="
echo ""
echo "A '$DEPLOY_USER' felhasználó kész. Lépj be vele:"
echo "  ssh $DEPLOY_USER@<szerver-ip>"
echo ""
echo "Majd a deploy user-ként:"
echo "  cd ~/production-env"
echo "  docker login ghcr.io -u Eldahar"
echo "  cp .env.prod.example .env.prod"
echo "  nano .env.prod                        # secrets kitöltése"
echo "  ./scripts/generate-secrets.sh          # secret-ek generálása"
echo "  # JWT kulcspár generálás (lásd generate-secrets.sh kimenet)"
echo "  docker compose pull"
echo "  docker compose up -d"
echo "  # DNS: pm.maturin.hu + loginautonom.maturin.hu → szerver IP"
