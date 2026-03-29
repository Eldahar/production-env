#!/bin/bash
# Adatbázis inicializálás — első indítás után egyszer kell futtatni.
# A tenant DB-ket NEM hozza létre — azokat külön kell (lásd README.md).
#
# Használat: ./scripts/init-db.sh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Database Initialization ==="
echo ""

# 1. Fallback tenant DB létrehozása (TENANT_DATABASE_URL-hez kell)
echo "-- Creating default tenant database --"
docker compose exec -T postgres psql -U app -d pm_central -c "
  SELECT 'CREATE DATABASE pm_tenant_default'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'pm_tenant_default')
\gexec
" 2>/dev/null || docker compose exec -T postgres psql -U app -d pm_central -c "CREATE DATABASE pm_tenant_default;" 2>/dev/null || true
docker compose exec -T postgres psql -U app -d pm_central -c "GRANT ALL PRIVILEGES ON DATABASE pm_tenant_default TO app;" 2>/dev/null || true
echo "  OK pm_tenant_default"

# 2. Central DB migráció
echo ""
echo "-- Running central DB migrations --"
docker compose exec -T api php bin/console doctrine:migrations:migrate \
    --em=central --configuration=config/migrations/central.yaml --no-interaction

# 3. Tenant schema migráció (a default DB-re — ugyanez a schema megy minden tenant-re)
echo ""
echo "-- Running tenant schema migrations --"
docker compose exec -T api php bin/console doctrine:migrations:migrate --em=tenant --no-interaction

echo ""
echo "=== Database initialization complete ==="
echo ""
echo "Következő lépések:"
echo "  1. Tenant DB-k létrehozása:"
echo "     docker compose exec postgres psql -U app -d pm_central -c \\"
echo "       \"CREATE DATABASE pm_tenant_<nev>; GRANT ALL PRIVILEGES ON DATABASE pm_tenant_<nev> TO app;\""
echo ""
echo "  2. Tenant schema alkalmazása (migráció az új DB-re):"
echo "     docker compose exec api php bin/console app:tenant:migrate --database=pm_tenant_<nev>"
echo "     # VAGY: a tenant provisioning command automatikusan futtatja"
echo ""
echo "  3. Tenant regisztráció:"
echo "     docker compose exec api php bin/console app:tenant:create ..."
echo ""
echo "  4. Admin user létrehozása:"
echo "     docker compose exec api php bin/console app:user:create ..."
