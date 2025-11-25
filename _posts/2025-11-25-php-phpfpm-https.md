---
title: PHP PHP-FPM HTTPS
date: 2025-11-25 20:42:00 +0200
categories: [Linux, Resumen]
tags: [php, php-fpm, https, linux]
---

# Teoría

## PHP

- PHP es un lenguaje de programación, normalmente se usa dentro de HTML.

- Se pueden servir páginas web de varias formas:

  - Servidor web Apache2 y el módulo libapache2-mod-php, donde el servidor web sirve el contenido estático y el contenido dinámico generado por el PHP.

  - Servidor web Apache2 y un servidor de aplicaciones como php-fpm, donde el servidor web sirve el contenido estático y hace de proxy inverso, es decir, manda las peticiones que necesitan ejecutar PHP al servidor de aplicaciones php-fpm y este devuelve el código HTML ya con el código PHP ejecutado. El servidor php-fpm puede escuchar por socket o por tcp (puerto).

  - Servidor web nginx y un servidor de aplicaciones como php-fpm, donde el funcionamiento es el mismo que en el caso anterior.

- Un servidor LAMP se compone de 4 elementos: Linux -> Apache -> MariaDB -> PHP.

- Un servidor LEMP es igual pero el servidor web es Nginx en vez de Apache.

- Un CMS es un sistema de gestión de contenidos (Content Management System), es un programa que permite crear y administrar contenidos, principalmente páginas web.

- Los pasos para la instalación de un CMS son los siguientes:

  1. Crear la base de datos y el usuario que va a utilizar el CMS para guardar la información.

  2. Decidir como instalar el CMS, o en un VirtualHost donde se accedería normalmente con cms.dominio.algo, o en un directorio donde se accedería normalmente con dominio.algo/wordpress.

  3. Descargar los ficheros del CMS y subirlos al servidor. Esto se puede hacer con muchos metodos, algunos de ellos son: scp, wget, GitHub.

  4. Acceder a la URL de la instalación del CMS y comenzar con la configuración.

  5. Indicar las credenciales principales de la base de datos, normalmente:

     - Dirección del servidor de base de datos (si está en el mismo equipo `localhost`).

     - Nombre de la base de datos.

     - Usuario de la base de datos.

     - Contraseña de la base de datos.

  6. Probablemente será necesario realizar la instalación de alguna librería de PHP, ya que los CMS hacen uso de ellas. Normalmente se realiza con `sudo apt install php-algo`.

  7. En la mayoría de CMS será necesario configurar credenciales de administrador, como por ejemplo usuario y contraseña.

## HTTPS

- Usar HTTPS nos permite cifrar el contenido que se transmite entre el cliente y el servidor, y confiar en la autenticidad de la página web (dependiendo de la reputación que tenga la autoridad certificadora).

- Usa el protocolo SSL para cifrar los datos.

- Normalmente se usa el puerto 443 para HTTPS, a diferencia del puerto 80 que se usa para HTTP.

- Utiliza mecanismos de cifrado de clave pública y se denominan certificados.

- El formato de los certificados está especificado por el estándar x.509 y estos los emiten entidades (Autoridad Certificadora o CA).

- La función de las CA es demostrar la autenticidad del servidor y asegurar que pertenecen a quien dicen ser.

- Los navegadores contienen una lista de certificados de CA en los que confían, por lo que solamente aceptaran los certificados de los servidores emitidos por alguna de esas CA.

- Una vez aceptado el certificado de un servidor web, el navegador lo utiliza para comunicar la clave simétrica entre el y el servidor.

- Esta clave se utilizar para cifrar los datos que se requiere enviar al servidor mediante el protocolo HTTPS.

- Para generar un certificado se hará lo siguiente:

  1. Se genera una clave privada y una clave pública.

  2. Se genera un fichero de solicitud de firma de certificado (CSR).

  3. Al realizar el CSR se debe indicar o el nombre del servidor (subdominio.dominio.algo), o el wildcard (\*.dominio.algo). Este último se usa para no tener que sacar un certificado por cada subdominio del dominio.

  4. La CA tendrá que verificar que la persona que solicita el certificado es propietaria del servidor y que sea quien dice ser, cuanto más profunda sea la investigación más caro será el certificado ya que asegura mucho más la autenticidad.

  5. El CSR se tendrá que enviar a la Autoridad Certificadora para que esta la firme con su clave privada. Esto nos lo tendrán que mandar de vuelta ya que esa será nuestra clave pública firmada por la CA.

  6. En el navegador cargaremos la clave pública de la CA o si es una autoridad oficial ya estará incluida en la lista del navegador, esto se hace para que el navegador pueda verificar la autenticidad del certificado y confiar en al página.

- Una CA gratuita puede ser Let's Encrypt. Se trata de una Autoridad Certificadora libre impulsada por la Fundación Linux. Permite certificados SSL gratuitos y automáticos.

- Utiliza el protocolo ACME (Automatic Certificate Management Environment), el cual realiza dos pasos: La validación del dominio y la solicitud del certificado.

- Existen dos agentes que hacen el trabajo por nosotros: Let's Encrypt CA y Certbot.

- Let's Encrypt identifica al administrador del servidor por claves RSA:

  1. La primera vez se genera un nuevo par de claves.

  2. El agente demuestra a Let's Encrypt CA que el servidor controla uno o más dominios.

  3. Para hacer la demostración se usa uno de los dos challenger posibles:

     - HTTP-01 challenger: Coloca un fichero con una determinada información en una URL específica del servidor que Let's Encrypt CA puede verificar.

     - DNS-01 challenger: Crea un registro en el DNS con una determinada información.

# Práctica

## PHP

### Instalación de un servidor LAMP + PHP

```bash
sudo apt install apache2 mariadb php libapache2-mod-php php-mysql -y
```

- `apache2`: Servidor web.

- `mariadb`: Base de datos MariaDB.

- `php`: Paquete que contiene lo necesario para que se puedan ejecutar las peticiones PHP.

- `libapache2-mod-php`: Módulo de apache2 que permite ejecutar código PHP.

- `php-mysql`: Librería de PHP que permite a PHP el acceso a la base de datos.

- El Virtual Host no deberá tener ninguna configuración adicional en esta forma de ejecutar código PHP en apache2.

### Instalación de un servidor LAMP + PHP-FPM

```bash
sudo apt install apache2 mariadb php-fpm php-mysql -y
```

- `/etc/php/8.4/fpm/php-fpm.conf` -> Configuración general de php-fpm.

- `/etc/php/8.4/fpm/pool.d/` -> Directorio con pools de configuración. Cada aplicación puede tener una configuración distinta (procesos distintos) de php-fpm.

- Por defecto hay un pool creado (`www`) en el que se puede indicar si php-fpm escucha por un socket unix, o por un socket TCP (puerto):

  - `listen = /run/php/php8.4-fpm.sock`

  - `listen = 127.0.0.1:9000` (local) o `listen = 9000` (cualquier dirección)

- Será necesario habilitar dos módulos con el comando: `a2enmod proxy_fcgi setenvif`

- Dependiendo de que forma escuche php-fpm se tendrá que añadir una de las siguientes líneas al Virtual Host:

  - Si escucha por socket unix -> `ProxyPassMatch ^/(.*\.php)$ unix:/run/php/php8.4-fpm.sock|fcgi://127.0.0.1/var/www/html`

    > **Nota**: Habrá que cambiar el /var/www/html por el Document Root a usar, y la ruta php8.4 por la versión instalada.

  - Si escucha por socket TCP -> `ProxyPassMatch ^/(.*\.php)$ fcgi://127.0.0.1:9000/var/www/html/$1`

    > **Nota**: Habrá que cambiar también /var/www/html por el Document Root a usar, y :9000 por el puerto configurado en el fichero `/etc/php/8.4/fpm/pool.d/www`.

### Instalación de un servidor LEMP + PHP-FPM

```bash
sudo apt install nginx mariadb php-fpm php-mysql -y
```

- Algunas aplicaciones web usan el fichero de configuración `.htaccess` pero nginx no es capaz de leer este fichero, por lo que si se migra una aplicación web de apache2 a nginx es necesario convertir el fichero .htaccess a lo equivalente en nginx, que normalmente se hace en el Virtual Host.

- Algunas páginas que hacen eso son:

  - [Winginx](https://winginx.com/en/htaccess)

  - [GetPageSpeed](https://www.getpagespeed.com/apache-to-nginx)

- Para ejecutar nginx + php-fpm será necesario configurar el siguiente código que por defecto está comentado en el Virtual Host `default`:

```
location ~ \.php$ {
    include snippets/fastcgi-php.conf;

# Descomenta la siguiente línea si php-fpm escucha por un socket unix:
    #fastcgi_pass unix:/run/php/php8.4-fpm.sock;

# Descomenta la siguiente línea si php-fpm escucha por un socket TCP:
    #fastcgi_pass 127.0.0.1:9000;
}
```

- Para ver información del servidor se puede crear en el Document Root (/var/www/algo/) un fichero info.php con el siguiente contenido:

```php
<?php phpinfo(); ?>
```

### Explicación directorios PHP

- `/etc/php/8.4/cli/` -> Configuración de php para php-cli, es decir para cuando se usa desde linea de comando.
- `/etc/php/8.4/apache2/` -> Configuración de php para apache2 cuando utiliza `libapache2-mod-php`.
- `/etc/php/8.4/fpm/` -> Configuración de php para `php-fpm`.
- `/etc/php/8.4/mods-available/` -> Módulos disponibles de php que pueden estar configurados en cualquiera de los escenarios (cli, apache2, fpm).
- `/etc/php/8.4/\*/conf.d/` -> Módulos de php instalados, son enlaces simbólicos a `/etc/php/8.4/mods-available`.
- `/etc/php/8.4/\*/php.ini` -> Configuración de php.

## HTTPS

Para obtener un certificado SSL sin complicación lo mejor será usar el agente `certbot` en el servidor:

- [Paso a paso para usar certbot](https://certbot.eff.org/)

> **Nota**: Será necesario indicar el servidor web y la instalación de certbot (snap recomendado).

