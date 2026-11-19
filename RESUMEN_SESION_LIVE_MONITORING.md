# Resumen de Sesión — Monitoreo de Pantalla en Vivo (ACA Advisor / EmpMonitor)

**Fecha:** 2026-11-18  
**Servidor Central:** `192.168.0.155`  
**Panel Web:** `http://192.168.0.155:8081/admin/live-monitoring`  
**Estado:** Funcionando correctamente (pantalla en vivo operativa).

---

## 1. Causa raíz identificada
- El binario `aca-agent.exe` (Qt C++) reportaba actividad (teclado, ratón, ventanas abiertas en Chrome) vía HTTP al puerto `3001`, pero **no incluía el módulo `Qt5WebSockets`** para conectarse al servidor de streaming en tiempo real (`ws://192.168.0.155:3003`).
- Adicionalmente, existían bloqueos previos en:
  1. Validación estricta de nombres de archivo de capturas en `emp_store_logs_api` (HTTP 406).
  2. Respuesta de licencia/organización en `emp_desktop` (`/api/v3/get-organization-detail`).
  3. Interpolación de `$ServerHost:puerto` en PowerShell (corregido a `${ServerHost}:puerto`).
  4. Falso positivo de Windows Defender AMSI cuando el lanzador `.vbs` estaba embebido en `fix-agent.ps1`.

---

## 2. Cambios realizados y archivos actualizados

### Backend (código fuente actualizado y desplegado en contenedores activos)
- `Backend/realtime/source/handler/service.js` (`emp_realtime`, puerto `3003`):
  - Propagación inmediata de frames `start_image_stream` hacia el navegador del administrador.
  - Almacenamiento en caché Redis (`latest_screenshot:<userId>` y `latest_screenshot:<empId>`) para mostrar la pantalla de inmediato al abrir o recargar el panel.
  - Activación automática del stream si el agente se conecta cuando el administrador ya está mirando la pantalla.
- `Backend/store-logs-api/src/modules/v1/desktop/utils/file.utils.ts`, `service/screenshot.service.ts`, `service/user-feature.service.ts`, `src/main.ts` (`emp_store_logs_api`, puerto `3001`):
  - Filtro de imágenes flexible (`jpg|jpeg|png|gif|webp`), extracción flexible de fecha, permisos completos de captura y registro de peticiones HTTP.
- `Backend/desktop/src/routes/v3/open/open.service.js` y `auth/services/auth.middleware.js` (`emp_desktop`, puerto `3004`):
  - Soporte para `req.body.id` en `get-organization-detail` y configuración de licencia activa y frecuencias de captura.

### Agente Windows (descargables desde el servidor web)
- `Frontend/public/downloads/fix-agent.ps1` (sincronizado con `Frontend/fix-agent.ps1` y `deploy/windows_agent/bin/register.ps1`):
  - Registra el equipo en `http://192.168.0.155:3004/api/v3/auth/register`.
  - Agrega exclusiones en Windows Defender.
  - Configura `config.js`, `config.json` y el Registro de Windows (`QSettings`).
  - Descarga `live-stream.ps1` y crea `configs/stream.json` dentro de `C:\Program Files\ACA Advisor Agent\`.
  - Configura autoarranque al iniciar sesión (`ACAAdvisorAgent` y `ACAAdvisorLiveStream`).
- `Frontend/public/downloads/live-stream.ps1`:
  - Módulo nativo .NET para Windows que inicia sesión en el servidor, se conecta por WebSocket a `ws://192.168.0.155:3003` y transmite la pantalla en vivo cada 1.5 segundos mientras el administrador observa el monitor (y entra en modo ahorro cuando no hay nadie mirando).

---

## 3. Comando para instalar/activar en otros equipos Windows
Abrir **PowerShell como Administrador** en cada equipo cliente y ejecutar:

```powershell
irm 'http://192.168.0.155:8081/downloads/fix-agent.ps1?v=9' | iex
```

---

## 4. Pendientes sugeridos para retomar mañana
1. Ejecutar el comando anterior en los demás equipos Windows que falten (por ejemplo, el equipo de Marvin Montoya `DESKTOP-KS57GP5`).
2. Reiniciar uno de los equipos Windows configurados para confirmar que `ACAAdvisorAgent` y `ACAAdvisorLiveStream` arrancan automáticamente tras el reinicio.
3. Si se requiere reconstruir imágenes Docker en el futuro, ejecutar `docker compose build` para que los cambios del código fuente queden fijos en las imágenes base.
4. Opcional: empaquetar `live-stream.ps1` y el flujo actualizado dentro del instalador `ACA_Advisor_Agent_Setup.exe`.
