# Production Environment — Project Management

Production deployment a Hetzner CPX42 szerverre.

## Architektúra

- **Traefik v3** — reverse proxy, automatikus Let's Encrypt SSL
- **API** — PHP 8.5 + nginx + Symfony 8.0 (`ghcr.io/eldahar/pm-api`)
- **UI** — nginx + React 19 statikus build (`ghcr.io/eldahar/pm-ui`)
- **Worker** — Symfony Messenger consumer (ugyanaz az API image)
- **AI** — Python FastAPI (`ghcr.io/eldahar/pm-ai`)
- **PostgreSQL 18** — database-per-tenant (pm_central + pm_tenant_*)
- **Backup** — napi pg_dump, 14 nap retention

## Első telepítés

```bash
# 1. Szerver beállítás (root-ként)
chmod +x scripts/setup-server.sh
./scripts/setup-server.sh

# 2. GHCR auth
docker login ghcr.io -u Eldahar

# 3. Secrets
cp .env.prod.example .env.prod
./scripts/generate-secrets.sh   # eredményt másold .env.prod-ba
chmod 600 .env.prod

# 4. JWT kulcspár (a generate-secrets.sh kimenete mutatja a parancsokat)

# 5. Indítás
docker compose pull
docker compose up -d

# 6. DB inicializálás
docker compose exec api php bin/console doctrine:migrations:migrate --no-interaction

# 7. Tenant DB-k
docker compose exec postgres psql -U app -d pm_central -c "
  CREATE DATABASE pm_tenant_pm;
  CREATE DATABASE pm_tenant_loginautonom;
  GRANT ALL PRIVILEGES ON DATABASE pm_tenant_pm TO app;
  GRANT ALL PRIVILEGES ON DATABASE pm_tenant_loginautonom TO app;
"

# 8. Tenant regisztráció + admin user (Symfony console command-ok)
```

## Deploy (frissítés)

```bash
./scripts/deploy.sh              # pull + up + migrate + cache clear
./scripts/deploy.sh --skip-migrate  # csak image frissítés
```

## Image-ek frissítése (dev gépen)

```bash
# project-management/ repo-ból:
make prod-push-all               # build + push mind a 3 image

# vagy egyenként:
make prod-push-api
make prod-push-ui
make prod-push-ai
```

## Parancsok

```bash
# Státusz
docker compose ps

# Logok
docker compose logs -f api
docker compose logs -f traefik

# Backup manuális futtatás
docker compose exec backup /bin/sh /backup.sh

# Backup visszaállítás
gunzip -c <backup-file>.sql.gz | docker compose exec -T postgres psql -U app -d <db-name>

# Symfony console
docker compose exec api php bin/console <command>
```
