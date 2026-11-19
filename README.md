<a id="readme-top"></a>

<div align="center">
  <h1>ACA Advisor</h1>
  <p><i>Plataforma integral de monitoreo laboral, productividad y prevención de pérdida de datos (DLP)</i></p>

  <p>
    <img src="https://img.shields.io/github/license/juandavid247/AcaAdvisorMonitoreo" alt="License: AGPL-3.0">
    <img src="https://img.shields.io/github/last-commit/juandavid247/AcaAdvisorMonitoreo" alt="Last Commit">
    <img src="https://img.shields.io/github/issues/juandavid247/AcaAdvisorMonitoreo" alt="GitHub Issues">
    <img src="https://img.shields.io/github/stars/juandavid247/AcaAdvisorMonitoreo" alt="GitHub Stars">
  </p>

  <p>
    <a href="#-características-principales">✨ Características</a> &ensp;•&ensp;
    <a href="#-arquitectura-y-tecnologías">🛠️ Tecnologías</a> &ensp;•&ensp;
    <a href="#-instalación-y-despliegue">🚀 Despliegue</a> &ensp;•&ensp;
    <a href="https://github.com/juandavid247/AcaAdvisorMonitoreo/issues/new">🐛 Reportar un problema</a>
  </p>
</div>

---

## ➤ Introducción

**ACA Advisor** es una plataforma completa de **monitoreo de estaciones de trabajo, gestión de productividad y seguridad corporativa** diseñada para equipos presenciales, remotos e híbridos. Centraliza en un único panel el seguimiento de horarios, actividad en aplicaciones y sitios web, capturas de pantalla con almacenamiento local, monitoreo en tiempo real y controles avanzados de prevención de pérdida de datos (DLP).

---

## ➤ Tabla de Contenidos

- [Introducción](#-introducción)
- [Características Principales](#-características-principales)
- [Agentes ACA Advisor](#-agentes-aca-advisor)
- [Arquitectura y Tecnologías](#-arquitectura-y-tecnologías)
- [Instalación y Despliegue](#-instalación-y-despliegue)
- [Respaldos y Seguridad](#-respaldos-y-seguridad)
- [Licencia](#-licencia)

---

## ➤ Características Principales

### 📊 Monitoreo de Productividad y Actividad
- **Tiempo activo, de oficina e inactivo:** Registro automatizado de horas trabajadas, pausas y periodos de inactividad con métricas precisas de productividad.
- **Uso de aplicaciones y sitios web:** Clasificación de actividad productiva, neutral e improductiva por usuario, equipo y departamento.
- **Monitoreo en tiempo real y capturas locales:** Visualización en vivo y almacenamiento local de capturas de pantalla sin depender de servicios externos.
- **Reportes automatizados:** Exportación de métricas y tendencias para toma de decisiones, auditorías y gestión operativa.

### 🕒 Control de Asistencia y Horarios
- **Registro de entradas y salidas:** Control automático de turnos, puntualidad, ausencias y horas extra.
- **Hojas de tiempo (Timesheets):** Filtros avanzados por departamento, ubicación, empleado y rango de fechas.

### 🛡️ Seguridad y Prevención de Pérdida de Datos (DLP)
- **Detección de amenazas internas:** Alertas en tiempo real ante comportamientos sospechosos o accesos no autorizados.
- **Control de dispositivos y archivos:** Monitoreo de actividad USB, transferencias de archivos y sincronización completa de políticas DLP.
- **Registro de impresiones (Print Logs API):** Auditoría detallada de documentos enviados a impresión.

### 📁 Gestión de Proyectos y Equipos
- **Directorio centralizado de empleados:** Información de rol, departamento, ubicación y estado del equipo asignado.
- **Seguimiento de tareas y proyectos:** Asignación de actividades, control de avances y distribución de carga de trabajo.

---

## ➤ Agentes ACA Advisor

ACA Advisor incluye agentes optimizados para despliegue en **Windows** (disponibles en `Frontend/public/downloads/`):

- **Modo Silencioso (Stealth):** `ACA_Advisor_Agent_Setup.exe` / `ACA_Advisor_Agent_Setup.zip`
- **Modo Visible:** `ACA_Advisor_Agent_Visible_Setup.exe` / `ACA_Advisor_Agent_Visible_Setup.zip`
- **Kit de Despliegue:** `ACA_Advisor_Agent_Deployment_Kit.zip`

Características del agente:
- Auto-registro y aprovisionamiento dinámico de equipos.
- Soporte para re-registro de empleados existentes y detección automática del adaptador de red activo.
- Configuración de permisos ACL y registro de Windows mediante scripts automatizados.

---

## ➤ Arquitectura y Tecnologías

| Componente | Tecnología | Descripción |
| :--- | :--- | :--- |
| **Agente de Escritorio** | **Qt (C++)** | Agente multiplataforma de alto rendimiento para recolección de actividad y telemetría. |
| **Frontend Web** | **Laravel (PHP / Blade)** | Panel administrativo, gestión de usuarios, reportes y descarga de agentes. |
| **Backend & APIs** | **Node.js** | Servicios REST, procesamiento en tiempo real, DLP y comunicación con agentes. |
| **Mensajería en Tiempo Real** | **Redis (Pub/Sub)** | Sincronización de eventos en vivo y monitoreo en tiempo real. |
| **Infraestructura** | **Docker & Docker Compose** | Contenerización de servicios, aislamiento de puertos y despliegue reproducible. |

---

## ➤ Instalación y Despliegue

### Requisitos Previos
- **Docker** y **Docker Compose** instalados en el servidor.
- **Git** para clonar el repositorio.

### Pasos Básicos

1. **Clonar el repositorio:**
   ```bash
   git clone https://github.com/juandavid247/AcaAdvisorMonitoreo.git
   cd AcaAdvisorMonitoreo
   ```

2. **Configurar variables de entorno y secretos:**
   Copia la plantilla segura y configura tus contraseñas/claves:
   ```bash
   cp .env.example .env
   chmod 600 .env
   ```

3. **Levantar los servicios con Docker Compose:**
   ```bash
   docker compose up -d --build
   ```
   Para habilitar **HTTPS / WSS automático** (Caddy en puertos `80`/`443`), consulta [deploy/proxy/README_HTTPS.md](deploy/proxy/README_HTTPS.md) y levanta:
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d
   ```

4. **Verificar el estado de los contenedores:**
   ```bash
   docker compose ps
   ```

---

## ➤ Respaldos y Seguridad

- **Secretos aislados fuera de Git:** Todas las credenciales de MySQL, MongoDB, Redis, JWT y panel administrador se gestionan exclusivamente en `.env` (ignorado por Git). Usa `scripts/rotate_credentials.sh` para rotar claves en vivo de forma segura.
- **Reverse Proxy unificado y puertos endurecidos:** MySQL, MongoDB, Redis y los microservicios internos se exponen únicamente en `127.0.0.1` o red interna de Docker; las capturas locales utilizan URLs firmadas HMAC con expiración corta.
- **Respaldos diarios automatizados y verificados:** `scripts/backup_and_cleanup.sh` respalda MySQL y MongoDB (verificando integridad `gzip`), limpia datos antiguos y soporta replicación remota vía `rclone` o `rsync`.

---

## ➤ Licencia

![License: AGPL-3.0](https://img.shields.io/badge/License-AGPLv3-green.svg)

Este proyecto se distribuye bajo la licencia **GNU Affero General Public License v3.0 (AGPL-3.0)**. Consulta el archivo [LICENSE](LICENSE) para más detalles.

<p align="right">(<a href="#readme-top">volver arriba</a>)</p>
