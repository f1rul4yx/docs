---
title: Configuración VPN de acceso remoto con WireGuard (Debian 13)
date: 2026-05-05 09:56:00 +0200
categories: [Seguridad, VPN]
tags: [wireguard, vpn, iptables, debian, linux, proxmox]
---

En este tutorial vamos a configurar una VPN de acceso remoto con WireGuard sobre Debian 13, ejecutándose como máquina virtual en Proxmox. Esto nos permitirá conectarnos a toda nuestra red local desde cualquier lugar con conexión a Internet, como si estuviéramos físicamente en casa.

## ¿Qué es WireGuard?

**WireGuard** es una solución VPN moderna, integrada directamente en el kernel de Linux desde la versión 5.6. A diferencia de OpenVPN, no usa una infraestructura de certificados (PKI): cada peer (servidor o cliente) se identifica simplemente con un par de claves pública/privada, igual que en SSH.

Sus principales ventajas son la simplicidad (apenas unas decenas de líneas de configuración), un rendimiento muy superior y un código mucho más reducido y auditable. Como contrapartida, no tiene autenticación basada en certificados ni servidor de gestión: cada cliente se añade manualmente en la configuración del servidor.

## Escenario

| Elemento | Valor |
| --- | --- |
| Red LAN | `192.168.0.0/22` (`255.255.252.0`) |
| Servidor VPN (VM en Proxmox) | `192.168.2.4` |
| Red del túnel VPN | `10.8.0.0/24` |
| Puerto | UDP `51820` |
| Sistema operativo | Debian 13 (Trixie) |
| Interfaz de red de la VM | `ens18` |

El router tiene configurado un **DNAT** (redirección de puertos) para que todo el tráfico UDP entrante por el puerto 51820 se redirija a la IP de la VM `192.168.2.4`.

---

## Paso 1: Instalación

WireGuard viene en los repositorios oficiales de Debian 13:

```bash
sudo apt update
sudo apt install wireguard -y
```

Esto instala las herramientas de espacio de usuario (`wg`, `wg-quick`). El módulo del kernel ya está incluido en el propio kernel.

## Paso 2: Generar las claves del servidor

WireGuard usa criptografía de clave pública: cada peer tiene una **clave privada** (que nunca sale del equipo) y una **clave pública** (que se comparte con el otro extremo del túnel).

Nos movemos al directorio de configuración y generamos el par de claves del servidor:

```bash
cd /etc/wireguard
sudo sh -c 'wg genkey | tee server.key | wg pubkey > server.pub'
sudo chmod 600 server.key
```

- `server.key` → clave privada del servidor (sensible, no compartir).
- `server.pub` → clave pública del servidor (la usaremos en la configuración de los clientes).

Podemos verlas con:

```bash
sudo cat /etc/wireguard/server.key
sudo cat /etc/wireguard/server.pub
```

## Paso 3: Generar las claves del cliente

Repetimos el mismo proceso para el primer cliente. Aunque las claves del cliente se podrían generar también en el propio dispositivo cliente, hacerlo aquí simplifica la creación del fichero de configuración:

```bash
sudo sh -c 'wg genkey | tee cliente.key | wg pubkey > cliente.pub'
sudo chmod 600 cliente.key
```

Si necesitas más clientes en el futuro, repite este paso cambiando `cliente` por el nombre que quieras (`movil`, `portatil`, etc.).

## Paso 4: Configuración del servidor

Creamos el fichero de configuración del servidor:

```bash
sudo nano /etc/wireguard/wg0.conf
```

Con el siguiente contenido (sustituye las claves por las generadas en los pasos anteriores):

```ini
[Interface]
PrivateKey = CLAVE_PRIVADA_DEL_SERVIDOR
Address = 10.8.0.1/24
ListenPort = 51820

PostUp = iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -d 192.168.0.0/22 -o ens18 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -d 192.168.0.0/22 -o ens18 -j MASQUERADE

[Peer]
# cliente
PublicKey = CLAVE_PUBLICA_DEL_CLIENTE
AllowedIPs = 10.8.0.2/32
```

### Explicación de cada parámetro

| Parámetro | Descripción |
| --- | --- |
| `[Interface]` | Sección que define el propio servidor. |
| `PrivateKey` | Clave privada del servidor (contenido de `server.key`). |
| `Address 10.8.0.1/24` | IP del servidor dentro del túnel. La máscara `/24` indica el tamaño de la red VPN. |
| `ListenPort 51820` | Puerto UDP en el que escucha WireGuard. Es el puerto estándar. |
| `PostUp` | Comando que se ejecuta al levantar la interfaz. Aquí añadimos la regla de NAT para que el tráfico desde la VPN salga hacia la LAN con la IP del servidor. |
| `PostDown` | Comando que se ejecuta al bajar la interfaz. Eliminamos la regla de NAT para no dejar reglas huérfanas. |
| `[Peer]` | Sección que define cada cliente autorizado. Habrá una sección `[Peer]` por cada cliente. |
| `PublicKey` | Clave pública del cliente (contenido de `cliente.pub`). Es lo que identifica a este peer concreto. |
| `AllowedIPs 10.8.0.2/32` | IPs cuyo tráfico se asocia a este peer. En el servidor actúa como **filtro**: solo se aceptan paquetes con esas IPs de origen viniendo de este cliente. Cada cliente debe tener una IP `/32` distinta. |

> **Importante:** WireGuard no tiene un mecanismo de asignación dinámica de IPs como OpenVPN. Cada cliente tiene su IP fija definida aquí.

## Paso 5: Activar el reenvío de paquetes (IP forwarding)

Para que la VM pueda enrutar el tráfico entre la red VPN (`10.8.0.0/24`) y la red local (`192.168.0.0/22`), es necesario activar el reenvío de paquetes a nivel de kernel.

En Debian 13 (Trixie), la forma correcta de hacerlo de manera persistente es creando un fichero en `/etc/sysctl.d/`:

```bash
sudo nano /etc/sysctl.d/99-forward.conf
```

Con el siguiente contenido:

```
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
```

Aplicamos los cambios:

```bash
sudo sysctl --system
sudo systemctl restart systemd-sysctl
```

Verificamos que está activo:

```bash
cat /proc/sys/net/ipv4/ip_forward
```

Debe devolver `1`.

## Paso 6: Persistir las reglas de NAT

A diferencia de la guía de OpenVPN, aquí no necesitamos `iptables-persistent`: las reglas las gestiona el propio WireGuard mediante las directivas `PostUp` y `PostDown` del fichero de configuración. Cada vez que se levante el túnel, se añade la regla de NAT; cuando se baje, se elimina.

> Comprueba el nombre de tu interfaz de red con `ip a`. En una VM de Proxmox suele ser `ens18`. Si difiere, ajústalo en las líneas `PostUp` y `PostDown`.

## Paso 7: Iniciar WireGuard

WireGuard se gestiona con `wg-quick`, que es un wrapper sobre `wg` que lee directamente los ficheros `.conf`:

```bash
sudo systemctl start wg-quick@wg0
sudo systemctl enable wg-quick@wg0
sudo systemctl status wg-quick@wg0
```

El nombre `wg0` corresponde al fichero `/etc/wireguard/wg0.conf`. El `enable` hace que el túnel se levante automáticamente con cada arranque.

Para ver el estado del túnel y los peers conectados:

```bash
sudo wg
```

## Paso 8: Redirección de puertos en el router

Este paso se realiza en la interfaz de administración de tu router. Debes configurar un **DNAT** (también llamado *port forwarding*) para redirigir el tráfico UDP del puerto 51820 que llega desde Internet hacia la IP de la VM VPN:

| Protocolo | Puerto externo | IP destino | Puerto interno |
| --- | --- | --- | --- |
| UDP | 51820 | 192.168.2.4 | 51820 |

No es necesario configurar nada más en el router.

---

## Configuración del cliente

### Instalación

En el equipo cliente (otro Debian, Ubuntu, etc.):

```bash
sudo apt install wireguard -y
```

### Crear el archivo de conexión

A diferencia de OpenVPN, en WireGuard la configuración del cliente es un fichero `.conf` muy similar al del servidor. No hay certificados que pegar, solo claves.

Creamos el fichero:

```bash
sudo nano /etc/wireguard/wg0.conf
```

Con el siguiente contenido:

```ini
[Interface]
PrivateKey = CLAVE_PRIVADA_DEL_CLIENTE
Address = 10.8.0.2/24

[Peer]
PublicKey = CLAVE_PUBLICA_DEL_SERVIDOR
Endpoint = TU_IP_PUBLICA:51820
AllowedIPs = 10.8.0.0/24, 192.168.0.0/22
PersistentKeepalive = 25
```

> Sustituye `TU_IP_PUBLICA` por la IP pública de tu conexión a Internet doméstica. Puedes consultarla buscando "cuál es mi IP" desde un equipo de tu red local.

### Explicación de los parámetros del cliente

| Parámetro | Descripción |
| --- | --- |
| `PrivateKey` | Clave privada del cliente (contenido de `cliente.key`). |
| `Address 10.8.0.2/24` | IP del cliente dentro del túnel. Debe coincidir con la `AllowedIPs` que pusimos en el servidor para este peer. |
| `PublicKey` | Clave pública del **servidor** (contenido de `server.pub`). |
| `Endpoint` | IP pública y puerto del servidor al que conectarse. |
| `AllowedIPs` | En el cliente actúa como **tabla de rutas**: define qué tráfico se envía por el túnel. Aquí incluimos la red VPN (`10.8.0.0/24`) y la LAN remota (`192.168.0.0/22`). Si quisiéramos enrutar **todo** el tráfico por la VPN, pondríamos `0.0.0.0/0`. |
| `PersistentKeepalive 25` | Envía un paquete keepalive cada 25 segundos. Necesario cuando el cliente está detrás de un NAT (lo habitual en redes domésticas o móviles), ya que mantiene viva la traducción NAT en los routers intermedios. |

> Recuerda copiar `cliente.key` y `server.pub` desde el servidor al cliente por un medio seguro (SCP). Una vez pegado el contenido en el fichero de configuración, los archivos sueltos pueden eliminarse.

### Conectar

```bash
sudo wg-quick up wg0
```

Para desconectar:

```bash
sudo wg-quick down wg0
```

Para que se conecte automáticamente al arrancar el cliente:

```bash
sudo systemctl enable wg-quick@wg0
```

### Verificar la conexión

Mostramos el estado del túnel:

```bash
sudo wg
```

Debe aparecer una línea `latest handshake` con un valor reciente (segundos), lo que indica que el peer está activo.

Probamos la conectividad:

```bash
ping 10.8.0.1       # Servidor VPN (IP del túnel)
ping 192.168.2.4    # Servidor VPN (IP de la LAN)
ping 192.168.0.1    # Router / otro equipo de la LAN
```

Si todos responden, la VPN está funcionando correctamente y tenemos acceso completo a la red `/22`.

---

## Notas adicionales

**Sobre la seguridad:** WireGuard usa una suite criptográfica fija y moderna (Curve25519, ChaCha20, Poly1305, BLAKE2s). No hay negociación de algoritmos como en TLS, lo que reduce la superficie de ataque. La autenticación entre peers se basa en sus claves públicas, igual que SSH.

**Sobre el rendimiento:** al ejecutarse dentro del kernel, WireGuard tiene una latencia y un *throughput* significativamente mejores que OpenVPN, que opera en espacio de usuario.

**Añadir más clientes:** para cada nuevo dispositivo, genera un nuevo par de claves (`wg genkey | tee nuevo.key | wg pubkey > nuevo.pub`), añade un nuevo bloque `[Peer]` en el `wg0.conf` del servidor con su clave pública y una `AllowedIPs` distinta (`10.8.0.3/32`, `10.8.0.4/32`, etc.), y crea su fichero de configuración correspondiente. Para aplicar los cambios en el servidor sin cortar las conexiones existentes:

```bash
sudo systemctl reload wg-quick@wg0
```

**Cliente en Android/iOS:** existen apps oficiales de WireGuard en ambas tiendas. Lo más cómodo es generar el fichero `.conf` del cliente, convertirlo a un código QR con `qrencode` y escanearlo desde la app:

```bash
sudo apt install qrencode -y
qrencode -t ansiutf8 < cliente.conf
```

La app importa toda la configuración directamente al escanear el QR.
