---
title: Herramienta GeoIP CLI con Python y MaxMind GeoLite2
date: 2026-04-14 17:53:00 +0200
categories: [Redes, Herramientas]
tags: [geoip, python, maxmind, debian, linux, redes, arch-linux]
---

Guía para construir un comando `geoip` propio que resuelve país, ciudad, coordenadas y ASN de cualquier IP, usando las bases de datos GeoLite2 de MaxMind y Python.

---

## ¿Qué vamos a construir?

Un comando de sistema que funciona así:

```
$ geoip 8.8.4.4
IP: 8.8.4.4
----------------------
Country: United States
City: None
Coords: 37.751 -97.822
ASN: 15169 Google LLC
```

---

## Componentes del sistema

Antes de instalar nada conviene entender qué hace cada pieza:

| Componente | Qué es | Para qué sirve |
| --- | --- | --- |
| **MaxMind / GeoLite2** | Proveedor de datos geográficos de IPs | La fuente de toda la información |
| **GeoLite2-City.mmdb** | Base de datos de ciudades y coordenadas | Mapea IPs a ubicaciones |
| **GeoLite2-ASN.mmdb** | Base de datos de ASNs | Identifica el operador de red de cada IP |
| **geoipupdate** | Herramienta de actualización | Descarga y actualiza los archivos `.mmdb` |
| **libmaxminddb** | Librería C para leer `.mmdb` | Permite que Python acceda a las bases de datos |
| **maxminddb (Python)** | Módulo Python | Interfaz limpia para consultar las bases |
| **Script geoip** | El comando que creamos | Une todo y muestra la información formateada |

> Las bases de datos GeoLite2 son **locales y offline**. Una vez descargadas no necesitas conexión para consultar IPs.
{: .prompt-info }

---

## Paso 1: Crear cuenta en MaxMind

GeoLite2 es gratuito pero requiere registro. Ve a la web de MaxMind y crea una cuenta.

Una vez registrado, entra en la sección **My License Key** y genera una nueva clave. Necesitarás dos datos:

- **Account ID** — número de cuenta
- **License Key** — clave de acceso a las descargas

> Sin estos datos `geoipupdate` no puede descargar ninguna base de datos.
{: .prompt-warning }

---

## Paso 2: Instalar dependencias

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install geoipupdate python3 python3-pip
pip3 install maxminddb
```

En Debian el paquete `geoipupdate` incluye tanto la herramienta como el fichero de configuración en `/etc/GeoIP.conf`.

### Arch Linux

```bash
sudo pacman -S geoipupdate libmaxminddb python
pip install maxminddb
```

> En Arch, `libmaxminddb` instala la librería C pero **no** incluye el binario `mmdblookup`. Para el script de Python esto no es un problema, ya que el módulo `maxminddb` lee los `.mmdb` directamente sin necesitar `mmdblookup`.
{: .prompt-info }

---

## Paso 3: Configurar geoipupdate

Edita el fichero de configuración:

```bash
sudo nano /etc/GeoIP.conf
```

Sustituye los valores por los de tu cuenta de MaxMind:

```
AccountID TU_ACCOUNT_ID
LicenseKey TU_LICENSE_KEY
EditionIDs GeoLite2-ASN GeoLite2-City GeoLite2-Country
```

Descarga las bases de datos:

```bash
sudo geoipupdate
```

Comprueba que se han descargado correctamente:

```bash
ls -lh /var/lib/GeoIP/
```

Deberías ver:

```
GeoLite2-ASN.mmdb
GeoLite2-City.mmdb
GeoLite2-Country.mmdb
```

---

## Paso 4: Crear el script

```bash
sudo nano /usr/local/bin/geoip
```

```python
#!/usr/bin/env python3

import sys
import maxminddb

if len(sys.argv) != 2:
    print("Uso: geoip <IP>")
    sys.exit(1)

ip = sys.argv[1]

CITY_DB = "/var/lib/GeoIP/GeoLite2-City.mmdb"
ASN_DB  = "/var/lib/GeoIP/GeoLite2-ASN.mmdb"

with maxminddb.open_database(CITY_DB) as city_db:
    c = city_db.get(ip)

with maxminddb.open_database(ASN_DB) as asn_db:
    a = asn_db.get(ip)

print(f"IP: {ip}")
print("----------------------")

if c:
    print("Country:", c.get("country", {}).get("names", {}).get("en"))
    print("City:", c.get("city", {}).get("names", {}).get("en"))
    loc = c.get("location", {})
    print("Coords:", loc.get("latitude"), loc.get("longitude"))
else:
    print("City data: not found")

if a:
    print("ASN:", a.get("autonomous_system_number"), a.get("autonomous_system_organization"))
else:
    print("ASN data: not found")
```

Hazlo ejecutable:

```bash
sudo chmod +x /usr/local/bin/geoip
```

---

## Paso 5: Probar

```bash
geoip 8.8.4.4
```

Salida esperada:

```
IP: 8.8.4.4
----------------------
Country: United States
City: None
Coords: 37.751 -97.822
ASN: 15169 Google LLC
```

> Que `City` salga como `None` en IPs de grandes proveedores (Google, Cloudflare, AWS...) es **completamente normal**. GeoLite2 no asigna ciudad a IPs de infraestructura. Con IPs residenciales o de ISP sí suele aparecer la ciudad.
{: .prompt-tip }

---

## Paso 6: Mantener las bases actualizadas

Las bases GeoLite2 se actualizan cada dos semanas. Para mantenerlas al día puedes crear un cron semanal:

```bash
sudo crontab -e
```

```
0 3 * * 1 /usr/bin/geoipupdate
```

Esto ejecuta `geoipupdate` todos los lunes a las 3:00.

---

## Notas sobre Arch Linux

- El paquete `libmaxminddb` en Arch **no incluye `mmdblookup`**. Este binario no está disponible en los repositorios oficiales ni es necesario para el script Python.
- El módulo Python se instala con `pip install maxminddb` ya que no hay paquete oficial en los repos de Arch (`python-maxminddb`).
- Las bases de datos se guardan igualmente en `/var/lib/GeoIP/` tras ejecutar `geoipupdate`.

---

## Troubleshooting

### geoipupdate falla con error de autenticación

Comprueba que `AccountID` y `LicenseKey` en `/etc/GeoIP.conf` son correctos. Recuerda que la License Key solo se muestra una vez al crearla en MaxMind.

### El módulo maxminddb no se encuentra

```bash
pip3 install maxminddb
```

Si usas un entorno con Python gestionado por el sistema (Debian 12+), puede ser necesario usar un entorno virtual:

```bash
python3 -m venv /opt/geoip-venv
/opt/geoip-venv/bin/pip install maxminddb
```

Y ajustar la primera línea del script:

```python
#!/opt/geoip-venv/bin/python3
```

### Los archivos .mmdb no existen

```bash
sudo geoipupdate
ls /var/lib/GeoIP/
```

Si el directorio no existe, créalo primero:

```bash
sudo mkdir -p /var/lib/GeoIP
sudo geoipupdate
```

---

## Referencias

- [MaxMind GeoLite2 Signup](https://www.maxmind.com/en/geolite2/signup)
- [Documentación de geoipupdate](https://dev.maxmind.com/geoip/updating-databases)
- [Módulo Python maxminddb](https://github.com/maxmind/MaxMind-DB-Reader-python)
