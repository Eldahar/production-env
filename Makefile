# ══════════════════════════════════════════════════════════
# Production Environment — Makefile
# ══════════════════════════════════════════════════════════

.PHONY: shell-api shell-db shell-ai logs logs-api logs-traefik ps pull up down restart deploy deploy-skip-migrate init-db backup

# ── Shells ──
shell-api:
	docker compose exec api sh

shell-db:
	docker compose exec postgres psql -U app -d pm_central

shell-ai:
	docker compose exec ai sh

# ── Logs ──
logs:
	docker compose logs -f

logs-api:
	docker compose logs -f api

logs-traefik:
	docker compose logs -f traefik

logs-worker:
	docker compose logs -f worker

# ── Stack management ──
ps:
	docker compose ps

pull:
	docker compose pull

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

# ── Deploy ──
deploy:
	./scripts/deploy.sh

deploy-skip-migrate:
	./scripts/deploy.sh --skip-migrate

# ── Database ──
init-db:
	./scripts/init-db.sh

backup:
	docker compose exec backup /bin/sh /backup.sh

# ── Symfony console ──
console:
	docker compose exec api php bin/console $(CMD)

migrate:
	docker compose exec api php bin/console doctrine:migrations:migrate --em=central --no-interaction
	docker compose exec api php bin/console doctrine:migrations:migrate --em=tenant --no-interaction
