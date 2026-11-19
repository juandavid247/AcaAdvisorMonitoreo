# Guía de Activación HTTPS / WSS — ACA Advisor

La plataforma ya opera a través de un único proxy interno (`emp_frontend`) que centraliza panel web, APIs, capturas firmadas y WebSockets. Para cifrar todo el tráfico con **HTTPS y WSS** (puerto `443`), usa el overlay [docker-compose.tls.yml](../../docker-compose.tls.yml) con Caddy.

---

## Opción 1: Con dominio público (Recomendada — Let's Encrypt automático)

1. Apunta un registro DNS `A` (ej. `monitoreo.tuempresa.com`) a la IP pública de tu servidor y abre únicamente los puertos `80` y `443` en el firewall.
2. Agrega en `.env`:
   ```env
   SITE_ADDRESS=monitoreo.tuempresa.com
   TLS_MODE=admin@tuempresa.com
   ALLOWED_ORIGINS=https://monitoreo.tuempresa.com
   ```
3. Levanta el stack con TLS:
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d
   ```
4. Despliega o actualiza los agentes Windows apuntando al dominio con `-UseHttps`:
   ```powershell
   & ([scriptblock]::Create((irm 'https://monitoreo.tuempresa.com/downloads/fix-agent.ps1'))) -ServerHost 'monitoreo.tuempresa.com' -UseHttps
   ```

---

## Opción 2: Solo red local (LAN con IP o dominio interno)

1. Agrega en `.env`:
   ```env
   SITE_ADDRESS=https://192.168.0.155
   TLS_MODE=internal
   ALLOWED_ORIGINS=https://192.168.0.155,http://192.168.0.155:8081
   ```
2. Levanta Caddy:
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d
   ```
3. Exporta la CA raíz interna de Caddy e instálala en los equipos Windows (una sola vez por equipo o por GPO) para que el navegador y el agente Windows confíen en el certificado sin advertencias:
   ```bash
   docker cp emp_caddy_tls:/data/caddy/pki/authorities/local/root.crt ./aca-advisor-root-ca.crt
   ```
   En Windows (PowerShell como Administrador):
   ```powershell
   Import-Certificate -FilePath .\aca-advisor-root-ca.crt -CertStoreLocation Cert:\LocalMachine\Root
   ```
4. Actualiza los agentes a HTTPS:
   ```powershell
   & ([scriptblock]::Create((irm 'https://192.168.0.155/downloads/fix-agent.ps1'))) -ServerHost '192.168.0.155' -UseHttps
   ```

---

## Paso Final (cuando todos los agentes ya usen HTTPS)

Una vez confirmes que todos los equipos Windows reportan por el puerto `443`, cierra en el firewall del servidor (`ufw`) los puertos legacy HTTP (`3001`, `3003`, `3004`, `8081`), dejando únicamente `80/tcp`, `443/tcp` y `22/tcp` (SSH).
