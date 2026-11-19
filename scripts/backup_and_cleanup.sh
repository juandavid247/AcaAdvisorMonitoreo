#!/usr/bin/env bash
# ==============================================================================
# ACA ADVISOR S.A.S. - Backup Diario Automatico, Replicacion Remota y Retencion
# Lee credenciales de .env (sin secretos hardcodeados en el script).
# ==============================================================================
set -euo pipefail

BASE_DIR="/home/juanda/emp-monitor"
ENV_FILE="${BASE_DIR}/.env"
BACKUP_DIR="${BASE_DIR}/backups"
MYSQL_DIR="${BACKUP_DIR}/mysql"
MONGO_DIR="${BACKUP_DIR}/mongodb"
LOG_FILE="${BACKUP_DIR}/backup.log"

BACKUP_RETENTION_DAYS=14
SCREENSHOT_RETENTION_DAYS=45
MONGO_RAW_RETENTION_DAYS=60

mkdir -p "${MYSQL_DIR}" "${MONGO_DIR}"
TS="$(date '+%Y-%m-%d_%H-%M-%S')"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "${LOG_FILE}"
}

if [[ ! -f "${ENV_FILE}" ]]; then
    log "[ERROR] No se encontro ${ENV_FILE}. Abortando respaldo."
    exit 1
fi

# Cargar variables clave desde .env de forma segura (sin ejecutar codigo arbitrario)
get_env_val() {
    local key="$1"
    local default_val="${2:-}"
    local val
    val="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 | cut -d'=' -f2- | sed -e "s/^['\"]//" -e "s/['\"]$//")" || true
    echo "${val:-$default_val}"
}

MYSQL_USER="$(get_env_val MYSQL_USER empuser)"
MYSQL_PASSWORD="$(get_env_val MYSQL_PASSWORD)"
MYSQL_DATABASE="$(get_env_val MYSQL_DATABASE empmonitor)"
MONGO_USER="$(get_env_val MONGO_USER empuser)"
MONGO_PASSWORD="$(get_env_val MONGO_PASSWORD)"
MONGO_DATABASE="$(get_env_val MONGO_DATABASE empmonitor)"
BACKUP_REMOTE_DEST="$(get_env_val BACKUP_REMOTE_DEST)"
BACKUP_RSYNC_DEST="$(get_env_val BACKUP_RSYNC_DEST)"

log "=== Iniciando respaldo y mantenimiento ACA Advisor (${TS}) ==="
FAILURES=0

# 1. Backup MySQL (contrasena por variable de entorno, no visible en ps)
MYSQL_OUT="${MYSQL_DIR}/empmonitor_${TS}.sql.gz"
if docker --context default exec -e MYSQL_PWD="${MYSQL_PASSWORD}" emp_mysql \
    mysqldump -u "${MYSQL_USER}" --single-transaction --routines --triggers "${MYSQL_DATABASE}" 2>/dev/null \
    | gzip -9 > "${MYSQL_OUT}" && gzip -t "${MYSQL_OUT}" 2>/dev/null && [[ -s "${MYSQL_OUT}" ]]; then
    chmod 600 "${MYSQL_OUT}"
    log "[OK] Backup MySQL creado y verificado: ${MYSQL_OUT} ($(du -h "${MYSQL_OUT}" | cut -f1))"
else
    log "[ERROR] Fallo backup MySQL"
    rm -f "${MYSQL_OUT}"
    FAILURES=$((FAILURES + 1))
fi

# 2. Backup MongoDB (verificado con gzip -t)
MONGO_OUT="${MONGO_DIR}/empmonitor_${TS}.archive.gz"
if docker --context default exec -e MONGO_URI="mongodb://${MONGO_USER}:${MONGO_PASSWORD}@localhost:27017/${MONGO_DATABASE}?authSource=admin" emp_mongodb \
    sh -c 'mongodump --uri="$MONGO_URI" --archive --gzip' 2>/dev/null > "${MONGO_OUT}" \
    && gzip -t "${MONGO_OUT}" 2>/dev/null && [[ -s "${MONGO_OUT}" ]]; then
    chmod 600 "${MONGO_OUT}"
    log "[OK] Backup MongoDB creado y verificado: ${MONGO_OUT} ($(du -h "${MONGO_OUT}" | cut -f1))"
else
    log "[ERROR] Fallo backup MongoDB"
    rm -f "${MONGO_OUT}"
    FAILURES=$((FAILURES + 1))
fi

# 3. Retencion de backups locales (>14 dias)
find "${MYSQL_DIR}" -type f -name "*.sql.gz" -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true
find "${MONGO_DIR}" -type f -name "*.archive.gz" -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true

# 4. Replicacion externa (off-site) si esta configurada en .env
if [[ -n "${BACKUP_REMOTE_DEST}" ]] && command -v rclone >/dev/null 2>&1; then
    if rclone sync "${MYSQL_DIR}" "${BACKUP_REMOTE_DEST}/mysql" --transfers 2 >> "${LOG_FILE}" 2>&1 \
       && rclone sync "${MONGO_DIR}" "${BACKUP_REMOTE_DEST}/mongodb" --transfers 2 >> "${LOG_FILE}" 2>&1; then
        log "[OK] Respaldos replicados via rclone a ${BACKUP_REMOTE_DEST}"
    else
        log "[ERROR] Fallo replicacion rclone a ${BACKUP_REMOTE_DEST}"
        FAILURES=$((FAILURES + 1))
    fi
fi

if [[ -n "${BACKUP_RSYNC_DEST}" ]] && command -v rsync >/dev/null 2>&1; then
    if rsync -az --delete "${MYSQL_DIR}" "${MONGO_DIR}" "${BACKUP_RSYNC_DEST}/" >> "${LOG_FILE}" 2>&1; then
        log "[OK] Respaldos replicados via rsync a ${BACKUP_RSYNC_DEST}"
    else
        log "[ERROR] Fallo replicacion rsync a ${BACKUP_RSYNC_DEST}"
        FAILURES=$((FAILURES + 1))
    fi
fi

# 5. Retencion de capturas de pantalla (>45 dias) dentro de emp_store_logs_api
docker --context default exec emp_store_logs_api sh -c "find /app/shared_screenshots -type f -mtime +${SCREENSHOT_RETENTION_DAYS} -delete 2>/dev/null || true"
log "[OK] Limpieza de capturas >${SCREENSHOT_RETENTION_DAYS} dias completada."

# 6. Retencion de logs crudos pesados en MongoDB (>60 dias)
CUTOFF_ISO="$(date -u -d "${MONGO_RAW_RETENTION_DAYS} days ago" '+%Y-%m-%dT%H:%M:%SZ')"
docker --context default exec -e MONGO_URI="mongodb://${MONGO_USER}:${MONGO_PASSWORD}@localhost:27017/${MONGO_DATABASE}?authSource=admin" emp_mongodb \
    sh -c "mongosh \"\$MONGO_URI\" --quiet --eval \"
      const cutoff = new Date('${CUTOFF_ISO}');
      const r1 = db.useractivitydatas.deleteMany({ createdAt: { \\\$lt: cutoff } });
      const r2 = db.usersystemlogs.deleteMany({ createdAt: { \\\$lt: cutoff } });
      print('Purged useractivitydatas=' + r1.deletedCount + ', usersystemlogs=' + r2.deletedCount);
    \"" >> "${LOG_FILE}" 2>&1 || true

# 7. Uso actual de disco y alerta si >85%
DISK_PCT="$(df -h / | awk 'NR==2 {gsub("%","",$5); print $5}')"
DISK_USAGE="$(df -h / | awk 'NR==2 {print $5 " usado (" $4 " libre)"}')"
log "[INFO] Estado del disco: ${DISK_USAGE}"
if [[ "${DISK_PCT:-0}" -ge 85 ]]; then
    log "[WARN] Uso de disco alto (${DISK_PCT}%)! Revisar almacenamiento."
fi

log "=== Respaldo y mantenimiento finalizado (fallos=${FAILURES}) ==="
exit "${FAILURES}"
