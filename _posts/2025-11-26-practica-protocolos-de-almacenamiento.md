---
title: Práctica - Protocolos de almacenamiento
date: 2025-11-26 18:14:00 +0200
categories: [Linux, Practica, SRI]
tags: [nas, san, linux]
---

# Añadir nueva red a las máquinas

## En el host

- `/etc/network/interfaces` -> Para crear el tercer puente

- `/var/lib/lxc/sri-c6-servidorweb/config` -> Para añadir la segunda interfaz

- `/var/lib/lxc/sri-c6-backend1/config` -> Para añadir la segunda interfaz

- `/var/lib/lxc/sri-c6-backend2/config` -> Para añadir la segunda interfaz

- `/var/lib/lxc/sri-c6-servidorweb/rootfs/etc/systemd/network/eth1.network` -> Para configurar la segunda interfaz

- `/var/lib/lxc/sri-c6-backend1/rootfs/etc/systemd/network/eth1.network` -> Para configurar la segunda interfaz

- `/var/lib/lxc/sri-c6-backend2/rootfs/etc/systemd/network/eth1.network` -> Para configurar la segunda interfaz

## En el nas-san

- `/etc/network/interfaces` -> Para configurar la segunda interfaz

# Preparación discos en Servidor NAS/SAN

```bash
sudo mdadm --create /dev/md/md5 --level 5 --raid-devices 3 /dev/vdb /dev/vdc /dev/vdd
sudo pvcreate /dev/md/md5
sudo vgcreate vg1 /dev/md/md5
sudo lvcreate -L 512M -n lv_lun1 vg1
sudo lvcreate -L 512M -n lv_lun2 vg1
sudo lvcreate -L 1G -n lv_nfs vg1
```

> El equipo LXC servidorweb ha sido cambiado por una máquina virtual completa en QEMU/KVM, ya que los clientes iSCSI también necesitan tener kernel.

# SAN

## Servidor (target)

- Instalación del servicio tgtd:

```bash
sudo apt install tgt -y
```

- Crear target:

```bash
sudo tgtadm --lld iscsi --op new --mode target --tid 1 -T iqn.2025-11.org.diego:target1
```

- Asociar dispositivo como LUN:

```bash
sudo tgtadm --lld iscsi --op new --mode logicalunit --tid 1 --lun 1 -b /dev/vg1/lv_lun1
sudo tgtadm --lld iscsi --op new --mode logicalunit --tid 1 --lun 2 -b /dev/vg1/lv_lun2
```

- Permitir acceso al target desde enp7s0:

```bash
sudo tgtadm --lld iscsi --op bind --mode target --tid 1 -I enp7s0
```

- Para verificar la configuración:

```bash
sudo tgtadm --lld iscsi --op show --mode target
```

- Para hacerlo persistente:

```bash
sudo tgt-admin --dump > /etc/tgt/conf.d/diego.org.conf
```

- También se puede crear directamente el fichero `/etc/tgt/conf.d/diego.org.conf`:

```
default-driver iscsi

<target iqn.2025-11.org.diego:target1>
    backing-store /dev/vg1/lv_lun1
    backing-store /dev/vg1/lv_lun2
    initiator-name enp7s0
    incominguser usuario clave12345
    outgoinguser usuario clave12345
</target>
```

## Cliente (initiator)

- Instalación del servicio cliente:

```bash
sudo apt install open-iscsi -y
```

- Lo primero que haré será descubrir los targets que ofrece el servidor (10.0.6.1):

```bash
sudo iscsiadm --mode discovery --type sendtargets --portal 10.0.6.1
```

> Nota: Al usar un contenedor lxc no se puede realizar esta parte, ya que ISCSI necesita que el equipo tenga kernel.

- Después de haber cambiado el servidorweb lxc por una máquina virtual completa de QEMU/KVM ya podré usar el target:

```bash
# Configuración usuario CHAP
sudo iscsiadm \
--mode node \
-T iqn.2025-11.org.diego:target1 \
--portal 10.0.6.1 \
-o update \
-n node.session.auth.username \
-v usuario
```

```bash
# Configuración contraseña CHAP
sudo iscsiadm \
--mode node \
-T iqn.2025-11.org.diego:target1 \
--portal 10.0.6.1 \
-o update \
-n node.session.auth.password \
-v clave12345
```

```bash
# Conexión
sudo iscsiadm --mode node -T iqn.2025-11.org.diego:target1 --portal 10.0.6.1 --login
```

- Para que la conexión sea persistente ejecutare el siguiente comando:

```bash
sudo iscsiadm -m node -T iqn.2025-11.org.diego:target1 -p 10.0.6.1 --op update -n node.startup -v automatic
```

- Para ver las conexiones se puede usar el comando:

```bash
sudo iscsiadm -m session
```

- A continuación voy a ejecutar los comandos necesarios para usar una de las unidades lógicas:

```bash
sudo mkfs.ext4 /dev/sda
sudo mkdir /mnt/lun1
sudo nano /etc/systemd/system/mnt-lun1.mount
```

```
[Unit]
Description=Montaje SAN iSCSI (lun1)
After=network-online.target iscsi.service
Requires=network-online.target iscsi.service

[Mount]
What=/dev/sda
Where=/mnt/lun1
Type=ext4
Options=_netdev

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable mnt-lun1.mount
```

# NFS

## Servidor

- Ahora voy a formatear el volúmen anteriormente creado:

```bash
sudo mkfs.ext4 /dev/vg1/lv_nfs
```

- A continuación instalaré el paquete necesario para usar NFS:

```bash
sudo apt install nfs-kernel-server -y
sudo mkdir /srv/lv_nfs
sudo nano /etc/exports
```

- En el fichero introduciré lo siguiente:

```
/srv/lv_nfs     10.0.6.0/24(rw,sync,no_subtree_check)
```

- Para aplicar los cambios y comprobarlos usaré los siguientes comandos respectivamente:

```bash
sudo exportfs -ra
sudo exportfs -v
```

- Ahora para guardar todo en el volumen lo montaré y crearé una unidad de montaje con systemd:

```bash
sudo mount /dev/vg1/lv_nfs /srv/lv_nfs/
sudo nano /etc/systemd/system/srv-lv_nfs.mount
```

- En el fichero introduzco el siguiente contenido:

```
[Unit]
Description=NFS (backends1 y 2)
After=network-online.target
Requires=network-online.target

[Mount]
What=/dev/vg1/lv_nfs
Where=/srv/lv_nfs
Type=ext4
Options=defaults,_netdev

[Install]
WantedBy=multi-user.target
```

- Casi acabando cargo el punto de montaje para que el sistema lo reconozca y pueda usarlo:

```bash
sudo systemctl daemon-reload
sudo systemctl enable srv-lv_nfs.mount
```

- En el punto de montaje creo un `index.html`:

```bash
echo "<h1>Página desde NFS</h1>" | sudo tee /srv/lv_nfs/index.html
```

## Clientes

- Instalaré el paquete necesario:

```bash
sudo apt install nfs-common -y
```

- Configuro la carpeta y el Virtual Host:

```bash
sudo mkdir /mnt/nfs
sudo mount 10.0.6.1:/srv/lv_nfs /mnt/nfs
sudo vim /etc/apache2/sites-available/000-default.conf
```

- Añado el alias:

```
<VirtualHost *:80>
    ServerName backend1.diego.org
    DocumentRoot /var/www/html

    Alias /nfs /mnt/nfs
    <Directory /mnt/nfs>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
```

- Reinicio el servicio:

```bash
sudo systemctl restart apache2.service
```

- Hago persistente el montaje con una unidad mount de systemd:

```bash
sudo vim /etc/systemd/system/mnt-nfs.mount
```

- Introduzco lo siguiente:

```
[Unit]
Description=Montaje NFS
After=network-online.target
Requires=network-online.target

[Mount]
What=10.0.6.1:/srv/lv_nfs
Where=/mnt/nfs
Type=nfs
Options=defaults,_netdev

[Install]
WantedBy=multi-user.target
```

- Habilito la unidad para que la pueda usar systemd:

```bash
sudo systemctl daemon-reload
sudo systemctl enable mnt-nfs.mount
```

- Hago lo mismo para el backend2.
