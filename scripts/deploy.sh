#!/bin/bash
# Production deploy script — pull + up + migrate.
# Használat:
#   ./scripts/deploy.sh              # pull + up + migrate + cache clear
#   ./scripts/deploy.sh --skip-migrate  # pull + up (csak kód frissítés)
set -euo pipefail

cd "$(dirname "$0")/.."

SKIP_MIGRATE=false
if [ "${1:-}" = "--skip-migrate" ]; then
    SKIP_MIGRATE=true
fi

echo "=== Production Deploy ==="
echo ""

# 1. Pull latest images
echo "-- Pulling images --"
docker compose pull
echo ""

# 2. Recreate containers with new images
echo "-- Starting services --"
docker compose up -d
echo ""

# 3. Migráció
if [ "$SKIP_MIGRATE" = false ]; then
    echo "-- Running migrations (central) --"
    docker compose exec -T api \
        php bin/console doctrine:migrations:migrate --em=central --configuration=config/migrations/central.yaml --no-interaction
    echo "-- Running migrations (all tenants) --"
    docker compose exec -T api \
        php bin/console app:tenant:migrate
    echo ""
fi

# 4. Cache clear
echo "-- Clearing cache --"
docker compose exec -T api \
    php bin/console cache:clear --env=prod 2>/dev/null || true
echo ""

# 5. Health check
echo "-- Health check --"
sleep 5
docker compose ps
echo ""

echo "=== Deploy complete ==="
