# Guía de Compilación y Despliegue del Instalador de Windows — ACA ADVISOR S.A.S.

Esta carpeta contiene todos los recursos necesarios para empaquetar, personalizar y distribuir el **Agente de Monitoreo y Productividad de ACA ADVISOR S.A.S.** para computadores con sistema operativo Windows (Windows 10, Windows 11 y Windows Server).

---

## 1. Contenido del Paquete

- `aca-advisor.ico`: Icono de alta resolución para Windows (16x16 hasta 256x256) con la identidad de ACA ADVISOR.
- `logo-horizontal.png` y `logo-isotype.png`: Banners e insignias de marca utilizados por el asistente de instalación.
- `config.js` y `config.json`: Archivos de configuración predeterminados que apuntan al servidor de ACA ADVISOR.
- `installer.iss`: Script de compilación para **Inno Setup Compiler** que genera el archivo `ACA_Advisor_Agent_Setup.exe`.
- `bin/`: Carpeta donde se alojan los binarios del agente ejecutable y librerías DLL de Qt.
- `LICENSE.txt`: Términos de uso y confidencialidad que se muestran en el asistente.

---

## 2. Preparación de los Binarios

1. Copie el ejecutable del agente (`aca-agent.exe` y `empmonitor.exe`) y todas las librerías dependientes de Qt (`Qt5Cored.dll`, `Qt5Guid.dll`, `Qt5Networkd.dll`, etc.) dentro de la subcarpeta `bin/`.
2. Verifique que `config.js` y `config.json` contengan la dirección IP o dominio público de su servidor en formato corporativo `office`:
   ```json
   {
     "id": "OjUpRAB",
     "mode": "office",
     "api": "http://IP_O_DOMINIO_DEL_SERVIDOR:3001/api/v1",
     "login": "http://IP_O_DOMINIO_DEL_SERVIDOR:3004/api/v3",
     "pipeline": "http://IP_O_DOMINIO_DEL_SERVIDOR:3001/api/v1",
     "realtime": "ws://IP_O_DOMINIO_DEL_SERVIDOR:3003",
     "updates": "http://IP_O_DOMINIO_DEL_SERVIDOR:3004/api/v3"
   }
   ```
3. El instalador configura automáticamente las políticas de intervalo en la ruta nativa de Qt `QSettings` en el Registro de Windows (`HKCU\Software\screen\empm\appSettings`):
   - `dataSendingPeriodSec = 30` (envío de actividad cada 30 segundos)
   - `from_remote\screenshotPeriodSec = 20` (capturas de pantalla cada 20 segundos)

---

## 3. Compilación del Instalador (.exe)

Para compilar el instalador corporativo en Windows:

1. Descargue e instale **[Inno Setup](https://jrsoftware.org/isdl.php)** (versión 6 o superior, software libre y gratuito).
2. Abra el archivo `installer.iss` con Inno Setup Compiler.
3. Presione el botón **Run** (o presione `Ctrl + F9`).
4. Al finalizar la compilación, se generará el archivo final dentro de la carpeta `Output/`:
   ```
   Output/ACA_Advisor_Agent_Setup.exe
   ```

---

## 4. Métodos de Instalación en Equipos Clientes

### A. Instalación Manual con Interfaz Gráfica
Haga doble clic sobre `ACA_Advisor_Agent_Setup.exe` y siga los pasos del asistente con el logotipo oficial de ACA ADVISOR S.A.S.

### B. Instalación Silenciosa / Desatendida (Recomendada para Empresas)
Para instalar el agente sin que el empleado vea ventanas ni tenga que intervenir, ejecute en PowerShell o CMD con permisos de Administrador:

```cmd
ACA_Advisor_Agent_Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

### C. Despliegue Masivo mediante Active Directory (GPO) o Microsoft Intune
- En redes corporativas con dominio, configure una directiva de grupo (GPO) o tarea programada de inicio que ejecute el comando silencioso anterior en todas las estaciones de trabajo.

---

## 5. Prevención de Bloqueos por Windows Defender y Antivirus

El script `installer.iss` incluye un comando automático post-instalación que agrega la ruta del agente a las exclusiones de Windows Defender:

```powershell
Add-MpPreference -ExclusionPath "C:\Program Files\ACA Advisor Agent"
```

Si su empresa utiliza un antivirus corporativo (Kaspersky, ESET, CrowdStrike, Sophos, etc.), agregue la carpeta `C:\Program Files\ACA Advisor Agent` a la lista de exclusiones de análisis en tiempo real.

---

## 6. Verificación de Conexión

Una vez instalado el agente en un equipo cliente:
1. El agente enviará un *heartbeat* y registrará la dirección MAC y nombre del equipo contra el servidor en el puerto `3004`.
2. Ingrese a la plataforma web de ACA ADVISOR en `http://IP_SERVIDOR:8081` con las credenciales de administrador.
3. En el menú **Empleados** o **Monitoreo en Tiempo Real**, el equipo aparecerá conectado en estado verde (*Online*).
