---
title: Servidor de Correo Completo con Postfix, Dovecot y Roundcube
date: 2026-04-12 16:27:00 +0200
categories: [Linux, Correo]
tags: [postfix, dovecot, roundcube, opendkim, correo, smtp, imap, homelab, proxmox, ionos, cloudflare, certbot]
---

Guía completa para montar un servidor de correo profesional con Postfix, Dovecot, OpenDKIM y Roundcube en un homelab con Proxmox, usando un VPS barato como relay SMTP.

---

## Arquitectura

El servidor de correo se divide en tres máquinas:

- **VPS IONOS** (IP pública fija) → Solo actúa como relay SMTP. Recibe correo del mundo y lo reenvía a casa. Recibe correo de casa y lo entrega al destino.
- **LXC Correo** (Proxmox, IP privada) → Servidor de correo principal. Almacena los buzones, firma con DKIM, sirve IMAP y Roundcube.
- **LXC Proxy Inverso** (Proxmox) → Termina SSL con certificado wildcard y reenvía el tráfico web a cada servicio.

```
                          INTERNET
                             │
            ┌────────────────┼──────────────────┐
            ▼                                   ▼
┌─────────────────────┐              ┌────────────────────────────┐
│   VPS (relay)       │              │  Homelab (Proxmox)         │
│   IP fija pública   │              │  IP dinámica               │
│                     │              │                            │
│   Postfix           │              │  ┌─ LXC Proxy ───────────┐ │
│   ├ :25  ← mundo    │   ─:2525─►   │  │  Nginx + wildcard SSL │ │
│   ├ :587 ← casa     │              │  └───────────────────────┘ │
│   └ :25  → mundo    │              │                            │
│                     │   ◄─:587──   │  ┌─ LXC Correo ──────────┐ │
│   PTR ✓  TLS ✓      │              │  │  Postfix    :25/2525  │ │
│                     │              │  │  Dovecot    :993      │ │
└─────────────────────┘              │  │  OpenDKIM   :8891     │ │
                                     │  │  Roundcube  :80       │ │
                                     │  └───────────────────────┘ │
                                     └────────────────────────────┘
```

### ¿Por qué esta arquitectura?

**¿Por qué un VPS relay?** La IP de casa es dinámica y residencial. Gmail y Outlook desconfían de IPs residenciales y marcan el correo como spam. El VPS tiene IP fija, PTR configurado y buena reputación.

**¿Por qué puerto 2525?** Muchos ISPs residenciales (Orange en España, por ejemplo) bloquean el puerto 25 entrante. El VPS reenvía correo a casa por el 2525, que se redirige con port forwarding en el router.

**¿Por qué SASL y no la IP en mynetworks?** La IP de casa es dinámica. Si cambia, el relay deja de funcionar. SASL autentica por usuario y contraseña, funciona desde cualquier IP.

---

## Requisitos previos

- Un VPS con IP pública fija, puerto 25 saliente desbloqueado y posibilidad de configurar reverse DNS (PTR)
- Un servidor Proxmox (o cualquier hipervisor) en casa
- Un dominio con DNS gestionados en Cloudflare (proxy desactivado para registros de correo)
- Port forwarding en el router: puertos 2525, 443, 587 y 993 hacia el LXC de correo

---

## Parte 1: DNS (Cloudflare)

Antes de tocar ningún servidor, configura los registros DNS. Los registros de correo deben tener el **proxy de Cloudflare desactivado** (nube gris, DNS only). Cloudflare solo hace proxy de HTTP/HTTPS, no de SMTP/IMAP.

| Tipo | Nombre | Contenido | Proxy |
| --- | --- | --- | --- |
| A | `mail` | IP del VPS | OFF |
| MX | `@` | `mail.tudominio.es` (prioridad 10) | — |
| TXT | `@` | `v=spf1 a mx a:mail.tudominio.es a:home.tudominio.es ~all` | — |
| TXT | `_dmarc` | `v=DMARC1; p=quarantine; rua=mailto:tu@tudominio.es` | — |

El registro DKIM se añade más adelante cuando se generen las claves.

> El registro A de `home.tudominio.es` (tu IP dinámica) también debe tener el proxy desactivado si lo vas a usar para recibir correo.
{: .prompt-warning }

### Verificar propagación

```bash
dig MX tudominio.es +short
dig A mail.tudominio.es +short
dig TXT tudominio.es +short
```

---

## Parte 2: VPS — Relay SMTP

El VPS solo hace de intermediario. No almacena correo, no tiene Dovecot, no tiene webmail.

### Configuración base

```bash
hostnamectl set-hostname mail.tudominio.es
```

Edita `/etc/hosts`:

```
127.0.0.1       localhost
IP_DEL_VPS      mail.tudominio.es mail
```

### Configurar Reverse DNS (PTR)

En el panel del proveedor de VPS, configura el reverse DNS de la IP pública para que apunte a `mail.tudominio.es`. Cada proveedor lo tiene en un sitio distinto. Verifica con:

```bash
dig -x IP_DEL_VPS +short
# Debe devolver: mail.tudominio.es.
```

> En IONOS, el puerto 25 saliente está bloqueado por defecto. Hay que contactar con soporte para que lo desbloqueen. Antes de llamar necesitas tener configurado el hostname, el PTR y el registro SPF.
{: .prompt-info }

### Certificado SSL

```bash
apt install -y certbot
certbot certonly --standalone -d mail.tudominio.es \
  --agree-tos --no-eff-email --email tu@tudominio.es
```

### Instalar Postfix

```bash
apt install -y postfix
# Tipo: Internet Site
# System mail name: tudominio.es
```

Edita `/etc/postfix/main.cf`:

```ini
# Identificación
myhostname = mail.tudominio.es
mydomain = tudominio.es
myorigin = $mydomain

# Interfaces
inet_interfaces = all
inet_protocols = ipv4

# Este VPS NO almacena correo, solo lo reenvía
mydestination =
relay_domains = tudominio.es
transport_maps = hash:/etc/postfix/transport

# Solo aceptar relay autenticado
mynetworks = 127.0.0.0/8

# TLS
smtpd_tls_cert_file = /etc/letsencrypt/live/mail.tudominio.es/fullchain.pem
smtpd_tls_key_file = /etc/letsencrypt/live/mail.tudominio.es/privkey.pem
smtpd_tls_security_level = may
smtp_tls_security_level = may
smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1

# SASL Auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_type = cyrus
smtpd_sasl_path = smtpd
smtpd_sasl_security_options = noanonymous
smtpd_relay_restrictions = permit_sasl_authenticated, reject_unauth_destination
broken_sasl_auth_clients = yes

# Límites
message_size_limit = 26214400
mailbox_size_limit = 0
```

> `mydestination` está vacío a propósito. El VPS no es destino final de ningún correo, solo relay. El correo entrante para `@tudominio.es` lo gestiona `relay_domains` + `transport_maps`.
{: .prompt-info }

### Fichero de transporte

Crea `/etc/postfix/transport`:

```
tudominio.es    smtp:[home.tudominio.es]:2525
```

Los corchetes `[]` significan "conecta directamente a ese host, no busques su MX". Sin ellos, Postfix buscaría el MX de `home.tudominio.es` y entraría en bucle.

```bash
postmap /etc/postfix/transport
```

### Configurar SASL

```bash
apt install -y sasl2-bin libsasl2-modules

# Crear usuario para el relay
saslpasswd2 -c -u mail.tudominio.es relay_user
# Escribe una contraseña fuerte

# Permisos
chown postfix:postfix /etc/sasldb2
chmod 640 /etc/sasldb2

# Copiar al chroot de Postfix (importante)
mkdir -p /var/spool/postfix/etc
cp /etc/sasldb2 /var/spool/postfix/etc/sasldb2
chown postfix:postfix /var/spool/postfix/etc/sasldb2
chmod 640 /var/spool/postfix/etc/sasldb2
```

> Postfix en Debian corre en un chroot (`/var/spool/postfix`). Cuando intenta abrir `/etc/sasldb2`, en realidad busca `/var/spool/postfix/etc/sasldb2`. Sin esta copia, la autenticación falla con el error `unable to canonify user and get auxprops`.
{: .prompt-warning }

Crea `/etc/postfix/sasl/smtpd.conf`:

```
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN
sasldb_path: /etc/sasldb2
```

### Habilitar submission (587)

En `/etc/postfix/master.cf`, descomenta o añade:

```
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
```

```bash
systemctl restart postfix
```

---

## Parte 3: LXC Correo — Servidor principal

### Crear el LXC

En Proxmox, crea un contenedor con Debian 12 o 13, IP estática en tu red local, al menos 1 GB de RAM y 8-10 GB de disco.

```bash
hostnamectl set-hostname correo.tudominio.es
```

### Instalar Postfix

```bash
apt install -y postfix
```

Edita `/etc/postfix/main.cf`:

```ini
# Identificación
myhostname = correo.tudominio.es
mydomain = tudominio.es
myorigin = $mydomain

# Red
inet_interfaces = all
inet_protocols = ipv4
mydestination = $myhostname, localhost.$mydomain, localhost

# Relay saliente al VPS
relayhost = [mail.tudominio.es]:587
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_security_level = encrypt
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt

# Entrega local a Dovecot vía LMTP
virtual_transport = lmtp:unix:private/dovecot-lmtp
virtual_mailbox_domains = tudominio.es
virtual_mailbox_maps = hash:/etc/postfix/virtual_mailbox

# TLS servidor
smtpd_tls_cert_file = /etc/ssl/tudominio/fullchain.pem
smtpd_tls_key_file = /etc/ssl/tudominio/privkey.pem
smtpd_tls_security_level = may

# Seguridad
smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination
smtpd_sasl_auth_enable = yes
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth

# Límites
message_size_limit = 26214400
mailbox_size_limit = 0

# DKIM
milter_protocol = 6
milter_default_action = accept
smtpd_milters = inet:localhost:8891
non_smtpd_milters = inet:localhost:8891
```

> `tudominio.es` NO debe estar en `mydestination` y en `virtual_mailbox_domains` a la vez. Si está en ambos, Postfix se confunde. Lo dejamos solo en `virtual_mailbox_domains` porque usamos buzones virtuales con Dovecot.
{: .prompt-warning }

Crea `/etc/postfix/sasl_passwd`:

```
[mail.tudominio.es]:587    relay_user@mail.tudominio.es:TU_CONTRASEÑA
```

```bash
postmap /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
```

Crea `/etc/postfix/virtual_mailbox`:

```
tu@tudominio.es    OK
```

```bash
postmap /etc/postfix/virtual_mailbox
```

Instala las librerías SASL necesarias:

```bash
apt install -y libsasl2-modules
```

> Sin `libsasl2-modules`, Postfix no puede autenticarse contra el VPS relay y falla con `SASL authentication failure: No worthy mechs found`.
{: .prompt-warning }

En `/etc/postfix/master.cf`, añade el puerto 2525 y submission:

```
smtp      inet  n       -       y       -       -       smtpd
2525      inet  n       -       y       -       -       smtpd
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
```

### Instalar Dovecot

```bash
apt install -y dovecot-core dovecot-imapd dovecot-lmtpd dovecot-sieve dovecot-managesieved
```

Crear usuario para buzones:

```bash
groupadd -g 5000 vmail
useradd -g vmail -u 5000 -d /var/vmail -m -s /usr/sbin/nologin vmail
mkdir -p /var/vmail/tudominio.es
chown -R vmail:vmail /var/vmail
chmod -R 770 /var/vmail
```

> Los ejemplos de configuración de Dovecot a continuación son para **Dovecot 2.4** (Debian 13). La versión 2.4 cambió significativamente la sintaxis respecto a 2.3: los bloques `passdb` y `userdb` necesitan nombre, `args` se reemplaza por parámetros individuales, y las variables cortas como `%d` y `%n` cambian a `%{user|domain}` y `%{user|username}`.
{: .prompt-warning }

#### dovecot.conf

Añade o descomenta:

```
protocols = imap lmtp
```

> No pongas `sieve` ni `managesieve` aquí. El protocolo se registra automáticamente al instalar `dovecot-managesieved` vía el fichero `/usr/share/dovecot/protocols.d/managesieved.protocol`. Si lo añades manualmente, Dovecot falla con `Unknown protocol`.
{: .prompt-info }

#### conf.d/10-mail.conf

Cambia las líneas de formato de buzón:

```ini
mail_driver = maildir
mail_home = /var/vmail/%{user|domain}/%{user|username}
mail_path = %{home}/Maildir
mail_inbox_path = %{home}/Maildir
mail_privileged_group = vmail
mail_uid = 5000
mail_gid = 5000
```

#### conf.d/10-auth.conf

```ini
auth_allow_cleartext = no
auth_mechanisms = plain login
```

Y cambia la inclusión de base de datos de autenticación:

```ini
#!include auth-system.conf.ext
!include auth-passwdfile.conf.ext
```

#### conf.d/auth-passwdfile.conf.ext

Crea este fichero con la sintaxis de Dovecot 2.4:

```ini
passdb passwd-file {
  passwd_file_path = /etc/dovecot/users
  default_password_scheme = BLF-CRYPT
}

userdb static {
  fields {
    uid = 5000
    gid = 5000
    home = /var/vmail/%{user|domain}/%{user|username}
  }
}
```

> En Dovecot 2.3 esto se hacía con `passdb { driver = passwd-file; args = scheme=BLF-CRYPT /etc/dovecot/users }`. En 2.4 cada parámetro tiene su propio campo y los bloques necesitan nombre (`passwd-file`, `static`).
{: .prompt-info }

#### Crear cuenta de correo

```bash
doveadm pw -s BLF-CRYPT
# Escribe tu contraseña, devuelve un hash

nano /etc/dovecot/users
```

```
tu@tudominio.es:{BLF-CRYPT}$2y$05$HASH_COMPLETO
```

```bash
chown dovecot:dovecot /etc/dovecot/users
chmod 640 /etc/dovecot/users
```

#### conf.d/10-ssl.conf

```ini
ssl = required
ssl_server_cert_file = /etc/ssl/tudominio/fullchain.pem
ssl_server_key_file = /etc/ssl/tudominio/privkey.pem
ssl_min_protocol = TLSv1.2
```

#### conf.d/10-master.conf

Configura los sockets para comunicación con Postfix:

```ini
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}

service auth {
  unix_listener auth-userdb {
    mode = 0600
    user = vmail
    group = vmail
  }
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
```

El socket `dovecot-lmtp` es la tubería por la que Postfix pasa los correos entrantes a Dovecot. El socket `auth` es donde Postfix pregunta a Dovecot si un usuario y contraseña son válidos cuando alguien intenta enviar correo.

#### conf.d/15-lda.conf

```ini
protocol lda {
  mail_plugins {
    sieve = yes
  }
  postmaster_address = tu@tudominio.es
}

protocol lmtp {
  mail_plugins {
    sieve = yes
  }
  postmaster_address = tu@tudominio.es
}
```

#### conf.d/20-lmtp.conf

Si existe una línea `auth_username_format` en este fichero, **coméntala**. Si está activa con el valor `%{user | username | lower}`, transforma `tu@tudominio.es` en `tu` antes de buscarlo en el fichero de usuarios, y como en el fichero está como `tu@tudominio.es`, no lo encuentra y devuelve `User doesn't exist`.

### Instalar OpenDKIM

```bash
apt install -y opendkim opendkim-tools
mkdir -p /etc/opendkim/keys/tudominio.es

opendkim-genkey -b 2048 -d tudominio.es \
  -D /etc/opendkim/keys/tudominio.es -s mail -v

chown -R opendkim:opendkim /etc/opendkim
chmod 700 /etc/opendkim/keys
```

Edita `/etc/opendkim.conf`:

```ini
Syslog                  yes
SyslogSuccess           yes
LogWhy                  yes
Canonicalization        relaxed/simple
Mode                    sv
OversignHeaders         From
Domain                  tudominio.es
Selector                mail
KeyFile                 /etc/opendkim/keys/tudominio.es/mail.private
UserID                  opendkim
UMask                   007
Socket                  inet:8891@localhost
PidFile                 /run/opendkim/opendkim.pid
TrustAnchorFile         /usr/share/dns/root.key
```

Publica la clave DKIM en DNS:

```bash
cat /etc/opendkim/keys/tudominio.es/mail.txt
```

Crea un registro TXT en Cloudflare con nombre `mail._domainkey` y el contenido de la clave pública (todo en una línea, sin comillas ni paréntesis).

```bash
systemctl enable opendkim
systemctl start opendkim
```

### Certificado SSL

Hay dos opciones para obtener el certificado en el LXC de correo:

**Opción A: Generar uno propio con DNS challenge de Cloudflare:**

```bash
apt install -y certbot python3-certbot-dns-cloudflare

mkdir -p /root/.secrets
echo "dns_cloudflare_api_token = TU_TOKEN" > /root/.secrets/cloudflare.ini
chmod 600 /root/.secrets/cloudflare.ini

certbot certonly --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/cloudflare.ini \
  -d correo.tudominio.es \
  --agree-tos --no-eff-email --email tu@tudominio.es
```

**Opción B: Usar un certificado wildcard generado en otra máquina** y copiarlo periódicamente con un script de deploy. En este caso los certificados se guardan en `/etc/ssl/tudominio/` y se distribuyen automáticamente tras cada renovación.

### Arrancar y verificar

```bash
systemctl restart postfix
systemctl restart dovecot
systemctl restart opendkim

# Verificar puertos
ss -tlnp | grep -E '25|587|993|2525|4190|8891'

# Probar autenticación
doveadm auth test tu@tudominio.es
```

---

## Parte 4: Roundcube

### Instalar dependencias

```bash
apt install -y apache2 mariadb-server php php-mysql php-mbstring \
  php-curl php-xml php-zip php-gd php-intl php-opcache libapache2-mod-php

a2enmod rewrite ssl headers
```

> En Debian 13, el paquete `php-imap` no existe en los repositorios. Roundcube funciona sin él.
{: .prompt-info }

### Configurar MariaDB

```bash
mysql_secure_installation

mysql -u root -p
```

```sql
CREATE DATABASE roundcubemail CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'roundcube'@'localhost' IDENTIFIED BY 'CONTRASEÑA_SEGURA';
GRANT ALL PRIVILEGES ON roundcubemail.* TO 'roundcube'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### Instalar Roundcube

```bash
cd /tmp
wget https://github.com/roundcube/roundcubemail/releases/download/1.6.9/roundcubemail-1.6.9-complete.tar.gz
tar xzf roundcubemail-1.6.9-complete.tar.gz
mv roundcubemail-1.6.9 /var/www/roundcube

chown -R www-data:www-data /var/www/roundcube
chmod -R 755 /var/www/roundcube
chmod -R 775 /var/www/roundcube/temp /var/www/roundcube/logs

mysql -u roundcube -p roundcubemail < /var/www/roundcube/SQL/mysql.initial.sql
```

### Configurar Apache

Como el proxy inverso ya termina SSL, Apache solo escucha en HTTP:

```bash
cat > /etc/apache2/sites-available/roundcube.conf << 'EOF'
<VirtualHost *:80>
    ServerName webmail.tudominio.es
    DocumentRoot /var/www/roundcube/public_html

    <Directory /var/www/roundcube/public_html>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <DirectoryMatch "/var/www/roundcube/(config|temp|logs|SQL|bin)">
        Require all denied
    </DirectoryMatch>

    ErrorLog ${APACHE_LOG_DIR}/roundcube-error.log
    CustomLog ${APACHE_LOG_DIR}/roundcube-access.log combined
</VirtualHost>
EOF

a2ensite roundcube.conf
a2dissite 000-default.conf
systemctl reload apache2
```

### Configurar Roundcube

```bash
openssl rand -hex 24
# Guarda el resultado

cp /var/www/roundcube/config/config.inc.php.sample \
   /var/www/roundcube/config/config.inc.php
nano /var/www/roundcube/config/config.inc.php
```

```php
<?php

$config['des_key'] = 'CLAVE_DE_openssl_rand';
$config['db_dsnw'] = 'mysql://roundcube:CONTRASEÑA_BD@localhost/roundcubemail';
$config['imap_host'] = 'ssl://localhost:993';
$config['smtp_host'] = 'tls://localhost:587';
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['imap_conn_options'] = [
    'ssl' => ['verify_peer' => true, 'verify_peer_name' => false]
];
$config['smtp_conn_options'] = [
    'ssl' => ['verify_peer' => true, 'verify_peer_name' => false]
];
$config['product_name'] = 'Mi Webmail';
$config['username_domain'] = 'tudominio.es';
$config['plugins'] = [
    'archive',
    'zipdownload',
    'managesieve',
    'markasjunk',
];
$config['language'] = 'es_ES';
$config['timezone'] = 'Europe/Madrid';
$config['force_https'] = false;
$config['use_https'] = true;
$config['max_message_size'] = '25M';
$config['trash_mbox'] = 'Trash';
$config['junk_mbox'] = 'Junk';
$config['drafts_mbox'] = 'Drafts';
$config['sent_mbox'] = 'Sent';
```

> `verify_peer_name = false` es necesario porque Roundcube se conecta a `localhost`, pero el certificado es para `*.tudominio.es`. El nombre no coincide, pero la conexión sigue siendo segura porque `verify_peer = true` valida que el certificado sea legítimo.
{: .prompt-info }

> `force_https = false` evita bucles de redirección ya que Apache recibe HTTP del proxy inverso. `use_https = true` hace que Roundcube genere URLs con `https://`.
{: .prompt-info }

---

## Parte 5: Proxy inverso

En el LXC del proxy inverso, añade un bloque para Roundcube:

```nginx
server {
    listen 80;
    server_name webmail.tudominio.es;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name webmail.tudominio.es;
    include snippets/ssl-wildcard.conf;

    location / {
        proxy_pass http://IP_LXC_CORREO;
        include proxy_params;
    }
}
```

```bash
nginx -t && systemctl reload nginx
```

---

## Parte 6: Verificación y pruebas

### Probar login

Accede a `https://webmail.tudominio.es` e inicia sesión con tu usuario (sin el `@tudominio.es` si configuraste `username_domain`).

### Probar envío

Envía un correo a una dirección de Gmail. El flujo es:

```
Roundcube → Postfix local (:587) → OpenDKIM firma → VPS relay (:587 SASL) → Gmail (:25)
```

### Probar recepción

Envía un correo desde Gmail a `tu@tudominio.es`. El flujo es:

```
Gmail → VPS (MX, :25) → home.tudominio.es (:2525) → Postfix local → Dovecot (LMTP) → buzón
```

### Verificar puntuación

Envía un correo a [mail-tester.com](https://www.mail-tester.com/) y comprueba que obtienes 9/10 o 10/10.

### Comprobar blacklists

Visita [mxtoolbox.com/blacklists.aspx](https://mxtoolbox.com/blacklists.aspx) e introduce la IP del VPS.

---

## Mantenimiento

### Añadir una cuenta nueva

```bash
# Generar hash de contraseña
doveadm pw -s BLF-CRYPT

# Añadir a Dovecot
echo 'nueva@tudominio.es:{BLF-CRYPT}$2y$05$HASH' >> /etc/dovecot/users

# Añadir a Postfix
echo 'nueva@tudominio.es    OK' >> /etc/postfix/virtual_mailbox
postmap /etc/postfix/virtual_mailbox

# Recargar
systemctl reload postfix dovecot
```

### Añadir un alias

Crea o edita `/etc/postfix/virtual_alias`:

```
contacto@tudominio.es    tu@tudominio.es
```

```bash
postmap /etc/postfix/virtual_alias
```

Añade a `main.cf`:

```ini
virtual_alias_maps = hash:/etc/postfix/virtual_alias
```

```bash
systemctl reload postfix
```

### Ver logs

```bash
# Postfix
journalctl -u postfix -f

# Dovecot
journalctl -u dovecot -f

# Roundcube
tail -f /var/www/roundcube/logs/errors.log

# Cola de correo
postqueue -p

# Forzar reenvío
postqueue -f
```

### Backups

```bash
# Buzones
tar czf backup-mail.tar.gz /var/vmail/

# Base de datos Roundcube
mysqldump -u roundcube -p roundcubemail > backup-roundcube.sql

# Configuración
tar czf backup-config.tar.gz /etc/postfix/ /etc/dovecot/ /etc/opendkim/
```

### Cambiar contraseña SASL del relay

```bash
# En el VPS
saslpasswd2 -c -u mail.tudominio.es relay_user
cp /etc/sasldb2 /var/spool/postfix/etc/sasldb2
chown postfix:postfix /var/spool/postfix/etc/sasldb2

# En el LXC de correo
nano /etc/postfix/sasl_passwd
# Actualiza la contraseña
postmap /etc/postfix/sasl_passwd
postfix reload
```

---

## Troubleshooting

### Login failed en Roundcube

Verificar que Dovecot escucha y la autenticación funciona:

```bash
ss -tlnp | grep 993
doveadm auth test tu@tudominio.es
```

### SASL authentication failed (No worthy mechs found)

Falta `libsasl2-modules` en el LXC de correo:

```bash
apt install -y libsasl2-modules
postfix reload
```

### SASL authentication failed (unable to canonify user)

El fichero `sasldb2` no está copiado en el chroot de Postfix del VPS:

```bash
cp /etc/sasldb2 /var/spool/postfix/etc/sasldb2
chown postfix:postfix /var/spool/postfix/etc/sasldb2
systemctl restart postfix
```

### User doesn't exist (LMTP)

Comprobar que `auth_username_format` no está transformando el usuario en `conf.d/20-lmtp.conf`. Comentar la línea si existe.

### Correo llega a spam

Verificar SPF, DKIM y DMARC con [mail-tester.com](https://www.mail-tester.com/). Comprobar PTR del VPS. Verificar que la IP no está en blacklists.

### Connection timed out al recibir

El port forwarding del 2525 no funciona o el proxy de Cloudflare está activado en `home.tudominio.es`. Verificar que resuelve a tu IP real, no a una IP de Cloudflare.

---

## Referencias

- [Documentación de Postfix](https://www.postfix.org/documentation.html)
- [Documentación de Dovecot 2.4](https://doc.dovecot.org/main/)
- [Migración de Dovecot 2.3 a 2.4](https://doc.dovecot.org/main/installation/upgrade/2.3-to-2.4.html)
- [Documentación de Roundcube](https://github.com/roundcube/roundcubemail/wiki)
- [OpenDKIM](http://www.opendkim.org/)
