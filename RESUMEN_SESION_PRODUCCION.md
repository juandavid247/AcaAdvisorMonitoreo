# Resumen de Sesión — Endurecimiento a Producción, Branding y Tema Oscuro (ACA Advisor v3.0.4)

**Fecha:** 2026-11-19  
**Repositorio GitHub:** `https://github.com/juandavid247/AcaAdvisorMonitoreo.git` (rama `main`)  
**Servidor Central:** `192.168.0.155`  
**Panel Web:** `http://192.168.0.155:8081`  
**Estado:** 11 / 11 contenedores Docker activos y en estado `(healthy)`.

---

## 1. Cambios realizados y verificados hoy

### Repositorio y Documentación
- Remoto `origin` migrado a `https://github.com/juandavid247/AcaAdvisorMonitoreo.git`.
- `README.md` reescrito completamente con identidad **ACA Advisor** (sin referencias a EmpMonitor/EmpCloud).

### Bloque A — Seguridad Backend y Docker (`bc964a9`)
- **Cierre de bypass de autenticación (Crítico):** `POST /api/v3/auth/admin` restringido a loopback + secreto interno (`X-Internal-Auth`); `POST /api/v1/auth/admin` valida email/usuario, usa `timingSafeEqual` y aplica rate limiting.
- **Capturas firmadas HMAC:** `Backend/admin/src/utils/helpers/screenshotSigner.js` protege `/screenshots-static` con firmas temporales (`exp` + `sig`) y bloquea accesos sin firma (`403`) y path traversal.
- **Hardening de APIs:** Swagger deshabilitado en producción (`ENABLE_SWAGGER=false`), CORS restringido por `ALLOWED_ORIGINS`, rate limiting en `desktop` auth, soporte opcional para `AGENT_ENROLLMENT_KEY` y protección contra path traversal en `/temp/*`.
- **Secretos y Docker:** contraseñas y claves movidas fuera de Git hacia `.env` (plantilla en `.env.example`), Redis con autenticación obligatoria (`requirepass` + persistencia AOF), `healthcheck`, `mem_limit` y rotación de logs (`10m x 3`) en los 11 servicios.

### Bloque B — Reverse Proxy Unificado y HTTPS/WSS (`bc964a9`)
- `Frontend/nginx.conf` unificado como proxy inverso para SPA, `/api/`, `/screenshots-static/`, `/temp/`, `/logs/`, `/desktop/`, `/downloads/` y WebSockets (`/ws/realtime`, `/ws/notification`, `/ws/remote`) con cabeceras de seguridad.
- Frontend actualizado a URLs mismo-origen (`/api/v3`) y detección automática `ws://` / `wss://`.
- Puertos internos (`3000`, `3002`, `3005`, `8080`, `3306`, `27017`, `6379`) cerrados a `127.0.0.1`; se mantienen `3001`, `3003`, `3004` y `8081` para compatibilidad con agentes actuales.
- Overlay HTTPS/WSS con Caddy listo en `docker-compose.tls.yml`, `deploy/proxy/Caddyfile` y `deploy/proxy/README_HTTPS.md`.

### Bloque C — Agente Windows y Respaldos (`bc964a9`)
- **Permisos ACL endurecidos:** eliminada la escalada de privilegios (`Users:FullControl`) sobre ejecutables y scripts `.ps1` en `fix-agent.ps1` / `register.ps1` e instaladores `.iss`, usando SIDs universales (`SYSTEM`/`Administrators:F`, `Users:RX`) y escritura aislada en `logs/` y `failed_screenshots/`.
- **Estabilidad del agente:** Mutex global en `live-stream.ps1`, rotación de logs a 5 MB en `live-stream.ps1` y `dlp-monitor.ps1`, limpieza periódica de trabajos de impresión en memoria y soporte `-UseHttps` / `-EnrollmentKey`.
- **Respaldos y rotación:** `scripts/backup_and_cleanup.sh` lee credenciales desde `.env`, valida integridad con `gzip -t` y soporta replicación remota (`rclone`/`rsync`). Cron activo a las `02:30`. Creado `scripts/rotate_credentials.sh` para rotación atómica en vivo.

### Mejoras Visuales, Branding `logoaca.ico` y Tema Oscuro (`ad51a97`)
- Generados iconos multi-resolución desde `~/Descargas/logos/logoaca.ico` para Web (`favicon.ico`, `favicon.png`, sidebars, badges) y Windows (`aca-advisor.ico`, `wizard-side.png`, `logo-isotype.png`).
- **Web:** pantallas de login centradas (`admin-login`, `nonadmin-login`, `employee-login`, `reset-password`, `LoginPage`) con logotipo grande y centrado; sidebars con logotipos ampliados; capa global de tema oscuro de alto contraste en `Frontend/src/index.css` corrigiendo textos oscuros heredados, tablas, modales, inputs y gráficos.
- **Windows v3.0.4:** `aca-agent.exe` y `empmonitor.exe` actualizados con icono `logoaca.ico` (`128x128`), banner de login centrado con logotipo grande (`943x909`), cabecera ampliada (`450x78`) y QSS centrado. Recompilados con Inno Setup `ACA_Advisor_Agent_Setup.exe`, `ACA_Advisor_Agent_Visible_Setup.exe` y los 3 paquetes `.zip` en `Frontend/public/downloads/`.

---

## 2. Pendientes para continuar mañana

1. **Revisar visualmente** el panel web (`Ctrl + Shift + R` en modo claro y modo oscuro) y probar la instalación de los nuevos instaladores Windows v3.0.4 en un equipo cliente.
2. **Rotar credenciales de producción** (Admin, MySQL, MongoDB, Redis, JWT):
   ```bash
   cd /home/juanda/emp-monitor
   ./scripts/rotate_credentials.sh 'TuNuevaClaveSegura#2026'
   ```
3. **Activar HTTPS / WSS** con `docker-compose.tls.yml` (definir si será dominio público con Let's Encrypt o red local LAN con CA interna).
4. **Configurar respaldo externo (off-site)** en `.env` (`BACKUP_REMOTE_DEST` con `rclone` o `BACKUP_RSYNC_DEST` con `rsync`) y probar una restauración completa.
5. **Seguridad de cuenta GitHub:** revocar el Personal Access Token antiguo en `https://github.com/settings/tokens` y actualizar `/home/juanda/.git-credentials` (o migrar a SSH).
