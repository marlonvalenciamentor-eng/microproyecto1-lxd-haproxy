# Microproyecto 1 — Cluster LXD + HAProxy + JMeter

**Materia:** Computación en la Nube — 2026-3B  
**Estudiante:** Marlon Valencia Velosa  
**Profesor:** Oscar Mondragón  

---

## Arquitectura

```
Windows Host
  │
  ├── localhost:8090  → HAProxy frontend (balanceo de carga)
  └── localhost:8404  → HAProxy Stats GUI
       │
       ▼  NAT VirtualBox
  servidorUbuntu — 192.168.100.3  (LXD nodo 1)
  ├── haproxy  → frontend :80, stats :8404
  ├── web1     → Apache (producción)
  └── web3     → Apache (backup)

  clienteUbuntu — 192.168.100.2  (LXD nodo 2)
  ├── web2     → Apache (producción)
  └── web4     → Apache (backup)
```

### Flujo de tráfico

| Condición | Servidores activos |
|-----------|-------------------|
| Normal | web1 + web2 (round-robin) |
| Producción caída o sobrecargada | web3 + web4 (backup) |
| Todos caídos | Página 503 personalizada |

---

## Requisitos previos

- [VirtualBox](https://www.virtualbox.org/) 6.x o superior  
- [Vagrant](https://www.vagrantup.com/) 2.x  
- 4 GB de RAM disponibles  
- Conexión a internet para descargar las boxes e imágenes LXD  

---

## Instalación y despliegue

### 1. Clonar el repositorio

```bash
git clone https://github.com/marlonvalenciamentor-eng/microproyecto1-lxd-haproxy.git
cd microproyecto1-lxd-haproxy
```

### 2. Levantar el entorno

```bash
vagrant up
```

> El proceso tarda ~15–20 minutos la primera vez (descarga de boxes e imágenes LXD).  
> `servidorUbuntu` inicia primero, inicializa el cluster y genera el token.  
> `clienteUbuntu` espera el token, se une al cluster y despliega sus contenedores.

### 3. Verificar el cluster

```bash
vagrant ssh servidorUbuntu
lxc cluster list
lxc list
```

Resultado esperado:

```
+----------------+---------------------------+----------+
|      NAME      |            URL            |  STATE   |
+----------------+---------------------------+----------+
| servidorUbuntu | https://192.168.100.3:8443 | ONLINE   |
| clienteUbuntu  | https://192.168.100.2:8443 | ONLINE   |
+----------------+---------------------------+----------+
```

---

## Acceso a los servicios

| Servicio | URL |
|---------|-----|
| HAProxy (balanceador) | http://localhost:8090 |
| HAProxy Stats GUI | http://localhost:8404/stats |
| web1 directo (producción) | http://localhost:8081 |
| web3 directo (backup) | http://localhost:8083 |

**Credenciales Stats GUI:** `admin` / `admin123`

---

## Pruebas de disponibilidad

### Verificar round-robin (producción)

```powershell
# PowerShell — 6 peticiones al balanceador
1..6 | ForEach-Object {
    $r = Invoke-WebRequest -Uri "http://localhost:8090" -UseBasicParsing
    if ($r.Content -match 'WEB (\d)') { "Request $_ -> WEB $($Matches[1])" }
}
```

Resultado esperado: `WEB 1 → WEB 2 → WEB 1 → WEB 2 → ...`

### Verificar failover a backup (simular caída de producción)

```bash
# Dentro de servidorUbuntu — detener servidores de producción
vagrant ssh servidorUbuntu
lxc stop web1

# En clienteUbuntu — detener web2
vagrant ssh clienteUbuntu
lxc stop web2
```

Luego acceder a `http://localhost:8090` — debe responder **WEB 3** o **WEB 4**.

El Stats GUI en `http://localhost:8404/stats` mostrará web1/web2 en rojo (DOWN) y web3/web4 en verde (UP).

### Verificar página 503 personalizada (todos los servidores caídos)

```bash
vagrant ssh servidorUbuntu
lxc stop web1 web3

vagrant ssh clienteUbuntu
lxc stop web2 web4
```

Acceder a `http://localhost:8090` — debe mostrar la página **"Servicio Temporalmente No Disponible"**.

### Restaurar servidores

```bash
# En servidorUbuntu
lxc start web1 web3

# En clienteUbuntu
lxc start web2 web4
```

---

## Pruebas de carga con JMeter

### Prerrequisitos

- Java 21+ instalado  
- Apache JMeter 5.6.3 descomprimido en `C:\jmeter\apache-jmeter-5.6.3\`  

### Escenario 1 — Carga normal (500 usuarios, round-robin)

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jre-21.0.11.10-hotspot"
C:\jmeter\apache-jmeter-5.6.3\bin\jmeter.bat -n -t jmeter\escenario1_carga_normal.jmx -l jmeter\resultado1.jtl
```

Verifica que solo web1 y web2 respondan en distribución ~50/50.

### Escenario 2 — Falla parcial (failover a backup)

1. Detener web1 y web2 (ver sección anterior).  
2. Ejecutar:

```powershell
C:\jmeter\apache-jmeter-5.6.3\bin\jmeter.bat -n -t jmeter\escenario2_falla_parcial.jmx -l jmeter\resultado2.jtl
```

Verifica que web3 y web4 absorben todo el tráfico sin errores.

### Escenario 3 — Falla total (página 503)

1. Detener **todos** los servidores.  
2. Ejecutar:

```powershell
C:\jmeter\apache-jmeter-5.6.3\bin\jmeter.bat -n -t jmeter\escenario3_falla_total.jmx -l jmeter\resultado3.jtl
```

Verifica que el 100% de las respuestas son HTTP 503 con el cuerpo personalizado.

---

## Estructura del repositorio

```
microproyecto1-lxd-haproxy/
├── Vagrantfile                        # Infraestructura: 2 VMs + provisioning
├── provision_server.sh                # LXD bootstrap + web1 + web3 + haproxy
├── provision_client.sh                # LXD join + web2 + web4
├── haproxy/
│   ├── haproxy.cfg                    # Roundrobin + backup + stats + errorfile
│   └── errors/
│       └── 503.http                   # Página personalizada sin servidores
├── web/
│   ├── web1/index.htm                 # Producción — nodo servidorUbuntu
│   ├── web2/index.htm                 # Producción — nodo clienteUbuntu
│   ├── web3/index.htm                 # Backup — nodo servidorUbuntu
│   └── web4/index.htm                 # Backup — nodo clienteUbuntu
└── jmeter/
    ├── escenario1_carga_normal.jmx    # 500 usuarios, round-robin
    ├── escenario2_falla_parcial.jmx   # 1000 usuarios, failover backup
    └── escenario3_falla_total.jmx     # 100 usuarios, todos caídos → 503
```

---

## Gestión del entorno

```bash
vagrant up               # Levantar todo
vagrant halt             # Apagar VMs
vagrant destroy -f       # Eliminar VMs y empezar desde cero
vagrant provision        # Re-ejecutar scripts de provisionamiento
vagrant ssh servidorUbuntu
vagrant ssh clienteUbuntu
```
