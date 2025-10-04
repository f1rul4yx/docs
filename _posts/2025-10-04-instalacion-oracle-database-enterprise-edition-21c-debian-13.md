---
title: Instalación Oracle Database Enterprise Edition 21c (Debian 13)
date: 2025-10-04 19:12:00 +0200
categories: [Linux, Instalación]
tags: [oracle, database, linux]
---

## Instalación de dependencias

Lo primero será instalar los paquetes necesarios para poder instalar y usar el software.

```bash
sudo apt update
sudo apt install libaio1t64 libaio-dev unixodbc rlwrap wget -y
```

> Antes para instalar Oracle Database en Debian 12 se necesitaba el paquete libaio1 pero en Debian 13 ese paquete ha cambiado de nombre (libaio1t64).
> Como Oracle Database busca el fichero `/usr/lib/x86_64-linux-gnu/libaio.so.1` pero ese fichero en Debian 13 ahora se llama `/usr/lib/x86_64-linux-gnu/libaio.so.1t64` vamos a crear un enlace simbólico del archivo actual que se llame como el antiguo para que Oracle Database lo encuentre.

```bash
sudo ln -s /usr/lib/x86_64-linux-gnu/libaio.so.1t64 /usr/lib/x86_64-linux-gnu/libaio.so.1
```

## Descarga del archivo .deb e instalación

Ahora realizaré la descarga del archivo .deb y la instalación del mismo.

```bash
wget https://files.diegovargas.es/deb/oracle-database-ee-21c_1.0-2_amd64.deb
sudo dpkg -i oracle-database-ee-21c_1.0-2_amd64.deb
sudo rm -r oracle-database-ee-21c_1.0-2_amd64.deb
```

> Oracle Database no proporciona archivo .deb pero si un archivo .rpm por lo que con ayuda del paquete alien he convertido el archivo .rpm a .deb.

## Configuraciones necesarias

Ya para casi finalizar la instalación del software proporcionaré unos comandos para configurar Oracle Database.

```bash
echo "$(hostname -I | awk '{print $1}') $(hostname)" | sudo tee -a /etc/hosts
sudo /etc/init.d/oracledb_ORCLCDB-21c configure
sudo usermod -aG dba $USER
```

> El primer comando es útil, ya que Orale Database necesita resolver el nombre del host con una IP válida. Si no se configurara, la instalación fallaría y habría problemas al arrancar el listener.
> Ahora como última configuración necesaria será asignar los alias para poder usar Oracle Database.

```bash
echo 'export ORACLE_HOME=/opt/oracle/product/21c/dbhome_1' >> ~/.bashrc
echo 'export ORACLE_SID=ORCLCDB' >> ~/.bashrc
echo 'export NLS_LANG=SPANISH_SPAIN.AL32UTF8' >> ~/.bashrc
echo 'export ORACLE_BASE=/opt/oracle' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH' >> ~/.bashrc
echo 'export PATH=$ORACLE_HOME/bin:$PATH' >> ~/.bashrc
echo "alias sqlplus='rlwrap sqlplus'" >> ~/.bashrc
source ~/.bashrc
```

> Estos alias se guardan en ~/.bashrc para hacerlos persistentes pero si usas otra shell como por ejemplo zsh en vez de redireccionarlos a (>> ~/.bashrc) deberás de redireccionarlo a >> ~/.zshrc

## Configuraciones recomendadas

Ahora indicaré como usar Oracle Database y alguna configuración útil.

### Acceso a Oracle como administrador

```bash
sqlplus / as sysdba
```

### Configuración inicial para permitir la creación de usuarios en Oracle

```sql
STARTUP;
ALTER SESSION SET "_ORACLE_SCRIPT"=true;
```

### Pasos para crear un usuario y asignar permisos

- Crear usuario:

```sql
CREATE USER <<user>> IDENTIFIED BY <<password>>;
```

- Permisos de todo:

```sql
GRANT ALL PRIVILEGES TO <<user>>;
```

### Pasos para iniciar el servicio automáticamente

```bash
sudo crontab -e
```

- Añadir la línea ---> `@reboot sudo systemctl restart oracledb_ORCLCDB-21c.service`

### Ejecución de configuración automática

Hay algunas configuraciones que se deben de hacer cada vez que se inicia sesión por lo que una solución para evitar eso es crear un archivo `~/.login.sql` con una configuración como la siguiente:

```sql
-- Habilita la salida de mensajes desde procedimientos PL/SQL utilizando DBMS_OUTPUT.PUT_LINE
SET SERVEROUTPUT ON
-- Establece el ancho de línea para la salida en pantalla, útil para evitar que se divida la información en varias líneas
SET LINESIZE 150
-- Establece el número de líneas por página en la salida, para controlar la paginación al mostrar muchos registros
SET PAGESIZE 100
```

> Para conseguir ejecutar este fichero es necesario indicarlo al iniciar la sesión `sqlplus <<usuario>>/<<contraseña>> @<<ruta_absoluta_.login.sql>>`

## Configuración para conexión remota

Ahora voy a explicar como configurar el servidor para que acepte conexiones remotas y un cliente para que se puede conectar.

### Configuración del lado del servidor

Por defecto oracle solamente escucha al localhost por lo que tendremos que modificar el archivo **listener.ora** para conseguir que escuche todas las peticiones.

```bash
sudo nano /opt/oracle/homes/OraDBHome21cEE/network/admin/listener.ora
```

![listener.ora](/assets/img/capturas/instalacion-oracle-database-enterprise-edition-21c-debian-13/listener.ora.png)

Como se ve en la captura se debe cambiar lo que está despues de HOST por 0.0.0.0, esto indica cualquier dirección.
También es recomendable modificar el archivo **tnsnames.ora** ya que este controla cómo el cliente se conecta al servidor.

```bash
sudo nano /opt/oracle/homes/OraDBHome21cEE/network/admin/tnsnames.ora
```

![tnsnames.ora](/assets/img/capturas/instalacion-oracle-database-enterprise-edition-21c-debian-13/tnsnames.ora.png)

Como se ve en la captura se debe de cambiar lo mismo que en el archivo listener.ora.
Para aplicar los cambios hay más de una forma pero yo lo que haré será reiniciar el servidor.

### Configuración del lado del cliente

Ahora voy a explicar como instalar y configurar el cliente, lo primero será instalar los siguientes paquetes:

```bash
sudo apt install libaio1t64 libaio-dev rlwrap wget p7zip-full -y
```

Con el paquete libaio1t64 pasa lo mismo que para instalar el servidor oracle, hay que crear el link para que Debian 13 lo encuentre:

```bash
sudo ln -s /usr/lib/x86_64-linux-gnu/libaio.so.1t64 /usr/lib/x86_64-linux-gnu/libaio.so.1
```

A continuación pasaré con la instalación del cliente para ello será necesario _basic_ y _sqlplus_:

```bash
mkdir ~/oracle
cd ~/oracle
wget https://download.oracle.com/otn_software/linux/instantclient/2119000/instantclient-basic-linux.x64-21.19.0.0.0dbru.zip
wget https://download.oracle.com/otn_software/linux/instantclient/2119000/instantclient-sqlplus-linux.x64-21.19.0.0.0dbru.zip
7z x instantclient-basic-linux.x64-21.19.0.0.0dbru.zip
7z x instantclient-sqlplus-linux.x64-21.19.0.0.0dbru.zip
rm -r instantclient-basic-linux.x64-21.19.0.0.0dbru.zip
rm -r instantclient-sqlplus-linux.x64-21.19.0.0.0dbru.zip
```

Por último para que el sistema pueda ejecutar los binarios será necesario crear las variables:

```bash
echo 'export ORACLE_HOME=$HOME/oracle/instantclient_21_19' >> ~/.bashrc
echo 'export PATH=$ORACLE_HOME:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=$ORACLE_HOME:$LD_LIBRARY_PATH' >> ~/.bashrc
echo "alias sqlplus='rlwrap sqlplus'" >> ~/.bashrc
source ~/.bashrc
```

Por último para poder conectarse remotamente será necesario ejecutar el siguiente comando:

```bash
sqlplus usuario/password@//IP_DEL_SERVIDOR:1521/ORCLCDB
```
