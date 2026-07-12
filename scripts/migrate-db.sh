#!/usr/bin/env bash
#
# migrate-db.sh — dump the blue (VPS docker-compose) production Postgres and
# restore it into the green (k3s) Postgres. Implements Phase 2 of the migration
# (see docs/runbook-cutover.md) as a repeatable, rehearsable script.
#
# Modes:
#   rehearse (default) — restore into a THROWAWAY database on green, report row
#                        counts + timing, then drop it. Non-destructive; run this
#                        first (and time it) before the real cutover.
#   final              — restore into the real target DB (--clean --if-exists).
#                        Prompts for confirmation. Use only during the cutover
#                        window with the blue app stopped/quiesced.
#
# Requirements: ssh access to the blue host, kubectl pointed at the green cluster.
#
# Usage:
#   BLUE_HOST=root@168.119.156.43 ./scripts/migrate-db.sh rehearse
#   BLUE_HOST=root@168.119.156.43 ./scripts/migrate-db.sh final
#
set -euo pipefail

MODE="${1:-rehearse}"
BLUE_HOST="${BLUE_HOST:?set BLUE_HOST, e.g. root@168.119.156.43}"
BLUE_COMPOSE_DIR="${BLUE_COMPOSE_DIR:-/opt/stockplan}"
BLUE_COMPOSE_FILE="${BLUE_COMPOSE_FILE:-docker-compose.production.yml}"
BLUE_COMPOSE_PROJECT="${BLUE_COMPOSE_PROJECT:-prod}"
SRC_DB_USER="${SRC_DB_USER:-stockplan_user}"
SRC_DB="${SRC_DB:-stockplan_prod}"
GREEN_NS="${GREEN_NS:-data}"
GREEN_POD="${GREEN_POD:-postgres-0}"
TARGET_DB="${TARGET_DB:-stockplan_production}"
REHEARSE_DB="${REHEARSE_DB:-stockplan_migrate_rehearsal}"
DUMP="${DUMP:-/tmp/norviq-blue-$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo dump).dump}"

log() { printf '\033[1;34m[migrate]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[migrate] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v ssh >/dev/null || die "ssh not found"
command -v kubectl >/dev/null || die "kubectl not found"
kubectl -n "$GREEN_NS" get pod "$GREEN_POD" >/dev/null 2>&1 || die "green pod $GREEN_NS/$GREEN_POD not reachable (check KUBECONFIG)"

# 1. Dump blue (custom format, compressed) over ssh.
log "dumping $SRC_DB from blue ($BLUE_HOST) ..."
ssh "$BLUE_HOST" "cd $BLUE_COMPOSE_DIR && docker compose -p $BLUE_COMPOSE_PROJECT -f $BLUE_COMPOSE_FILE exec -T db pg_dump -Fc -U $SRC_DB_USER $SRC_DB" > "$DUMP"
SIZE=$(wc -c < "$DUMP" | tr -d ' ')
[ "$SIZE" -gt 100 ] || die "dump looks empty ($SIZE bytes)"
log "dump ok: $DUMP ($SIZE bytes)"

# 2. Copy dump into the green pod.
log "copying dump into green pod ..."
kubectl -n "$GREEN_NS" cp "$DUMP" "$GREEN_POD:/tmp/migrate.dump"

restore_into() {
  local db="$1" extra="$2"
  kubectl -n "$GREEN_NS" exec -i "$GREEN_POD" -- sh -c "
    set -e
    pg_restore $extra -U \"\$POSTGRES_USER\" -d $db /tmp/migrate.dump
  "
}

rowcounts() {
  local db="$1"
  kubectl -n "$GREEN_NS" exec -i "$GREEN_POD" -- sh -c "
    psql -tAq -U \"\$POSTGRES_USER\" -d $db -c \"
      SELECT 'tables=' || count(*) FROM information_schema.tables WHERE table_schema='public';\"
  " 2>/dev/null || true
}

if [ "$MODE" = "rehearse" ]; then
  log "REHEARSE: restoring into throwaway DB $REHEARSE_DB (non-destructive) ..."
  kubectl -n "$GREEN_NS" exec -i "$GREEN_POD" -- sh -c "
    psql -U \"\$POSTGRES_USER\" -c 'DROP DATABASE IF EXISTS $REHEARSE_DB;'
    psql -U \"\$POSTGRES_USER\" -c 'CREATE DATABASE $REHEARSE_DB;'
  "
  START=$(date +%s)
  restore_into "$REHEARSE_DB" "--no-owner --no-privileges"
  END=$(date +%s)
  log "rehearsal restore took $((END - START))s; public $(rowcounts "$REHEARSE_DB")"
  kubectl -n "$GREEN_NS" exec -i "$GREEN_POD" -- sh -c "
    psql -U \"\$POSTGRES_USER\" -c 'DROP DATABASE IF EXISTS $REHEARSE_DB;'
    rm -f /tmp/migrate.dump
  "
  log "rehearsal complete — throwaway DB dropped. Nothing on green was changed."
elif [ "$MODE" = "final" ]; then
  printf '\033[1;33m[migrate] FINAL restore into %s (destructive: --clean). Blue app should be stopped. Type YES to proceed: \033[0m' "$TARGET_DB"
  read -r ans; [ "$ans" = "YES" ] || die "aborted"
  log "restoring into $TARGET_DB (--clean --if-exists) ..."
  START=$(date +%s)
  restore_into "$TARGET_DB" "--clean --if-exists --no-owner --no-privileges"
  END=$(date +%s)
  log "final restore took $((END - START))s; public $(rowcounts "$TARGET_DB")"
  kubectl -n "$GREEN_NS" exec -i "$GREEN_POD" -- rm -f /tmp/migrate.dump
  log "final restore complete. Verify the green api, then flip DNS (runbook-cutover step 4)."
else
  die "unknown mode '$MODE' (use: rehearse | final)"
fi

rm -f "$DUMP"
log "done."
