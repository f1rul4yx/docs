---
title: Notificaciones de Jellyfin en Telegram
date: 2026-03-18 10:41:00 +0200
categories: [Linux, Automatización]
tags: [jellyfin, telegram, python, bot, notificaciones, docker, systemd, autoalojado]
---

En este tutorial vamos a configurar un sistema de notificaciones automáticas que avisa por Telegram cada vez que se añade una película, serie o episodio nuevo a Jellyfin. El sistema usa un bot de Telegram y un script en Python que consulta periódicamente la API de Jellyfin.

---

## ¿Cómo funciona?

El flujo es el siguiente:

1. Un **bot de Telegram** actúa como emisor de mensajes en un grupo
2. Un **script en Python** consulta la API de Jellyfin periódicamente buscando contenido nuevo
3. Cuando detecta novedades, el script envía una notificación al grupo con información del contenido (título, sinopsis, póster, puntuación...)

El script mantiene un fichero local con los IDs de todo el contenido ya notificado, de forma que solo avisa de las novedades reales. En la primera ejecución envía un resumen de todo el contenido existente y a partir de ahí notifica individualmente.

---

## Escenario

| Elemento | Valor |
| --- | --- |
| Servidor Jellyfin | Docker en Debian |
| URL de Jellyfin | `http://localhost:8096` |
| Bot de Telegram | Creado con @BotFather |
| Grupo de Telegram | Grupo con el bot como participante |
| Script | Python 3 con `requests` |
| Servicio | systemd con venv de Python |

---

## Paso 1: Crear el bot de Telegram

Abre Telegram y busca **@BotFather** (tiene un tick azul de verificación). Es el bot oficial de Telegram para crear y gestionar bots.

1. Escríbele `/newbot`
2. Te pedirá un **nombre** para el bot (el que se muestra en la conversación, puede tener espacios)
3. Te pedirá un **username** que debe terminar en `bot` (por ejemplo `novedades_jellyfin_diego_bot`)
4. BotFather te devolverá un **token** de acceso a la API HTTP, tipo `1234567890:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX`

> Guarda el token en un lugar seguro. Cualquier persona con acceso a él puede controlar tu bot.
{: .prompt-warning }

### Configurar permisos del bot

Antes de añadir el bot a un grupo, es recomendable ejecutar los siguientes comandos en @BotFather:

- `/setjoingroups` → selecciona tu bot → **Enable** (permite que el bot sea añadido a grupos)
- `/setprivacy` → selecciona tu bot → **Enable** (el bot solo recibe mensajes que le mencionan directamente, no lee conversaciones)

Opcionalmente puedes personalizar el bot:

- `/setdescription` → descripción que se muestra al abrir el chat con el bot
- `/setuserpic` → foto de perfil del bot

---

## Paso 2: Crear un grupo de Telegram y añadir el bot

Crear un grupo en vez de un canal es más sencillo ya que permite añadir al bot como participante directamente durante la creación:

1. En Telegram → **Nuevo Grupo**
2. Cuando te pida añadir miembros, busca tu bot por su `@username` y añádelo
3. Pon el nombre que quieras al grupo
4. Añade a las personas que quieran recibir las notificaciones

Una vez creado el grupo, es recomendable hacer al bot **administrador** con permiso de "Enviar mensajes" para asegurar que siempre pueda publicar aunque se cambien los permisos del grupo.

---

## Paso 3: Obtener el chat_id del grupo

Para que el script pueda enviar mensajes al grupo, necesitamos su identificador numérico (`chat_id`).

1. Escribe cualquier mensaje en el grupo (un simple `hola` vale)
2. Abre en el navegador la siguiente URL, sustituyendo `<TOKEN>` por el token completo de tu bot:

```
https://api.telegram.org/bot<TOKEN>/getUpdates
```

3. En el JSON de respuesta, busca el campo `"chat":{"id":-XXXXXXXXXX}` dentro del bloque del grupo. El `chat_id` es ese número negativo

> Si `result` aparece vacío, asegúrate de haber escrito algo en el grupo **después** de añadir al bot, y recarga la página.
{: .prompt-tip }

---

## Paso 4: Obtener la API Key de Jellyfin

1. Abre Jellyfin en el navegador
2. Ve a **Panel de Control** → **API Keys** (en el menú lateral)
3. Haz clic en **+** para crear una nueva clave
4. Ponle un nombre identificativo, por ejemplo `Telegram Notifier`
5. Copia la API Key generada

---

## Paso 5: Preparar los ficheros en el servidor

Crea el directorio de trabajo:

```bash
mkdir -p /opt/jellyfin-telegram
cd /opt/jellyfin-telegram
```

### config.json

```bash
nano config.json
```

```json
{
    "telegram_bot_token": "TU_TOKEN_DE_BOTFATHER",
    "telegram_chat_id": "-XXXXXXXXXX",
    "jellyfin_url": "http://localhost:8096",
    "jellyfin_api_key": "TU_API_KEY_DE_JELLYFIN",
    "poll_interval_seconds": 300,
    "notify_movies": true,
    "notify_series": true,
    "notify_episodes": true
}
```

| Parámetro | Descripción |
| --- | --- |
| `telegram_bot_token` | Token del bot obtenido de @BotFather |
| `telegram_chat_id` | ID numérico del grupo (negativo) |
| `jellyfin_url` | URL de Jellyfin. Si está en la misma máquina, `http://localhost:8096` |
| `jellyfin_api_key` | API Key generada en el panel de Jellyfin |
| `poll_interval_seconds` | Intervalo de comprobación en segundos (300 = 5 minutos) |
| `notify_movies` | Notificar películas nuevas |
| `notify_series` | Notificar series nuevas |
| `notify_episodes` | Notificar episodios nuevos individualmente |

> Si Jellyfin está en otra máquina o en un contenedor con red diferente, cambia `localhost` por la IP correspondiente.
{: .prompt-info }

### notifier.py

```bash
nano notifier.py
```

```python
#!/usr/bin/env python3
"""
Jellyfin → Telegram Notifier
Detecta contenido nuevo en Jellyfin y envía notificaciones a un grupo de Telegram.

Uso:
  python3 notifier.py --mode polling
  python3 notifier.py --test
"""

import argparse
import json
import logging
import os
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    print("❌ Falta 'requests'. Instálalo con: pip install requests")
    sys.exit(1)

# ─── Configuración ──────────────────────────────────────────
CONFIG_FILE = Path(__file__).parent / "config.json"
SEEN_FILE = Path(__file__).parent / ".seen_ids.json"

DEFAULT_CONFIG = {
    "telegram_bot_token": "",
    "telegram_chat_id": "",
    "jellyfin_url": "http://localhost:8096",
    "jellyfin_api_key": "",
    "poll_interval_seconds": 300,
    "notify_movies": True,
    "notify_series": True,
    "notify_episodes": True,
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("jellyfin-notifier")


def load_config() -> dict:
    config = DEFAULT_CONFIG.copy()
    if CONFIG_FILE.exists():
        with open(CONFIG_FILE) as f:
            config.update(json.load(f))
    env_map = {
        "TELEGRAM_BOT_TOKEN": "telegram_bot_token",
        "TELEGRAM_CHAT_ID": "telegram_chat_id",
        "JELLYFIN_URL": "jellyfin_url",
        "JELLYFIN_API_KEY": "jellyfin_api_key",
        "POLL_INTERVAL": "poll_interval_seconds",
    }
    for env_key, config_key in env_map.items():
        val = os.environ.get(env_key)
        if val:
            if isinstance(DEFAULT_CONFIG.get(config_key), int):
                val = int(val)
            config[config_key] = val
    return config


def load_seen_ids() -> set:
    if SEEN_FILE.exists():
        return set(json.loads(SEEN_FILE.read_text()))
    return set()


def save_seen_ids(seen_ids: set):
    SEEN_FILE.write_text(json.dumps(list(seen_ids)))


# ─── Telegram ────────────────────────────────────────────────
def send_telegram_message(config: dict, text: str, image_url: str = None) -> bool:
    bot_token = config["telegram_bot_token"]
    chat_id = config["telegram_chat_id"]

    if not bot_token or not chat_id:
        log.error("⚠️  Falta telegram_bot_token o telegram_chat_id")
        return False

    try:
        if image_url:
            api_key = config.get("jellyfin_api_key", "")
            headers = {"X-Emby-Token": api_key} if api_key else {}
            try:
                img_resp = requests.get(image_url, headers=headers, timeout=10)
                img_resp.raise_for_status()
                url = f"https://api.telegram.org/bot{bot_token}/sendPhoto"
                data = {"chat_id": chat_id, "caption": text, "parse_mode": "HTML"}
                files = {"photo": ("poster.jpg", img_resp.content, "image/jpeg")}
                resp = requests.post(url, data=data, files=files, timeout=30)
            except Exception as img_err:
                log.warning(f"⚠️  No se pudo descargar imagen: {img_err}")
                url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
                resp = requests.post(url, json={
                    "chat_id": chat_id, "text": text, "parse_mode": "HTML"
                }, timeout=15)
        else:
            url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
            resp = requests.post(url, json={
                "chat_id": chat_id, "text": text, "parse_mode": "HTML"
            }, timeout=15)

        if resp.status_code == 200:
            log.info("✅ Notificación enviada a Telegram")
            return True
        else:
            log.error(f"❌ Error Telegram ({resp.status_code}): {resp.text}")
            return False
    except Exception as e:
        log.error(f"❌ Error enviando a Telegram: {e}")
        return False


# ─── Formatear mensajes ─────────────────────────────────────
def format_movie_message(item: dict) -> str:
    name = item.get("Name", "Película desconocida")
    year = item.get("ProductionYear", "")
    overview = item.get("Overview", "")
    rating = item.get("CommunityRating", "")
    genres = ", ".join(item.get("Genres", [])[:3])
    runtime = item.get("RunTimeTicks")

    duration = ""
    if runtime:
        minutes = runtime // 600_000_000
        hours = minutes // 60
        mins = minutes % 60
        duration = f"{hours}h {mins}min" if hours else f"{mins}min"

    msg = f"🎬 <b>Nueva película añadida</b>\n\n<b>{name}</b>"
    if year:
        msg += f" ({year})"
    msg += "\n"
    if genres:
        msg += f"📂 {genres}\n"
    if duration:
        msg += f"⏱ {duration}\n"
    if rating:
        msg += f"⭐ {rating}/10\n"
    if overview:
        if len(overview) > 300:
            overview = overview[:297] + "..."
        msg += f"\n<i>{overview}</i>"
    return msg


def format_episode_message(item: dict) -> str:
    series = item.get("SeriesName", "Serie desconocida")
    season = item.get("ParentIndexNumber", "?")
    episode = item.get("IndexNumber", "?")
    ep_name = item.get("Name", "")

    msg = f"📺 <b>Nuevo episodio disponible</b>\n\n"
    msg += f"<b>{series}</b>\n"
    msg += f"Temporada {season} - Episodio {episode}"
    if ep_name:
        msg += f"\n<i>{ep_name}</i>"
    return msg


def format_series_message(item: dict) -> str:
    name = item.get("Name", "Serie desconocida")
    year = item.get("ProductionYear", "")
    overview = item.get("Overview", "")
    genres = ", ".join(item.get("Genres", [])[:3])

    msg = f"📺 <b>Nueva serie añadida</b>\n\n<b>{name}</b>"
    if year:
        msg += f" ({year})"
    msg += "\n"
    if genres:
        msg += f"📂 {genres}\n"
    if overview:
        if len(overview) > 300:
            overview = overview[:297] + "..."
        msg += f"\n<i>{overview}</i>"
    return msg


def get_image_url(item: dict, config: dict) -> str | None:
    item_id = item.get("Id")
    if not item_id:
        return None
    base_url = config["jellyfin_url"].rstrip("/")
    if item.get("ImageTags", {}):
        return f"{base_url}/Items/{item_id}/Images/Primary?maxWidth=500"
    return None


# ─── Jellyfin API ────────────────────────────────────────────
def fetch_all_items(config: dict) -> list:
    """Pide TODOS los items a Jellyfin, paginando de 100 en 100."""
    base_url = config["jellyfin_url"].rstrip("/")
    headers = {"X-Emby-Token": config["jellyfin_api_key"]}

    all_items = []
    start_index = 0
    page_size = 100

    while True:
        params = {
            "SortBy": "DateCreated",
            "SortOrder": "Descending",
            "StartIndex": start_index,
            "Limit": page_size,
            "Recursive": True,
            "IncludeItemTypes": "Movie,Episode,Series",
            "Fields": "Overview,Genres,CommunityRating,RunTimeTicks,ImageTags",
        }
        resp = requests.get(
            f"{base_url}/Items", headers=headers, params=params, timeout=15
        )
        resp.raise_for_status()
        data = resp.json()
        items = data.get("Items", [])
        all_items.extend(items)

        total = data.get("TotalRecordCount", 0)
        start_index += page_size
        if start_index >= total or not items:
            break

    log.info(f"📊 Jellyfin tiene {len(all_items)} elementos en total")
    return all_items


def wait_for_jellyfin(config: dict, max_wait: int = 300) -> bool:
    """Reintenta conectar a Jellyfin cada 10s hasta que responda."""
    base_url = config["jellyfin_url"].rstrip("/")
    headers = {"X-Emby-Token": config["jellyfin_api_key"]}
    waited = 0

    while waited < max_wait:
        try:
            resp = requests.get(
                f"{base_url}/System/Info", headers=headers, timeout=5
            )
            if resp.status_code == 200:
                log.info("✅ Jellyfin está listo")
                return True
        except requests.exceptions.ConnectionError:
            pass
        except Exception:
            pass

        log.info(f"⏳ Esperando a que Jellyfin arranque... ({waited}s)")
        time.sleep(10)
        waited += 10

    log.error(f"❌ Jellyfin no respondió en {max_wait}s")
    return False


# ─── Resumen (primera ejecución) ────────────────────────────
def send_summary_message(config: dict, items: list):
    """Envía un único mensaje resumen con todo el contenido existente."""
    movies = [i for i in items if i.get("Type") == "Movie"]
    series = [i for i in items if i.get("Type") == "Series"]
    episodes = [i for i in items if i.get("Type") == "Episode"]

    msg = "📋 <b>Contenido disponible en Jellyfin</b>\n\n"

    if movies:
        msg += f"🎬 <b>{len(movies)} película(s):</b>\n"
        for m in movies:
            name = m.get("Name", "?")
            year = m.get("ProductionYear", "")
            msg += f"  • {name}"
            if year:
                msg += f" ({year})"
            msg += "\n"
        msg += "\n"

    if series:
        msg += f"📺 <b>{len(series)} serie(s):</b>\n"
        for s in series:
            name = s.get("Name", "?")
            year = s.get("ProductionYear", "")
            ep_count = sum(1 for e in episodes if e.get("SeriesName") == name)
            msg += f"  • {name}"
            if year:
                msg += f" ({year})"
            if ep_count:
                msg += f" — {ep_count} episodios"
            msg += "\n"

    msg += f"\n<i>Total: {len(movies)} películas, {len(series)} series, "
    msg += f"{len(episodes)} episodios</i>"
    msg += "\n\n🔔 <i>A partir de ahora recibirás una notificación por cada novedad.</i>"

    if len(msg) > 4096:
        chunks = []
        lines = msg.split("\n")
        current = ""
        for line in lines:
            if len(current) + len(line) + 1 > 4000:
                chunks.append(current)
                current = line + "\n"
            else:
                current += line + "\n"
        if current:
            chunks.append(current)
        for chunk in chunks:
            send_telegram_message(config, chunk)
            time.sleep(1)
    else:
        send_telegram_message(config, msg)


# ─── Polling principal ───────────────────────────────────────
def poll_jellyfin(config: dict):
    interval = config["poll_interval_seconds"]

    if not config["jellyfin_api_key"]:
        log.error("❌ Falta jellyfin_api_key")
        sys.exit(1)

    if not wait_for_jellyfin(config):
        log.error("❌ No se pudo conectar a Jellyfin. Saliendo...")
        sys.exit(1)

    seen_ids = load_seen_ids()
    first_run = len(seen_ids) == 0

    log.info(f"🚀 Modo POLLING iniciado (cada {interval}s)")
    log.info(f"   Jellyfin: {config['jellyfin_url']}")
    log.info(f"   IDs ya conocidos: {len(seen_ids)}")
    log.info(f"   Primera ejecución: {'Sí' if first_run else 'No'}")

    while True:
        try:
            items = fetch_all_items(config)
            new_items = [i for i in items if i["Id"] not in seen_ids]

            if not new_items:
                log.info("Sin novedades")
            else:
                log.info(f"🆕 {len(new_items)} elemento(s) nuevo(s)")

                if first_run:
                    log.info("📋 Primera ejecución → enviando resumen")
                    send_summary_message(config, new_items)
                    for item in new_items:
                        seen_ids.add(item["Id"])
                    first_run = False
                else:
                    for item in reversed(new_items):
                        item_type = item.get("Type", "")
                        item_id = item["Id"]

                        if item_type == "Movie" and config["notify_movies"]:
                            msg = format_movie_message(item)
                            image_url = get_image_url(item, config)
                            send_telegram_message(config, msg, image_url)
                        elif item_type == "Series" and config["notify_series"]:
                            msg = format_series_message(item)
                            image_url = get_image_url(item, config)
                            send_telegram_message(config, msg, image_url)
                        elif item_type == "Episode" and config["notify_episodes"]:
                            msg = format_episode_message(item)
                            send_telegram_message(config, msg)

                        seen_ids.add(item_id)
                        time.sleep(1)

                save_seen_ids(seen_ids)

        except requests.exceptions.ConnectionError:
            log.warning("⚠️  No se pudo conectar a Jellyfin. Reintentando...")
        except Exception as e:
            log.error(f"❌ Error: {e}")

        time.sleep(interval)


# ─── Main ────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Jellyfin → Telegram Notifier")
    parser.add_argument("--mode", choices=["polling"], default="polling")
    parser.add_argument("--test", action="store_true",
                        help="Enviar mensaje de prueba")
    args = parser.parse_args()

    config = load_config()

    if args.test:
        log.info("📤 Enviando mensaje de prueba...")
        ok = send_telegram_message(
            config,
            "🎉 <b>¡Prueba exitosa!</b>\n\n"
            "El bot de notificaciones de Jellyfin está funcionando correctamente.",
        )
        if ok:
            log.info("✅ ¡Todo funciona!")
        else:
            log.error("❌ Algo falló. Revisa la configuración.")
        return

    if not config["telegram_bot_token"] or not config["telegram_chat_id"]:
        log.error("❌ Falta telegram_bot_token o telegram_chat_id")
        sys.exit(1)

    poll_jellyfin(config)


if __name__ == "__main__":
    main()
```

### requirements.txt

```bash
nano requirements.txt
```

```
requests>=2.28.0
```

---

## Paso 6: Instalar dependencias en un entorno virtual

Usamos un venv para no instalar paquetes globalmente en el sistema:

```bash
cd /opt/jellyfin-telegram
python3 -m venv venv
source venv/bin/activate
pip install requests
```

---

## Paso 7: Probar que funciona

```bash
python3 notifier.py --test
```

Si todo está bien configurado, recibirás un mensaje en el grupo de Telegram con el texto "¡Prueba exitosa!". Si da error, revisa que los tres datos de `config.json` estén correctos.

---

## Paso 8: Crear el servicio de systemd

Para que el notificador se ejecute automáticamente y sobreviva a reinicios del servidor:

```bash
sudo nano /etc/systemd/system/jellyfin-telegram.service
```

```ini
[Unit]
Description=Jellyfin Telegram Notifier
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/jellyfin-telegram
ExecStart=/opt/jellyfin-telegram/venv/bin/python3 notifier.py --mode polling
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

> `After=docker.service` y `Wants=docker.service` aseguran que el servicio se inicie después de Docker. Además, el propio script incluye un bucle de espera que reintenta la conexión a Jellyfin cada 10 segundos durante hasta 5 minutos.
{: .prompt-info }

Activar y arrancar el servicio:

```bash
sudo systemctl daemon-reload
sudo systemctl enable jellyfin-telegram
sudo systemctl start jellyfin-telegram
```

Verificar que está corriendo:

```bash
sudo systemctl status jellyfin-telegram
```

Para ver los logs en tiempo real:

```bash
journalctl -u jellyfin-telegram -f
```

---

## Comportamiento del script

### Primera ejecución

El script detecta que no existe el fichero `.seen_ids.json` (o está vacío) y lo interpreta como primera ejecución. En este caso:

1. Consulta **todo** el contenido de Jellyfin paginando de 100 en 100
2. Envía **un único mensaje resumen** al grupo con la lista de películas y series
3. Guarda todos los IDs en `.seen_ids.json`

### Ejecuciones posteriores

Cada 5 minutos (configurable) el script:

1. Consulta todos los items de Jellyfin
2. Compara con los IDs guardados
3. Si hay items nuevos, envía una **notificación individual** por cada uno (película con póster, serie con póster, episodio con texto)
4. Actualiza `.seen_ids.json`

### Imágenes

Las notificaciones de películas y series incluyen el póster. Como Jellyfin corre en local y Telegram no puede acceder a `http://localhost:8096`, el script descarga la imagen de Jellyfin y la sube directamente a Telegram como archivo. Si la descarga falla por cualquier motivo, envía la notificación solo con texto.

---

## Gestión y mantenimiento

### Reiniciar el servicio

```bash
sudo systemctl restart jellyfin-telegram
```

### Forzar reenvío de todo el contenido

Si quieres que el script vuelva a enviar el resumen como si fuera la primera vez:

```bash
rm /opt/jellyfin-telegram/.seen_ids.json
sudo systemctl restart jellyfin-telegram
```

### Ver el estado

```bash
sudo systemctl status jellyfin-telegram
journalctl -u jellyfin-telegram --since "1 hour ago"
```

### Cambiar el intervalo de comprobación

Edita `config.json` y cambia `poll_interval_seconds`. Por ejemplo, para comprobar cada 2 minutos:

```json
"poll_interval_seconds": 120
```

Reinicia el servicio para aplicar el cambio.

### Desactivar notificaciones de episodios

Si solo quieres recibir avisos de películas y series nuevas pero no de cada episodio individual:

```json
"notify_episodes": false
```

---

## Troubleshooting

### El script no conecta a Jellyfin tras un reinicio

El script espera hasta 5 minutos reintentando cada 10 segundos. Si Jellyfin tarda más en arrancar, puedes aumentar el tiempo de espera en la función `wait_for_jellyfin` del script, o bien añadir un delay en el servicio de systemd:

```ini
ExecStartPre=/bin/sleep 30
```

### Error "wrong remote file" en los logs

Esto ocurre si el script intenta pasar una URL local a Telegram en vez de subir la imagen directamente. Asegúrate de estar usando la versión del script que descarga la imagen de Jellyfin y la sube como archivo.

### No llegan mensajes al grupo

1. Verifica que el bot está en el grupo
2. Comprueba que el `chat_id` en `config.json` es correcto (número negativo)
3. Ejecuta `python3 notifier.py --test` para descartar problemas de configuración
4. Revisa los logs con `journalctl -u jellyfin-telegram -f`

### El resumen inicial no muestra todas las películas/series

El script pagina de 100 en 100 hasta obtener todos los items. Si aun así falta contenido, puede ser que Jellyfin no haya terminado de escanear las bibliotecas. Ejecuta un escaneo manual desde el panel de Jellyfin y después reinicia el servicio.
