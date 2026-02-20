---
title: Configuración acceso remoto Oracle Database Enterprise Edition 21c (Debian 13)
date: 2025-10-08 21:58:00 +0200
categories: [Linux, Configuración]
tags: [oracle, database, linux]
image:
  path: /assets/img/capturas/configuracion-acceso-remoto-oracle-database-enterprise-edition-21c-debian-13/portada.png
  alt: "Configuración acceso remoto Oracle Database Enterprise Edition 21c (Debian 13)"
---

Aquí voy a explicar como configurar el servidor para que acepte conexiones remotas y un cliente para que se puede conectar.

## Configuración del lado del servidor

Por defecto Oracle solamente escucha al localhost por lo que tendremos que modificar el archivo **listener.ora** para conseguir que escuche todas las peticiones.

```bash
sudo nano /opt/oracle/homes/OraDBHome21cEE/network/admin/listener.ora
```

![listener.ora](/assets/img/capturas/configuracion-acceso-remoto-oracle-database-enterprise-edition-21c-debian-13/listener.ora.png)

Como se ve en la captura se debe cambiar lo que está después de HOST por 0.0.0.0, esto indica cualquier dirección.

También es recomendable modificar el archivo **tnsnames.ora** ya que este controla cómo el cliente se conecta al servidor.

```bash
sudo nano /opt/oracle/homes/OraDBHome21cEE/network/admin/tnsnames.ora
```

![tnsnames.ora](/assets/img/capturas/configuracion-acceso-remoto-oracle-database-enterprise-edition-21c-debian-13/tnsnames.ora.png)

Como se ve en la captura se debe de cambiar lo mismo que en el archivo listener.ora.

Para aplicar los cambios hay más de una forma pero yo lo que haré será reiniciar el servidor.

## Configuración del lado del cliente

Ahora voy a explicar como instalar y configurar el cliente, lo primero será instalar los siguientes paquetes:

```bash
sudo apt install libaio1t64 libaio-dev rlwrap wget p7zip-full -y
```

Con el paquete libaio1t64 pasa lo mismo que para instalar el servidor Oracle, hay que crear el link para que Debian 13 lo encuentre:

```bash
sudo ln -s /usr/lib/x86_64-linux-gnu/libaio.so.1t64 /usr/lib/x86_64-linux-gnu/libaio.so.1
```

A continuación pasaré con la instalación del cliente, para ello será necesario _basic_ y _sqlplus_:

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
