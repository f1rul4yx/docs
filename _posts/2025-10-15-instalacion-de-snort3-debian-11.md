---
title: Instalación de Snort3 (Debian 11)
date: 2025-10-15 19:48:00 +0200
categories: [Linux, Instalación]
tags: [snort3, linux]
---

## Descarga de paquetes

Lo primero será descargar los ficheros source de la [web oficial](https://www.snort.org/downloads#snort3-downloads) de Snort como se ve en la siguiente captura:

![web-snort](/assets/img/capturas/instalacion-de-snort3-debian-11/web-snort.png)

> Esta es una manera de descargar los componentes para la instalación de Snort3 pero yo voy a clonar los repositorios oficiales, por lo que el paso anterior me lo voy a saltar.

## Instalar dependencias del sistema

```bash
sudo apt update
sudo apt install build-essential cmake libpcap-dev libpcre3-dev libdumbnet-dev bison flex zlib1g-dev libluajit-5.1-dev libssl-dev pkg-config autoconf automake libtool libhwloc-dev libpcre2-dev xz-utils liblzma-dev uuid-dev libunwind-dev libnuma-dev -y
```

> Esto asegura que tengas todo lo necesario para compilar libdaq, libml, Snort y Snort Extra.

## Compilar e instalar libdaq

```bash
git clone https://github.com/snort3/libdaq.git
cd libdaq/
./bootstrap
./configure
make
sudo make install
cd ../
```

> Esto instala libdaq en /usr/local/lib. Para que el sistema encuentre la librería: sudo ldconfig

## Compilar e instalar libml

```bash
git clone https://github.com/snort3/libml.git
cd libml/
./configure.sh
cd build/
cmake ..
make
sudo make install
cd ../../
```

> Ejecutar sudo ldconfig nuevamente si el sistema no encuentra la librería.

## Compilar e instalar Snort 3

```bash
git clone https://github.com/snort3/snort3.git
cd snort3/
./configure_cmake.sh --prefix=/usr/local/snort
cd build/
make
sudo make install
cd ../../
```

- Añade la ruta a la variable PATH para que el sistema encuentre el binario:

```bash
echo 'export PATH=$PATH:/usr/local/snort/bin' >> ~/.bashrc
source ~/.bashrc
```

> Para poder usar el binario con el usuario root será necesario añadir el PATH también en el .bashrc del usuario root.

- Verifica la instalación:

```bash
snort --version
```

## Instalar Snort3 Extra (reglas y scripts)

- Añade la ruta de snort.pc a PKG_CONFIG_PATH:

```bash
echo 'export PKG_CONFIG_PATH=/usr/local/snort/lib/pkgconfig:$PKG_CONFIG_PATH' >> ~/.bashrc
source ~/.bashrc
```

- Verifica que pkg-config lo encuentre:

```bash
pkg-config --modversion snort
```

```bash
git clone https://github.com/snort3/snort3_extra.git
cd snort3_extra/
./configure_cmake.sh --prefix=/usr/local/snort
cd build/
make
sudo make install
cd ../../
```

> Esto integrará las reglas y scripts extra a tu instalación de Snort.

## Configuración inicial

- Copia el archivo de configuración de ejemplo:

```bash
cp /usr/local/snort/etc/snort/snort.lua /usr/local/snort/etc/snort/snort.lua.backup
```

- Edita snort.lua según tu red y necesidades:

```bash
nano /usr/local/snort/etc/snort/snort.lua
```

- Asegúrate de que las librerías estén en la ruta:

```bash
echo 'export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc
```
