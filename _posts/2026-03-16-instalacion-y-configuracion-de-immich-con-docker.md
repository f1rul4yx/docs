---
title: Instalación y Configuración de Immich con Docker
date: 2026-03-16 10:48:00 +0200
categories: [Linux, Instalación]
tags: [immich, docker, linux, selfhosted, nginx]
---

Guía completa para instalar Immich con Docker Compose y configurar un proxy inverso nginx con SSL para acceso externo.

---

## ¿Qué es Immich?

**Immich** es una solución de gestión de fotos y vídeos autoalojada (self-hosted) de código abierto. Es una alternativa a Google Photos que corre en tu propio servidor, con app móvil para iOS y Android, reconocimiento facial, búsqueda semántica por IA y mapas.

---

## Requisitos

- Docker y Docker Compose instalados
- Dominio apuntando a tu IP pública (para acceso externo con SSL)
- Proxy inverso nginx con Certbot (opcional, para acceso externo)

---

## Paso 1: Descargar los ficheros de Immich

Crea el directorio de trabajo y descarga los ficheros oficiales de la última versión:

```bash
mkdir /opt/immich-app
cd /opt/immich-app

wget -O docker-compose.yml https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
wget -O .env https://github.com/immich-app/immich/releases/latest/download/example.env
```

---

## Paso 2: Configurar el fichero .env

```bash
nano /opt/immich-app/.env
```

Ajusta los siguientes valores:

```env
# Ruta donde se guardarán las fotos y vídeos
UPLOAD_LOCATION=/mnt/fotos

# Ruta para los datos de PostgreSQL (NO usar un share de red)
DB_DATA_LOCATION=/opt/immich-app/postgres

# Zona horaria
TZ=Europe/Madrid

# Versión de Immich
IMMICH_VERSION=release

# Contraseña de la base de datos (solo caracteres A-Za-z0-9)
DB_PASSWORD=TuPasswordSegura123

# No es necesario modificar estos valores
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
```

> `DB_DATA_LOCATION` no debe apuntar a un recurso compartido de red (NFS, SMB...). PostgreSQL requiere acceso directo al disco.
{: .prompt-warning }

---

## Paso 3: Arrancar Immich

```bash
cd /opt/immich-app
docker compose up -d
```

Comprueba que todos los contenedores están corriendo y en estado `healthy`:

```bash
docker compose ps
```

Para ver los logs en tiempo real:

```bash
docker compose logs -f
```

---

## Paso 4: Primer acceso y usuario administrador

Una vez que todos los contenedores estén en estado `healthy`, accede desde el navegador usando la IP del servidor:

```
http://<IP_DEL_SERVIDOR>:2283
```

La primera vez solicitará crear el **usuario administrador**.

> Las versiones recientes de Immich requieren HTTPS para la autenticación cuando se accede con un dominio. Si intentas acceder con `http://tudominio.es:2283` obtendrás un error de autenticación. Usa siempre la IP local para el primer acceso o configura el proxy inverso con SSL antes.
{: .prompt-warning }

---

## Paso 5: Configuración dentro de Immich

### Plantilla de almacenamiento

Immich permite definir cómo se organizan físicamente los ficheros en el disco. Se configura en **Administración → Ajustes → Plantilla de almacenamiento**.

Por defecto los ficheros se guardan con nombres UUID aleatorios. Activando la plantilla puedes definir una estructura legible, por ejemplo:

```
{% raw %}{{y}}/{{y}}-{{MM}}-{{dd}}/{{filename}}{% endraw %}
```

Lo que genera rutas como `2024/2024-03-15/IMG_1234.jpg`.

> Actívalo antes de subir cualquier fichero. Si lo activas con fotos ya subidas, Immich reorganizará todos los ficheros existentes.
{: .prompt-tip }

### Configuración del servidor

En **Administración → Ajustes → Configuración del servidor** puedes definir el **dominio externo**, que es la URL que Immich usará para generar enlaces compartidos:

```
https://immich.tudominio.es
```

---

## Paso 6: Configurar el proxy inverso nginx

Para acceder a Immich desde fuera de la red local con dominio y SSL es necesario un proxy inverso. Immich requiere configuración específica en nginx para manejar ficheros grandes y WebSockets correctamente.

### Virtualhost de Immich

```nginx
server {
  server_name immich.tudominio.es;

  location / {
    proxy_pass http://192.168.X.X:2283;
    include proxy_params;

    # Necesario para subir fotos y vídeos grandes
    client_max_body_size 50000M;

    # Timeouts para subidas lentas y procesamiento de vídeo
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;

    # Desactivar buffering para WebSockets y streaming de vídeo
    proxy_buffering off;
  }

  listen 443 ssl;
  ssl_certificate /etc/letsencrypt/live/immich.tudominio.es/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/immich.tudominio.es/privkey.pem;
  include /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

server {
  if ($host = immich.tudominio.es) {
    return 301 https://$host$request_uri;
  }
  server_name immich.tudominio.es;
  listen 80;
  return 404;
}
```

Verifica la sintaxis y recarga nginx:

```bash
nginx -t && systemctl reload nginx
```

Para obtener el certificado SSL con Certbot:

```bash
certbot --nginx -d immich.tudominio.es
```

### Directorio temporal de nginx

Por defecto nginx guarda los ficheros temporalmente en `/tmp`, que en muchos sistemas es un **tmpfs montado en RAM** con capacidad muy limitada. Al subir varios ficheros en paralelo desde la app móvil este espacio se llena y aparece el siguiente error:

```
pwrite() "/tmp/..." failed (28: No space left on device)
```

La solución es redirigir el directorio temporal al disco. Crea el directorio y asigna los permisos:

```bash
mkdir -p /var/lib/nginx/tmp
chown www-data:www-data /var/lib/nginx/tmp
```

Añade esta directiva dentro del bloque `http {}` de `/etc/nginx/nginx.conf`:

```nginx
http {
    client_body_temp_path /var/lib/nginx/tmp;
    ...
}
```

Recarga nginx:

```bash
nginx -t && systemctl reload nginx
```

### Por qué es necesaria cada directiva

| Directiva | Por qué es necesaria |
| --- | --- |
| `client_body_temp_path` | Mueve el directorio temporal al disco para evitar llenar el tmpfs de RAM al subir varios ficheros en paralelo. |
| `client_max_body_size 50000M` | Por defecto nginx limita las peticiones a 1 MB, lo que rechaza cualquier foto o vídeo. |
| `proxy_read_timeout 600s` | Evita que nginx corte la conexión mientras Immich procesa vídeos grandes. |
| `proxy_send_timeout 600s` | Evita que nginx corte subidas lentas desde el móvil con mala cobertura. |
| `proxy_buffering off` | Necesario para que funcionen los WebSockets que usa Immich para las notificaciones de progreso de subida. |

---

## Paso 7: Configurar la app móvil

Descarga la app de Immich desde la **App Store** o **Google Play** e introduce la URL del servidor al abrirla por primera vez:

```
https://immich.tudominio.es
```

> La app realiza **copia de seguridad**, no sincronización bidireccional. Las fotos se copian al servidor pero no se borran del móvil. Para liberar espacio hay que borrarlas manualmente una vez verificadas en el servidor.
{: .prompt-info }

---

## Troubleshooting

### Error de autenticación al acceder con dominio sin SSL

Las versiones recientes de Immich requieren HTTPS para la autenticación por diseño. Si accedes con `http://` y un dominio obtendrás el error `Authentication required (Immich Server Error)`. Configura el proxy inverso con SSL o accede directamente por IP local:

```
http://192.168.X.X:2283
```

### Error al subir ficheros (too large body)

Comprueba los logs de nginx para confirmar el error:

```bash
tail -f /var/log/nginx/error.log
```

Verifica que `client_max_body_size` está aplicando en todos los niveles de configuración:

```bash
grep -r "client_max_body_size" /etc/nginx/
```

### No space left on device al subir fotos

El directorio temporal de nginx se ha llenado. Verifica el espacio disponible y los permisos:

```bash
df -h /var/lib/nginx/tmp
ls -la /var/lib/nginx/
```

### Los contenedores no arrancan o no están healthy

```bash
docker compose ps
docker compose logs -f
```

---

## Referencias

- [Documentación oficial de Immich - Docker Compose](https://docs.immich.app/install/docker-compose)
- [Variables de entorno de Immich](https://docs.immich.app/install/environment-variables)
- [Post-instalación de Immich](https://docs.immich.app/install/post-install)
