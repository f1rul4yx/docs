---
title: Monitorización web con Umami
date: 2026-02-28 12:03:00 +0200
categories: [Monitorización, Analítica]
tags: [umami, analitica, docker, autoalojado, privacidad, postgresql]
---

En este tutorial vamos a instalar y configurar **Umami**, una plataforma de analítica web open source y self-hosted que nos permite monitorizar las visitas de cualquier web sin depender de servicios externos como Google Analytics.

---

## ¿Qué es Umami?

Umami es una aplicación Node.js que recoge datos de visitas a través de un pequeño script JavaScript (~2KB) que se inserta en las páginas web. Cuando un visitante carga una página, el script envía una petición a nuestra instancia de Umami con información básica: URL visitada, referrer, navegador, sistema operativo, idioma, resolución de pantalla y país.

No usa cookies, no rastrea entre sitios, no almacena IPs y es compatible con GDPR sin necesidad de banners de consentimiento.

**Funcionamiento interno:**

```
Visitante → carga tu web → el navegador ejecuta script.js de Umami
         → envía POST a tu instancia de Umami (/api/send)
         → Umami procesa y guarda en PostgreSQL
         → Tú consultas el dashboard
```

**Características principales:**

- Pageviews, visitantes únicos, bounce rate y duración de sesión
- Referrers, navegadores, sistemas operativos, dispositivos y países
- Tracking de eventos personalizados (clicks, formularios, descargas)
- Funnels, journeys, retención, UTM y objetivos
- API REST completa
- Multi-sitio: una sola instancia para todas tus webs

---

## Paso 1: Generar credenciales

Antes de desplegar, generamos la contraseña de la base de datos y el secreto de aplicación:

```bash
# Contraseña para PostgreSQL
openssl rand -base64 24

# Secreto de aplicación
openssl rand -base64 32
```

Guardamos ambos valores, los necesitaremos en el siguiente paso.

---

## Paso 2: Despliegue con Docker Compose

Creamos el directorio de trabajo:

```bash
mkdir -p /opt/umami && cd /opt/umami
```

Creamos el fichero `docker-compose.yml`:

```yaml
services:
  umami:
    image: ghcr.io/umami-software/umami:postgresql-latest
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://umami:TU_PASSWORD_GENERADA@db:5432/umami
      DATABASE_TYPE: postgresql
      APP_SECRET: TU_APP_SECRET_GENERADO
    depends_on:
      db:
        condition: service_healthy
    init: true
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl http://localhost:3000/api/heartbeat"]
      interval: 5s
      timeout: 5s
      retries: 5

  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: umami
      POSTGRES_USER: umami
      POSTGRES_PASSWORD: TU_PASSWORD_GENERADA
    volumes:
      - umami-db:/var/lib/postgresql/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U umami -d umami"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  umami-db:
```

Sustituimos `TU_PASSWORD_GENERADA` (en `DATABASE_URL` y `POSTGRES_PASSWORD`, deben ser la misma) y `TU_APP_SECRET_GENERADO` por los valores generados en el paso anterior.

> Si el puerto 3000 ya está en uso, cambia el mapeo a otro puerto, por ejemplo `"3001:3000"`. El puerto interno del contenedor (3000) no se modifica.
{: .prompt-tip }

### Explicación del compose

| Parámetro | Descripción |
|---|---|
| `ghcr.io/umami-software/umami:postgresql-latest` | Imagen oficial de Umami con soporte para PostgreSQL. |
| `ports` | Mapeo de puertos `host:contenedor`. |
| `DATABASE_URL` | Cadena de conexión a PostgreSQL. La contraseña debe coincidir con `POSTGRES_PASSWORD`. |
| `APP_SECRET` | Cadena aleatoria usada para firmar tokens de sesión y cifrar datos internos. |
| `init: true` | Ejecuta un proceso init dentro del contenedor para manejar correctamente señales y procesos zombie. |
| `healthcheck` | Verifica que Umami responde en `/api/heartbeat` antes de considerarlo saludable. |
| `postgres:15-alpine` | Imagen ligera de PostgreSQL 15 basada en Alpine Linux. |
| `umami-db` | Volumen persistente para los datos de PostgreSQL. Si se destruye el contenedor, los datos se mantienen. |

Levantamos los contenedores:

```bash
docker compose up -d
```

La primera vez, Umami creará automáticamente todas las tablas necesarias en PostgreSQL y un usuario con las credenciales por defecto `admin` / `umami`.

Verificamos que todo funciona:

```bash
docker compose ps
docker compose logs umami
```

Umami estará disponible en `http://IP_DEL_SERVIDOR:3000`.

---

## Paso 3: Configuración inicial

Accedemos a Umami desde el navegador e iniciamos sesión con las credenciales por defecto:

- **Usuario:** `admin`
- **Contraseña:** `umami`

> Cambia la contraseña inmediatamente desde **Settings → Profile**.
{: .prompt-danger }

### Añadir un sitio web

1. Ir a **Settings → Websites → Add Website**
2. En **Nombre** ponemos un identificador (por ejemplo `mi-web`)
3. En **Dominio** ponemos **solo el hostname**, sin `https://`: `miweb.com`
4. Guardamos
5. Hacemos click en **Edit** junto al sitio creado
6. Copiamos el **Website ID** (un UUID tipo `a1b2c3d4-5678-9abc-def0-123456789abc`)

Este proceso se repite para cada web que queramos monitorizar. Cada sitio tendrá su propio Website ID y su dashboard independiente.

---

## Paso 4: Añadir el tracking a tu web

### Cualquier web (HTML, WordPress, React, etc.)

Insertamos el siguiente script en el `<head>` de nuestra web:

```html
<script defer src="https://umami.tudominio.es/script.js"
        data-website-id="tu-website-id"></script>
```

| Atributo | Descripción |
|---|---|
| `defer` | El script se carga en paralelo y se ejecuta después del HTML, sin bloquear la carga de la página. |
| `src` | URL del script de tracking alojado en nuestra instancia de Umami. |
| `data-website-id` | El Website ID que identifica a qué sitio corresponden las visitas. |

El script pesa menos de 2KB y no afecta al rendimiento de la web.

### Jekyll con tema Chirpy (v7.0.0+)

Chirpy tiene soporte nativo para Umami. Solo hay que editar el `_config.yml`:

```yaml
analytics:
  umami:
    id: "tu-website-id"
    domain: "https://umami.tudominio.es"
```

> El tracking de Chirpy solo se activa cuando el build se ejecuta con `JEKYLL_ENV=production`. Si las visitas no se registran, asegúrate de que el build incluye esta variable: `JEKYLL_ENV=production bundle exec jekyll build`.
{: .prompt-warning }

Para verificar que funciona, abre tu web, haz click derecho → **Ver código fuente** (Ctrl+U) y busca `umami`. Debería aparecer un `<script>` apuntando a tu instancia.

---

## Paso 5: Dashboard público (opcional)

Si queremos que las estadísticas sean visibles públicamente, Umami ofrece la opción de generar un **Share URL**:

1. En Umami, ir a **Settings → Websites**
2. Click en **Edit** junto al sitio
3. Activar **Share URL**
4. Copiar la URL generada

Podemos embeber ese dashboard en cualquier página con un `<iframe>`:

```html
<iframe src="https://umami.tudominio.es/share/TU-TOKEN"
        style="width:100%; height:800px; border:none;">
</iframe>
```

---

## Tracking de eventos personalizados

Además de las visitas a páginas, Umami permite rastrear acciones específicas usando el atributo `data-umami-event`:

```html
<a href="/archivo.pdf" data-umami-event="descarga-pdf">Descargar PDF</a>

<button data-umami-event="click-contacto">Contactar</button>
```

Estos eventos aparecerán en el dashboard con el nombre que hayamos definido.

---

## Gestión y mantenimiento

### Actualizar Umami

```bash
cd /opt/umami
docker compose pull
docker compose up -d
```

### Backup de la base de datos

```bash
docker exec -t umami-db-1 pg_dump -U umami umami > backup_umami_$(date +%F).sql
```

### Restaurar un backup

```bash
cat backup_umami_2026-02-28.sql | docker exec -i umami-db-1 psql -U umami umami
```

---

## Notas finales

- **Seguridad:** las credenciales de PostgreSQL y el `APP_SECRET` nunca deben subirse a un repositorio público. El Website ID sí es seguro, ya que es público por naturaleza (aparece en el código fuente de la web).
- **Ad blockers:** al ser self-hosted en tu propio dominio, la mayoría de ad blockers no bloquean el script, a diferencia de servicios externos como Google Analytics.
- **Multi-sitio:** una sola instancia de Umami sirve para monitorizar todas las webs que necesites. Solo hay que añadir cada sitio en Settings y usar su Website ID correspondiente.
- **Acceso externo:** si Umami se ejecuta en una red local y necesitamos acceder desde internet, será necesario configurar un reverse proxy (nginx, Caddy, Traefik...) con HTTPS y apuntar un subdominio a la IP del servidor.
