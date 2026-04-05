#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════
# Tenant Worker Reconciler
# ══════════════════════════════════════════════════════════
# Ciklikusan ellenőrzi, hogy minden aktív tenant-nek fut-e
# worker konténer, és indítja/leállítja szükség szerint.
#
# Futtatás: systemd timer (30s) vagy cron
# Előfeltétel: .env.prod fájl, docker hozzáférés
# ══════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_DIR}/.env.prod"
COMPOSE_PROJECT="production-env"

# Docker label-ek a tenant worker konténerek azonosítására
LABEL_ROLE="pm.role=tenant-worker"
LABEL_TENANT_PREFIX="pm.tenant"

# Worker konfiguráció
WORKER_IMAGE="ghcr.io/eldahar/pm-api:latest"
WORKER_COMMAND="php bin/console messenger:consume outbox --time-limit=3600 --memory-limit=256M -v"
WORKER_RESTART="unless-stopped"
WORKER_NETWORKS=("${COMPOSE_PROJECT}_backend" "${COMPOSE_PROJECT}_pm-ai-net")

# Logging
LOG_PREFIX="[tenant-reconciler]"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} $*"; }

# ── .env.prod betöltés ──
if [[ ! -f "$ENV_FILE" ]]; then
    log "ERROR: ${ENV_FILE} not found"
    exit 1
fi

# DB credentials kiolvasása az .env.prod-ból
POSTGRES_PASSWORD=$(grep '^POSTGRES_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)
DATABASE_URL=$(grep '^DATABASE_URL=' "$ENV_FILE" | cut -d= -f2-)
APP_SECRET=$(grep '^APP_SECRET=' "$ENV_FILE" | cut -d= -f2-)
JWT_PASSPHRASE=$(grep '^JWT_PASSPHRASE=' "$ENV_FILE" | cut -d= -f2-)
ENCRYPTION_KEY=$(grep '^ENCRYPTION_KEY=' "$ENV_FILE" | cut -d= -f2-)
MAILER_DSN=$(grep '^MAILER_DSN=' "$ENV_FILE" | cut -d= -f2-)
MESSENGER_TRANSPORT_DSN=$(grep '^MESSENGER_TRANSPORT_DSN=' "$ENV_FILE" | cut -d= -f2-)
INTERNAL_API_BASE_URL=$(grep '^INTERNAL_API_BASE_URL=' "$ENV_FILE" | cut -d= -f2-)
INTERNAL_API_TOKEN=$(grep '^INTERNAL_API_TOKEN=' "$ENV_FILE" | cut -d= -f2-)

if [[ -z "$POSTGRES_PASSWORD" || -z "$DATABASE_URL" ]]; then
    log "ERROR: POSTGRES_PASSWORD or DATABASE_URL not found in ${ENV_FILE}"
    exit 1
fi

# ── 1. Aktív tenant-ek lekérdezése a central DB-ből ──
log "Querying active tenants from central DB..."

TENANTS_RAW=$(docker exec "${COMPOSE_PROJECT}-postgres-1" \
    psql -U app -d pm_central -t -A -F'|' \
    -c "SELECT subdomain, db_name FROM tenants WHERE deleted_at IS NULL ORDER BY subdomain;" \
    2>/dev/null) || {
    log "ERROR: Failed to query central DB"
    exit 1
}

declare -A EXPECTED_WORKERS
while IFS='|' read -r subdomain db_name; do
    [[ -z "$subdomain" ]] && continue
    EXPECTED_WORKERS["$subdomain"]="$db_name"
done <<< "$TENANTS_RAW"

log "Active tenants: ${#EXPECTED_WORKERS[@]} (${!EXPECTED_WORKERS[*]})"

# ── 2. Futó tenant worker konténerek listázása ──
RUNNING_RAW=$(docker ps --filter "label=${LABEL_ROLE}" \
    --format '{{.Label "pm.tenant"}}|{{.Names}}|{{.Status}}' 2>/dev/null) || true

declare -A RUNNING_WORKERS
while IFS='|' read -r tenant name status; do
    [[ -z "$tenant" ]] && continue
    RUNNING_WORKERS["$tenant"]="$name"
done <<< "$RUNNING_RAW"

log "Running workers: ${#RUNNING_WORKERS[@]} (${!RUNNING_WORKERS[*]})"

# ── 3. Hiányzó worker-ek indítása ──
STARTED=0
for subdomain in "${!EXPECTED_WORKERS[@]}"; do
    if [[ -z "${RUNNING_WORKERS[$subdomain]:-}" ]]; then
        db_name="${EXPECTED_WORKERS[$subdomain]}"
        container_name="pm-worker-${subdomain}"
        tenant_db_url="postgresql://app:${POSTGRES_PASSWORD}@postgres:5432/${db_name}?serverVersion=18&charset=utf8"

        log "Starting worker for tenant '${subdomain}' (DB: ${db_name})..."

        # Network connect parancsok összeállítása
        NETWORK_ARGS=()
        for net in "${WORKER_NETWORKS[@]}"; do
            NETWORK_ARGS+=(--network "$net")
        done

        docker run -d \
            --name "$container_name" \
            --restart "$WORKER_RESTART" \
            --label "$LABEL_ROLE" \
            --label "${LABEL_TENANT_PREFIX}=${subdomain}" \
            "${NETWORK_ARGS[@]}" \
            -e APP_ENV=prod \
            -e APP_SECRET="$APP_SECRET" \
            -e DATABASE_URL="$DATABASE_URL" \
            -e TENANT_DATABASE_URL="$tenant_db_url" \
            -e MESSENGER_TRANSPORT_DSN="$MESSENGER_TRANSPORT_DSN" \
            -e MAILER_DSN="$MAILER_DSN" \
            -e JWT_PASSPHRASE="$JWT_PASSPHRASE" \
            -e ENCRYPTION_KEY="$ENCRYPTION_KEY" \
            -e INTERNAL_API_BASE_URL="$INTERNAL_API_BASE_URL" \
            -e INTERNAL_API_TOKEN="$INTERNAL_API_TOKEN" \
            --log-driver json-file \
            --log-opt max-size=5m \
            --log-opt max-file=3 \
            "$WORKER_IMAGE" \
            $WORKER_COMMAND \
            2>/dev/null && {
                log "  ✓ Started ${container_name}"
                ((STARTED++))
            } || {
                log "  ✗ Failed to start ${container_name}"
            }
    fi
done

# ── 4. Felesleges worker-ek leállítása (törölt tenant-ek) ──
STOPPED=0
for subdomain in "${!RUNNING_WORKERS[@]}"; do
    if [[ -z "${EXPECTED_WORKERS[$subdomain]:-}" ]]; then
        container_name="${RUNNING_WORKERS[$subdomain]}"
        log "Stopping orphaned worker for deleted tenant '${subdomain}'..."

        docker stop "$container_name" 2>/dev/null && \
        docker rm "$container_name" 2>/dev/null && {
            log "  ✓ Stopped and removed ${container_name}"
            ((STOPPED++))
        } || {
            log "  ✗ Failed to stop ${container_name}"
        }
    fi
done

# ── 5. Crashed worker-ek újraindítása ──
RESTARTED=0
EXITED_RAW=$(docker ps -a --filter "label=${LABEL_ROLE}" --filter "status=exited" \
    --format '{{.Label "pm.tenant"}}|{{.Names}}' 2>/dev/null) || true

while IFS='|' read -r tenant name; do
    [[ -z "$tenant" ]] && continue
    # Csak ha a tenant még aktív
    if [[ -n "${EXPECTED_WORKERS[$tenant]:-}" ]]; then
        log "Restarting crashed worker '${name}' for tenant '${tenant}'..."
        docker restart "$name" 2>/dev/null && {
            log "  ✓ Restarted ${name}"
            ((RESTARTED++))
        } || {
            log "  ✗ Failed to restart ${name}"
        }
    else
        # Törölt tenant crashed worker-e → takarítás
        docker rm "$name" 2>/dev/null || true
    fi
done <<< "$EXITED_RAW"

# ── Összefoglaló ──
if ((STARTED > 0 || STOPPED > 0 || RESTARTED > 0)); then
    log "Summary: started=${STARTED}, stopped=${STOPPED}, restarted=${RESTARTED}"
else
    log "All workers in sync — no changes needed"
fi
