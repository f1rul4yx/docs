---
title: Guía de Instalación de Arch Linux
date: 2026-02-27 14:59:00 +0200
categories: [Linux, Arch Linux]
tags: [arch-linux, linux, instalacion, lvm, grub, uefi, aur]
---

Guía completa para instalar Arch Linux desde cero siguiendo la documentación oficial, con soporte para particionado estándar y LVM.

---

## ¿Qué es Arch Linux?

**Arch Linux** es una distribución GNU/Linux de propósito general con modelo *rolling-release*, diseñada para usuarios que quieren control total sobre su sistema. A diferencia de otras distribuciones, no incluye instalador gráfico: todo se configura desde la terminal, lo que permite entender cada componente del sistema.

**Principios fundamentales:**

- **Simplicidad:** mínima configuración predeterminada
- **Modernidad:** software siempre en las últimas versiones estables
- **Pragmatismo:** decisiones basadas en mérito técnico
- **Centrado en el usuario:** orientado a usuarios con conocimientos de Linux

---

## Paso 1: Configuración inicial del entorno live

### Distribución de teclado

```bash
# Cargar distribución española
loadkeys es
```

### Verificar modo de arranque

```bash
# Si devuelve 64, estás en modo UEFI de 64 bits
cat /sys/firmware/efi/fw_platform_size
```

> Si el archivo no existe, el sistema arrancó en modo BIOS/Legacy.

### Conexión a Internet

**Ethernet:** se configura automáticamente. Verifica con:

```bash
ping -c 3 one.one.one.one
```

**Wi-Fi con iwctl:**

```bash
iwctl
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect NOMBRE_RED
exit
```

### Sincronizar el reloj

```bash
timedatectl set-ntp true
```

---

## Paso 2: Particionado del disco

> **Advertencia:** Un error en esta fase puede borrar datos. Haz copia de seguridad antes de continuar.

### Identificar los discos

```bash
lsblk
fdisk -l
```

Los discos suelen llamarse `/dev/sda` (SATA), `/dev/nvme0n1` (NVMe) o `/dev/vda` (virtual).

---

### Opción A — Particionado estándar (sin LVM)

Este es el método que sigue directamente la guía oficial de Arch Linux. Es el más sencillo y recomendado para la mayoría de casos.

**Esquema para UEFI (GPT):**

| Partición | Punto de montaje | Tamaño | Tipo |
| --- | --- | --- | --- |
| `/dev/sda1` | `/boot` | 512 MiB – 1 GiB | EFI System |
| `/dev/sda2` | `[SWAP]` | 1–2x RAM | Linux swap |
| `/dev/sda3` | `/` | Resto del disco | Linux root (x86-64) |

**Particionar con cfdisk:**

```bash
cfdisk /dev/sda
```

Selecciona `gpt` (UEFI) o `dos` (BIOS), crea las particiones y selecciona `Write` para guardar.

**Formatear:**

```bash
# Partición EFI
mkfs.fat -F32 /dev/sda1

# Swap
mkswap /dev/sda2

# Raíz
mkfs.ext4 /dev/sda3
```

**Montar:**

```bash
mount /dev/sda3 /mnt
mount --mkdir /dev/sda1 /mnt/boot
swapon /dev/sda2
```

---

### Opción B — Particionado con LVM

LVM (Logical Volume Manager) permite gestionar el espacio en disco de forma más flexible: redimensionar volúmenes, crear snapshots y agregar discos fácilmente. Requiere pasos adicionales respecto al particionado estándar.

> **Nota:** LVM es una opción avanzada documentada en [wiki.archlinux.org/title/LVM](https://wiki.archlinux.org/title/LVM). No forma parte del flujo básico de la Installation Guide oficial.

**Esquema recomendado con LVM (UEFI):**

| Partición | Uso | Tipo |
| --- | --- | --- |
| `/dev/sda1` | `/boot` (EFI) — **fuera de LVM** | EFI System |
| `/dev/sda2` | Physical Volume de LVM | Linux LVM |

Dentro del Volume Group, los Logical Volumes:

| Logical Volume | Punto de montaje | Tamaño sugerido |
| --- | --- | --- |
| `vg0-swap` | `[SWAP]` | 1–2x RAM |
| `vg0-root` | `/` | Resto del espacio |

**Crear la partición EFI y el Physical Volume con cfdisk:**

```bash
cfdisk /dev/sda
# Crea sda1 como EFI System (512 MiB - 1 GiB)
# Crea sda2 como Linux LVM (resto del disco)
```

**Configurar LVM:**

```bash
# Crear el Physical Volume
pvcreate /dev/sda2

# Crear el Volume Group
vgcreate vg0 /dev/sda2

# Crear los Logical Volumes
lvcreate -L 4G vg0 -n swap
lvcreate -l 100%FREE vg0 -n root
```

**Formatear:**

```bash
# Partición EFI
mkfs.fat -F32 /dev/sda1

# Swap
mkswap /dev/mapper/vg0-swap

# Raíz
mkfs.ext4 /dev/mapper/vg0-root
```

**Montar:**

```bash
mount /dev/mapper/vg0-root /mnt
mount --mkdir /dev/sda1 /mnt/boot
swapon /dev/mapper/vg0-swap
```

---

## Paso 3: Instalación del sistema base

### Configurar mirrors (recomendado)

```bash
pacman -Sy reflector
reflector --protocol http --country Spain,France,Germany --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
```

### Instalar paquetes base

```bash
pacstrap -K /mnt base linux linux-firmware base-devel linux-headers \
          networkmanager sudo vim nano man-db man-pages
```

> **Si usas LVM**, añade también el paquete `lvm2`:
>
> ```bash
> pacstrap -K /mnt base linux linux-firmware base-devel linux-headers \
>           networkmanager sudo vim nano man-db man-pages lvm2
> ```

### Generar fstab

```bash
genfstab -U /mnt >> /mnt/etc/fstab

# Verifica el resultado
cat /mnt/etc/fstab
```

---

## Paso 4: Configuración del sistema (chroot)

```bash
arch-chroot /mnt
```

### Zona horaria

```bash
ln -sf /usr/share/zoneinfo/Europe/Madrid /etc/localtime
hwclock --systohc
```

### Idioma y localización

```bash
# Editar /etc/locale.gen y descomentar:
# es_ES.UTF-8 UTF-8
# en_US.UTF-8 UTF-8
nano /etc/locale.gen

locale-gen

echo 'LANG=es_ES.UTF-8' > /etc/locale.conf
```

### Distribución de teclado persistente

```bash
echo 'KEYMAP=es' > /etc/vconsole.conf
```

### Hostname

```bash
echo 'mi-arch' > /etc/hostname
```

### Archivo hosts

```bash
nano /etc/hosts
```

Añade:

```
127.0.0.1    localhost
::1          localhost
127.0.1.1    mi-arch.localdomain  mi-arch
```

### Contraseña de root

```bash
passwd
```

### Crear usuario normal

```bash
useradd -m -G wheel,audio,video,optical,storage diego
passwd diego

# Habilitar sudo para el grupo wheel
EDITOR=nano visudo
# Descomenta: %wheel ALL=(ALL:ALL) ALL
```

---

## Paso 5: Configurar el initramfs

### Sin LVM

Si hiciste el particionado estándar (Opción A), **no necesitas modificar nada**. El `mkinitcpio.conf` funciona con los hooks por defecto.

Simplemente ejecuta:

```bash
mkinitcpio -P
```

### Con LVM

Si usaste LVM (Opción B), necesitas añadir el hook `lvm2` en `/etc/mkinitcpio.conf`.

Primero asegúrate de que `lvm2` está instalado:

```bash
pacman -S lvm2
```

Edita el archivo:

```bash
nano /etc/mkinitcpio.conf
```

Localiza la línea `HOOKS` y añade `lvm2` entre `block` y `filesystems`:

```
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)
```

Regenera el initramfs:

```bash
mkinitcpio -P
```

> **Importante:** La salida no debe mostrar ningún `ERROR`. Si aparece `binary not found: 'pdata_tools'` o `can't read /etc/lvm/lvm.conf`, significa que el paquete `lvm2` no está instalado correctamente.

---

## Paso 6: Gestor de arranque (GRUB)

### Microcódigo del procesador

```bash
# Intel
pacman -S intel-ucode

# AMD
pacman -S amd-ucode
```

### Instalar GRUB en UEFI

```bash
pacman -S grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
```

### Instalar GRUB en BIOS/Legacy

```bash
pacman -S grub
grub-install --target=i386-pc /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg
```

> **Nota:** `grub-mkconfig` detecta automáticamente el microcódigo instalado y lo incluye en la configuración.

---

## Paso 7: Red y servicios esenciales

```bash
systemctl enable NetworkManager
```

---

## Paso 8: Finalizar la instalación

```bash
# Salir del chroot
exit

# Desmontar todas las particiones
umount -R /mnt

# Reiniciar
reboot
```

> **Recuerda:** Retira el USB antes de que el sistema arranque desde el disco.

---

## Post-instalación

### Entorno de escritorio

Arch no incluye entorno gráfico por defecto. Estos son los más populares:

| Escritorio | Tipo | Instalación |
| --- | --- | --- |
| KDE Plasma | Completo | `pacman -S plasma sddm` |
| GNOME | Completo | `pacman -S gnome gdm` |
| XFCE | Ligero | `pacman -S xfce4 lightdm` |
| Hyprland | Wayland / Tiling | `pacman -S hyprland` |
| i3 | X11 / Tiling | `pacman -S i3` |

Habilita el gestor de pantalla correspondiente:

```bash
# Ejemplo con SDDM (KDE)
systemctl enable sddm

# Ejemplo con GDM (GNOME)
systemctl enable gdm
```

### Herramientas recomendadas

```bash
# Red y utilidades
pacman -S net-tools wget curl openssh htop git zip unzip

# Fuentes de texto
pacman -S ttf-dejavu ttf-liberation noto-fonts
```

### AUR con yay

El AUR (Arch User Repository) contiene miles de paquetes adicionales mantenidos por la comunidad:

```bash
pacman -S git base-devel
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```

### Actualizaciones

```bash
# Solo repositorios oficiales
pacman -Syu

# Incluye AUR
yay -Syu
```

> **Arch Linux es rolling-release.** Se recomienda actualizar regularmente y revisar las noticias en [archlinux.org/news](https://archlinux.org/news/) antes de actualizaciones importantes.

---

## Opción rápida: archinstall

Si prefieres una instalación guiada, el live system incluye `archinstall`:

```bash
archinstall
```

Te guiará mediante menús interactivos para configurar disco, idioma, usuario, escritorio y más. Es una buena opción para familiarizarse antes de hacer la instalación manual.

> **Nota:** Los perfiles de `archinstall` son específicos del instalador y no están soportados por los mantenedores de paquetes oficiales.

---

## Referencias

- [Installation Guide oficial — ArchWiki](https://wiki.archlinux.org/title/Installation_guide)
- [LVM — ArchWiki](https://wiki.archlinux.org/title/LVM)
- [General recommendations — ArchWiki](https://wiki.archlinux.org/title/General_recommendations)
- [mkinitcpio — ArchWiki](https://wiki.archlinux.org/title/Mkinitcpio)
- [GRUB — ArchWiki](https://wiki.archlinux.org/title/GRUB)
- [AUR — ArchWiki](https://wiki.archlinux.org/title/Arch_User_Repository)
