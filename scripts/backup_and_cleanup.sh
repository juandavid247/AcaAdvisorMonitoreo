#!/usr/bin/env bash
# ==============================================================================
# ACA ADVISOR S.A.S. - Backup Diario Automatico y Retencion de Disco
# Respalda MySQL + MongoDB (14 dias) y purga capturas/logs pesados antiguos
# ==============================================================================
set -euo pipefail

BASE_DIR="/home/juanda/emp-monitor"
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

log "=== Iniciando respaldo y mantenimiento ACA Advisor (${TS}) ==="

# 1. Backup MySQL
MYSQL_OUT="${MYSQL_DIR}/empmonitor_${TS}.sql.gz"
if docker --context default exec emp_mysql mysqldump -uempuser -pemppassword --single-transaction --routines --triggers empmonitor 2>/dev/null | gzip -9 > "${MYSQL_OUT}"; then
    log "[OK] Backup MySQL creado: ${MYSQL_OUT} ($(du -h "${MYSQL_OUT}" | cut -f1))"
else
    log "[ERROR] Fallo backup MySQL"
    rm -f "${MYSQL_OUT}"
fi

# 2. Backup MongoDB
MONGO_OUT="${MONGO_DIR}/empmonitor_${TS}.archive.gz"
if docker --context default exec emp_mongodb mongodump --uri="mongodb://empuser:emppassword@localhost:27017/empmonitor?authSource=admin" --archive --gzip 2>/dev/null > "${MONGO_OUT}"; then
    log "[OK] Backup MongoDB creado: ${MONGO_OUT} ($(du -h "${MONGO_OUT}" | cut -f1))"
else
    log "[ERROR] Fallo backup MongoDB"
    rm -f "${MONGO_OUT}"
fi

# 3. Retencion de backups locales (>14 dias)
find "${MYSQL_DIR}" -type f -name "*.sql.gz" -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true
find "${MONGO_DIR}" -type f -name "*.archive.gz" -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true

# 4. Retencion de capturas de pantalla (>45 dias) dentro de emp_store_logs_api
docker --context default exec emp_store_logs_api sh -c "find /app/shared_screenshots -type f -mtime +${SCREENSHOT_RETENTION_DAYS} -delete 2>/dev/null || true"
log "[OK] Limpieza de capturas >${SCREENSHOT_RETENTION_DAYS} dias completada."

# 5. Retencion de logs crudos pesados en MongoDB (>60 dias)
CUTOFF_ISO="$(date -u -d "${MONGO_RAW_RETENTION_DAYS} days ago" '+%Y-%m-%dT%H:%M:%SZ')"
docker --context default exec emp_mongodb mongosh "mongodb://empuser:emppassword@localhost:27017/empmonitor?authSource=admin" --quiet --eval "
  const cutoff = new Date('${CUTOFF_ISO}');
  const r1 = db.useractivitydatas.deleteMany({ createdAt: { \$lt: cutoff } });
  const r2 = db.usersystemlogs.deleteMany({ createdAt: { \$lt: cutoff } });
  print('Purged useractivitydatas=' + r1.deletedCount + ', usersystemlogs=' + r2.deletedCount);
" >> "${LOG_FILE}" 2>&1 || true

# 6. Uso actual de disco
DISK_USAGE="$(df -h / | awk 'NR==2 {print $5 " usado (" $4 " libre)"}')"
log "[INFO] Estado del disco: ${DISK_USAGE}"
log "=== Respaldo y mantenimiento finalizado ==="
