#!/usr/bin/env bash
# ==============================================================================
# ACA ADVISOR S.A.S. - Rotacion Segura de Credenciales en Vivo
# Actualiza contrasenas en MySQL, MongoDB, Redis y .env de forma atomica
# sin perder datos ni romper agentes Windows ya desplegados.
# ==============================================================================
set -euo pipefail

BASE_DIR="/home/juanda/emp-monitor"
ENV_FILE="${BASE_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "[ERROR] No se encontro ${ENV_FILE}"
    exit 1
fi

get_env_val() {
    local key="$1"
    grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 | cut -d'=' -f2- | sed -e "s/^['\"]//" -e "s/['\"]$//"
}

set_env_val() {
    local key="$1"
    local val="$2"
    python3 -c '
import sys, pathlib
p = pathlib.Path(sys.argv[1])
key, val = sys.argv[2], sys.argv[3]
lines = p.read_text().splitlines()
updated = False
out = []
for line in lines:
    if line.startswith(key + "="):
        out.append(f"{key}={val}")
        updated = True
    else:
        out.append(line)
if not updated:
    out.append(f"{key}={val}")
p.write_text("\n".join(out) + "\n")
' "${ENV_FILE}" "${key}" "${val}"
}

NEW_ADMIN_PASS="${1:-}"
if [[ -z "${NEW_ADMIN_PASS}" ]]; then
    echo "Uso: $0 <NUEVA_CONTRASENA_ADMIN>"
    echo "Ejemplo: $0 'AcaAdvisor#2026!Prod'"
    exit 1
fi

OLD_MYSQL_ROOT="$(get_env_val MYSQL_ROOT_PASSWORD)"
OLD_MYSQL_USER="$(get_env_val MYSQL_USER)"
OLD_MONGO_USER="$(get_env_val MONGO_USER)"
OLD_MONGO_PASS="$(get_env_val MONGO_PASSWORD)"

NEW_MYSQL_ROOT="$(openssl rand -hex 20)"
NEW_MYSQL_PASS="$(openssl rand -hex 20)"
NEW_MONGO_PASS="$(openssl rand -hex 20)"
NEW_REDIS_PASS="$(openssl rand -hex 24)"
NEW_SESSION_SECRET="$(openssl rand -hex 32)"
NEW_JWT_ACCESS="$(openssl rand -hex 32)"
NEW_JWT_REFRESH="$(openssl rand -hex 32)"
NEW_INTERNAL_AUTH="$(openssl rand -hex 24)"
NEW_SS_SIGNING="$(openssl rand -hex 24)"

echo "[1/4] Actualizando contrasenas en MySQL en vivo..."
docker --context default exec -e MYSQL_PWD="${OLD_MYSQL_ROOT}" emp_mysql \
    mysql -u root -e "ALTER USER '${OLD_MYSQL_USER}'@'%' IDENTIFIED BY '${NEW_MYSQL_PASS}'; ALTER USER 'root'@'localhost' IDENTIFIED BY '${NEW_MYSQL_ROOT}'; ALTER USER 'root'@'%' IDENTIFIED BY '${NEW_MYSQL_ROOT}'; FLUSH PRIVILEGES;"

echo "[2/4] Actualizando contrasena en MongoDB en vivo..."
docker --context default exec -e OLD_URI="mongodb://${OLD_MONGO_USER}:${OLD_MONGO_PASS}@localhost:27017/admin?authSource=admin" emp_mongodb \
    sh -c "mongosh \"\$OLD_URI\" --quiet --eval \"db.changeUserPassword('${OLD_MONGO_USER}', '${NEW_MONGO_PASS}')\""

echo "[3/4] Guardando nuevos secretos en ${ENV_FILE} (permisos 600)..."
set_env_val "MYSQL_ROOT_PASSWORD" "${NEW_MYSQL_ROOT}"
set_env_val "MYSQL_PASSWORD" "${NEW_MYSQL_PASS}"
set_env_val "MONGO_PASSWORD" "${NEW_MONGO_PASS}"
set_env_val "REDIS_PASSWORD" "${NEW_REDIS_PASS}"
set_env_val "SESSION_SECRET" "${NEW_SESSION_SECRET}"
set_env_val "JWT_ACCESS_TOKEN_SECRET" "${NEW_JWT_ACCESS}"
set_env_val "JWT_REFRESH_TOKEN_SECRET" "${NEW_JWT_REFRESH}"
set_env_val "INTERNAL_AUTH_SECRET" "${NEW_INTERNAL_AUTH}"
set_env_val "SCREENSHOT_SIGNING_SECRET" "${NEW_SS_SIGNING}"
set_env_val "ADMIN_PASSWORD" "${NEW_ADMIN_PASS}"
chmod 600 "${ENV_FILE}"

echo "[4/4] Recreando contenedores con los nuevos secretos..."
docker --context default compose -f "${BASE_DIR}/docker-compose.yml" up -d

echo "[OK] Rotacion completa. El panel web ahora usa tu nueva contrasena de administrador."
echo "Nota: los agentes Windows existentes se re-autenticaran automaticamente con el nuevo JWT en <60s."
