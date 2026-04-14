---
title: Configuración VPN de acceso remoto con OpenVPN (Debian 13)
date: 2026-02-27 16:40:00 +0200
categories: [Seguridad, VPN]
tags: [openvpn, vpn, pki, easy-rsa, iptables, debian, linux, proxmox]
---

En este tutorial vamos a configurar una VPN de acceso remoto con OpenVPN sobre Debian 13, ejecutándose como máquina virtual en Proxmox. Esto nos permitirá conectarnos a toda nuestra red local desde cualquier lugar con conexión a Internet, como si estuviéramos físicamente en casa.

## ¿Qué es una VPN de acceso remoto?

Existen dos tipos principales de VPN: **site-to-site**, que conecta dos redes completas entre sí (por ejemplo, dos oficinas), y **acceso remoto** (*remote access*), que permite a un dispositivo individual conectarse a una red remota a través de un túnel cifrado.

En nuestro caso usaremos acceso remoto: un cliente (nuestro portátil, móvil, etc.) se conecta al servidor VPN de casa y obtiene acceso completo a la red local como si estuviera conectado directamente.

**OpenVPN** es una solución VPN de código abierto que utiliza TLS/SSL para crear túneles cifrados. Es estable, ampliamente soportada y flexible para todo tipo de escenarios.

## Escenario

| Elemento | Valor |
| --- | --- |
| Red LAN | `192.168.0.0/22` (`255.255.252.0`) |
| Servidor VPN (VM en Proxmox) | `192.168.2.4` |
| Red del túnel VPN | `10.8.0.0/24` |
| Puerto | UDP `1194` |
| Sistema operativo | Debian 13 (Trixie) |
| Interfaz de red de la VM | `ens18` |

El router tiene configurado un **DNAT** (redirección de puertos) para que todo el tráfico UDP entrante por el puerto 1194 se redirija a la IP de la VM `192.168.2.4`.

---

## Paso 1: Instalación de paquetes

Lo primero es instalar OpenVPN y easy-rsa, que nos permitirá gestionar la infraestructura de certificados (PKI):

```bash
sudo apt update
sudo apt install openvpn easy-rsa -y
```

## Paso 2: Crear la infraestructura de certificados (PKI)

OpenVPN utiliza certificados TLS para autenticar tanto al servidor como a los clientes. Para gestionar estos certificados usaremos **easy-rsa**, una herramienta que simplifica la creación y gestión de una PKI (*Public Key Infrastructure*).

### Inicializar el directorio de trabajo

```bash
make-cadir ~/easy-rsa
cd ~/easy-rsa
```

`make-cadir` crea una copia del entorno easy-rsa en nuestro directorio personal, donde trabajaremos sin necesidad de tocar los archivos del sistema.

### Inicializar la PKI

```bash
./easyrsa init-pki
```

Esto crea la estructura de directorios donde se almacenarán todos los certificados y claves.

### Crear la Autoridad Certificadora (CA)

```bash
./easyrsa build-ca
```

Nos pedirá una contraseña para proteger la clave privada de la CA y un nombre (*Common Name*). La CA es la entidad que firma todos los certificados; sin ella, ningún certificado será válido.

### Generar el certificado del servidor

```bash
./easyrsa gen-req server nopass
./easyrsa sign-req server server
```

El primer comando genera la solicitud de certificado y la clave privada del servidor. El parámetro `nopass` evita que pida contraseña cada vez que se inicie OpenVPN. El segundo comando firma esa solicitud con nuestra CA.

### Generar el certificado del cliente

```bash
./easyrsa gen-req cliente nopass
./easyrsa sign-req client cliente
```

Mismo proceso pero para el cliente. Si necesitas más clientes en el futuro, repite estos dos comandos cambiando `cliente` por el nombre que quieras.

### Generar parámetros Diffie-Hellman y clave TLS

```bash
./easyrsa gen-dh
openvpn --genkey secret ta.key
```

Los **parámetros Diffie-Hellman** (`dh.pem`) se usan para el intercambio seguro de claves durante el establecimiento del túnel. La **clave TLS** (`ta.key`) añade una capa extra de autenticación HMAC que protege contra ataques de denegación de servicio y escaneo de puertos.

## Paso 3: Copiar archivos al directorio de OpenVPN

```bash
sudo cp pki/ca.crt \
   pki/issued/server.crt \
   pki/private/server.key \
   pki/dh.pem \
   ta.key \
   /etc/openvpn/
```

Copiamos todos los archivos necesarios al directorio donde OpenVPN busca su configuración por defecto.

## Paso 4: Configuración del servidor

Creamos el fichero de configuración del servidor:

```bash
sudo nano /etc/openvpn/server.conf
```

Con el siguiente contenido:

```
port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0
server 10.8.0.0 255.255.255.0
push "route 192.168.0.0 255.255.252.0"
keepalive 10 120
log /var/log/openvpn.log
status /var/log/openvpn-status.log
verb 4
```

### Explicación de cada parámetro

| Parámetro | Descripción |
| --- | --- |
| `port 1194` | Puerto en el que escucha OpenVPN. Es el puerto estándar de OpenVPN. |
| `proto udp` | Protocolo de transporte. UDP es más rápido que TCP para VPN ya que evita el problema de encapsular TCP dentro de TCP. |
| `dev tun` | Tipo de interfaz virtual. `tun` opera a nivel de capa 3 (IP), creando un túnel punto a punto. La alternativa `tap` opera en capa 2 (Ethernet) pero no es necesaria para acceso remoto. |
| `ca ca.crt` | Certificado de la Autoridad Certificadora. Se usa para verificar que los certificados del servidor y los clientes son legítimos. |
| `cert server.crt` | Certificado público del servidor, firmado por la CA. |
| `key server.key` | Clave privada del servidor. Debe mantenerse protegida ya que es lo que demuestra la identidad del servidor. |
| `dh dh.pem` | Parámetros Diffie-Hellman para el intercambio seguro de claves. |
| `tls-auth ta.key 0` | Clave HMAC compartida para autenticación adicional. El `0` indica que este es el servidor (el cliente usa `1`). Protege contra ataques DoS y escaneo de puertos. |
| `server 10.8.0.0 255.255.255.0` | Define la subred del túnel VPN. El servidor se asigna `10.8.0.1` y los clientes reciben IPs del rango `10.8.0.0/24`. |
| `push "route 192.168.0.0 255.255.252.0"` | Envía al cliente una ruta hacia nuestra red LAN `/22`. Así el cliente sabe que para llegar a `192.168.0.0/22` debe enviar el tráfico por el túnel VPN. |
| `keepalive 10 120` | Envía un ping cada 10 segundos. Si no hay respuesta en 120 segundos, considera la conexión caída y la reinicia. |
| `log /var/log/openvpn.log` | Redirige los logs del servidor a un fichero en disco. Se sobreescribe en cada reinicio del servicio. |
| `status /var/log/openvpn-status.log` | Escribe periódicamente el estado actual de las conexiones activas (clientes conectados, IPs asignadas, bytes transferidos). |
| `verb 4` | Nivel de detalle de los logs. `4` incluye información de conexión/desconexión y errores detallados. |

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

## Paso 6: Configurar NAT con iptables

Los paquetes que llegan desde la VPN tienen como IP de origen una dirección del rango `10.8.0.0/24`, que los dispositivos de nuestra LAN no conocen. Para que la comunicación funcione, necesitamos hacer **MASQUERADE** (NAT de origen): la VM sustituye la IP de origen por la suya propia (`192.168.2.4`) antes de enviar los paquetes a la LAN.

Instalamos iptables-persistent para que las reglas sobrevivan a reinicios:

```bash
sudo apt install iptables-persistent -y
```

Añadimos la regla de NAT:

```bash
sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -d 192.168.0.0/22 -o ens18 -j MASQUERADE
```

> Comprueba el nombre de tu interfaz de red con `ip a`. En una VM de Proxmox suele ser `ens18`.

Guardamos las reglas para que sean persistentes:

```bash
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

Para verificar que la regla está activa:

```bash
sudo iptables -t nat -L -v
```

## Paso 7: Iniciar OpenVPN

```bash
sudo systemctl start openvpn@server
sudo systemctl enable openvpn@server
sudo systemctl status openvpn@server
```

El servicio debe aparecer como `active (running)`. El `enable` hace que se inicie automáticamente con cada arranque del sistema.

## Paso 8: Redirección de puertos en el router

Este paso se realiza en la interfaz de administración de tu router. Debes configurar un **DNAT** (también llamado *port forwarding*) para redirigir el tráfico UDP del puerto 1194 que llega desde Internet hacia la IP de la VM VPN:

| Protocolo | Puerto externo | IP destino | Puerto interno |
| --- | --- | --- | --- |
| UDP | 1194 | 192.168.2.4 | 1194 |

No es necesario configurar nada más en el router.

---

## Configuración del cliente

### Instalación

En el equipo cliente (otro Debian, Ubuntu, etc.):

```bash
sudo apt install openvpn -y
```

### Crear el archivo de conexión

Necesitamos crear un único archivo `.ovpn` que contenga toda la configuración y los certificados necesarios para conectarse. Los certificados los copiamos de la máquina servidor.

Los archivos que necesitamos del servidor son:

| Archivo | Ruta en el servidor |
| --- | --- |
| `ca.crt` | `~/easy-rsa/pki/ca.crt` |
| `cliente.crt` | `~/easy-rsa/pki/issued/cliente.crt` |
| `cliente.key` | `~/easy-rsa/pki/private/cliente.key` |
| `ta.key` | `~/easy-rsa/ta.key` |

Podemos copiarlos al cliente por SCP u otro medio seguro, y luego crear el archivo de configuración:

```bash
nano cliente.ovpn
```

Con el siguiente contenido:

```
client
dev tun
proto udp
remote TU_IP_PUBLICA 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
key-direction 1
verb 3

<ca>
(contenido de ca.crt)
</ca>

<cert>
(contenido de cliente.crt)
</cert>

<key>
(contenido de cliente.key)
</key>

<tls-auth>
(contenido de ta.key)
</tls-auth>
```

> Sustituye `TU_IP_PUBLICA` por la IP pública de tu conexión a Internet doméstica. Puedes consultarla buscando "cuál es mi IP" desde un equipo de tu red local.

### Explicación de los parámetros del cliente

| Parámetro | Descripción |
| --- | --- |
| `client` | Indica que este es un archivo de configuración de cliente. |
| `dev tun` | Debe coincidir con el tipo de interfaz configurado en el servidor. |
| `proto udp` | Protocolo de transporte, debe coincidir con el servidor. |
| `remote TU_IP_PUBLICA 1194` | IP pública del servidor y puerto al que conectarse. |
| `resolv-retry infinite` | Si no puede resolver el nombre del servidor, lo reintenta indefinidamente en lugar de fallar. |
| `nobind` | No vincula el cliente a un puerto local específico. |
| `persist-key` | Mantiene las claves en memoria al reiniciar el túnel, evitando tener que releerlas. |
| `persist-tun` | Mantiene la interfaz tun activa al reiniciar la conexión. |
| `remote-cert-tls server` | Verifica que el certificado del servidor tiene el atributo correcto de tipo servidor, evitando ataques *man-in-the-middle*. |
| `key-direction 1` | Complemento de `tls-auth`. El servidor usa `0` y el cliente `1`. |
| `verb 3` | Nivel de detalle de los logs. |
| `<ca>`, `<cert>`, `<key>`, `<tls-auth>` | Bloques inline donde se pega el contenido de cada archivo directamente, permitiendo tener toda la configuración en un solo fichero `.ovpn`. |

### Conectar

```bash
sudo openvpn --config cliente.ovpn
```

Si la conexión es correcta, veremos en la salida el mensaje `Initialization Sequence Completed`.

### Verificar la conexión

```bash
ping 192.168.2.4    # Servidor VPN
ping 192.168.0.1    # Router / otro equipo de la LAN
```

Si ambos responden, la VPN está funcionando correctamente y tenemos acceso completo a toda la red `/22`.

---

## Notas adicionales

**Sobre la seguridad:** toda la comunicación entre el cliente y el servidor viaja cifrada mediante TLS. La combinación de certificados + clave HMAC (`tls-auth`) proporciona autenticación mutua y protección contra ataques comunes.

**Sobre el rendimiento:** UDP es la opción recomendada para VPN ya que las aplicaciones que viajan por el túnel (TCP sobre TCP) gestionan sus propias retransmisiones. Usar TCP como transporte del túnel puede causar retransmisiones innecesarias que degradan el rendimiento.

**Añadir más clientes:** para cada nuevo dispositivo que quiera conectarse, solo es necesario generar un nuevo par de certificados con `easyrsa gen-req` y `easyrsa sign-req client`, crear su fichero `.ovpn` correspondiente, y transferirlo de forma segura al dispositivo.

**Cliente en Android/iOS:** existen apps oficiales de OpenVPN tanto para Android como iOS. Basta con importar el fichero `.ovpn` directamente en la aplicación.
