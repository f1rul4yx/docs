---
title: Instalación de Snort3 (Debian 11)
date: 2025-10-15 19:48:00 +0200
categories: [Linux, Instalación]
tags: [snort3, linux]
---

## Descarga de paquetes

Lo primero será descargar los ficheros source de la [web oficial](https://www.snort.org/downloads#snort3-downloads) de Snort como se ve en la siguiente captura:

![web-snort](/assets/img/capturas/instalacion-de-snort3-debian-11/web-snort.png)

## Instalar dependencias del sistema

```bash
sudo apt update
sudo apt install build-essential cmake libpcap-dev libpcre3-dev libdumbnet-dev bison flex zlib1g-dev libluajit-5.1-dev libssl-dev pkg-config autoconf automake libtool libhwloc-dev libpcre2-dev xz-utils liblzma-dev uuid-dev libunwind-dev libnuma-dev -y
```

> Esto asegura que tengas todo lo necesario para compilar libdaq, libml y Snort.

## Compilar e instalar libdaq

```bash
cd snort3-libdaq-22dab0c
./bootstrap           # Genera el configure script
./configure
make
sudo make install
cd ..
```

> Esto instala libdaq en /usr/local/lib. Para que el sistema encuentre la librería: sudo ldconfig

## Compilar e instalar libml

```bash
cd snort3-libml-0e9247c
./configure.sh
cd build
cmake ..
make
sudo make install
cd ../..
```

> Ejecutar sudo ldconfig nuevamente si el sistema no encuentra la librería.

## Compilar e instalar Snort 3

```bash
cd snort3-snort3-92185d9
./configure_cmake.sh --prefix=/usr/local/snort
cd build
make
sudo make install
cd ../..
```

- Verifica la instalación:

```bash
/usr/local/snort/bin/snort --version
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
cd snort3-snort3_extra-114241b
./configure_cmake.sh --prefix=/usr/local/snort
cd build
make
sudo make install
cd ../..
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
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
```
