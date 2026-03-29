#!/bin/bash
# Egyszer futtatandó — production secret-ek generálása.
# Az eredményt másold be az .env.prod fájlba.
set -euo pipefail

echo "# ── Generated secrets ($(date +%Y-%m-%d)) ──"
echo "POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '=/+')"
echo "APP_SECRET=$(openssl rand -hex 32)"
echo "JWT_PASSPHRASE=$(openssl rand -base64 32 | tr -d '=/+')"
echo "ENCRYPTION_KEY=$(openssl rand -hex 32)"
echo "INTERNAL_API_TOKEN=$(openssl rand -hex 32)"
echo ""
echo "# JWT kulcspár generálás (futtasd manuálisan a JWT_PASSPHRASE-zel):"
echo "# mkdir -p jwt-keys"
echo "# openssl genpkey -algorithm RSA -out jwt-keys/private.pem \\"
echo "#     -aes256 -pass pass:<JWT_PASSPHRASE> -pkeyopt rsa_keygen_bits:4096"
echo "# openssl rsa -pubout -in jwt-keys/private.pem \\"
echo "#     -passin pass:<JWT_PASSPHRASE> -out jwt-keys/public.pem"
echo "#"
echo "# Majd másold be a Docker volume-ba:"
echo "# docker compose up -d api"
echo "# docker cp jwt-keys/private.pem \$(docker compose ps -q api):/var/www/html/config/jwt/"
echo "# docker cp jwt-keys/public.pem \$(docker compose ps -q api):/var/www/html/config/jwt/"
