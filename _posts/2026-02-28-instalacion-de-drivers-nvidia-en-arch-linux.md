---
title: Instalación de Drivers NVIDIA en Arch Linux
date: 2026-02-28 02:01:00 +0200
categories: [Linux, Controladores]
tags: [nvidia, drivers, arch-linux, linux, wayland, gpu, modulo-kernel]
---

Guía para instalar los drivers propietarios de NVIDIA en Arch Linux, explicando el porqué de cada paso y cómo verificar que todo funciona correctamente.

---

## ¿Por qué instalar los drivers propietarios?

Arch Linux, al igual que la mayoría de distribuciones, incluye por defecto **Nouveau**: el driver libre y de código abierto para tarjetas NVIDIA. Aunque funciona para uso básico, tiene limitaciones importantes:

- **Rendimiento muy inferior** al driver oficial, especialmente en cargas gráficas intensas.
- **Sin soporte para las últimas arquitecturas** (Ada Lovelace, Ampere...).
- **Problemas de estabilidad** en entornos de escritorio modernos como Wayland.

Los drivers propietarios de NVIDIA (`nvidia-open` o `nvidia`) ofrecen rendimiento completo, soporte para Vulkan, CUDA, y una integración mucho mejor con el escritorio.

---

## Paso 1: Identificar la tarjeta gráfica y el kernel

Antes de instalar nada, necesitamos saber qué GPU tenemos y qué kernel estamos usando, ya que el paquete a instalar depende de ambos factores.

```bash
# Ver la GPU
lspci -k | grep -A3 VGA

# Ver la versión del kernel
uname -r
```

El resultado de `uname -r` nos dirá el kernel exacto. Por ejemplo:

- `6.x.x-arch1-1` → Kernel estándar de Arch (`linux`)
- `6.x.x-zen1-1` → Kernel Zen (`linux-zen`)
- `6.x.x-lts1` → Kernel LTS (`linux-lts`)

Esto es importante porque el paquete que instalaremos varía según el kernel.

---

## Paso 2: Elegir el paquete correcto

NVIDIA ofrece dos variantes de driver en los repositorios oficiales de Arch:

| Paquete | Descripción | Cuándo usarlo |
|---|---|---|
| `nvidia-open` | Driver de código abierto oficial de NVIDIA (≠ Nouveau) | Kernel estándar `linux`, GPUs modernas (Turing en adelante) |
| `nvidia-open-dkms` | Igual pero se compila para cualquier kernel | Kernels alternativos (`linux-zen`, `linux-lts`, etc.) |
| `nvidia` | Driver propietario clásico (binario cerrado) | GPUs más antiguas |
| `nvidia-dkms` | Igual pero para kernels alternativos | Kernels alternativos + GPUs antiguas |

> **Nota:** `nvidia-open` es el driver de código abierto **oficial de NVIDIA**, distinto de Nouveau. NVIDIA lo publicó a partir de la serie Turing (RTX 20xx en adelante) y es el recomendado actualmente para GPUs modernas.

Para el caso más común (kernel estándar + GPU moderna como una RTX 30xx/40xx):

```bash
pacman -S nvidia-open nvidia-utils
```

Si usas un kernel alternativo:

```bash
pacman -S nvidia-open-dkms nvidia-utils
```

---

## Paso 3: Añadir los módulos al initramfs

El initramfs es la imagen que el kernel carga al arrancar antes de montar el sistema de archivos raíz. Para que los drivers de NVIDIA estén disponibles desde el inicio del arranque (necesario para Wayland y para evitar el parpadeo de pantalla), hay que incluirlos explícitamente.

Edita `/etc/mkinitcpio.conf`:

```bash
nano /etc/mkinitcpio.conf
```

Busca la línea `MODULES=()` y añade los módulos de NVIDIA:

```
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
```

¿Qué hace cada módulo?

- `nvidia` → El driver principal.
- `nvidia_modeset` → Necesario para la gestión de modos de pantalla (KMS).
- `nvidia_uvm` → Permite la gestión unificada de memoria (útil para CUDA).
- `nvidia_drm` → Integración con el subsistema DRM del kernel, imprescindible para Wayland.

Regenera el initramfs para que los cambios surtan efecto:

```bash
mkinitcpio -P
```

---

## Paso 4: Habilitar el modo KMS de NVIDIA en el kernel

KMS (Kernel Mode Setting) permite que el kernel gestione la resolución y el modo de pantalla directamente, en lugar de delegarlo al espacio de usuario. Es necesario para que Wayland funcione correctamente con NVIDIA.

Edita `/etc/default/grub` y añade el parámetro al final de `GRUB_CMDLINE_LINUX_DEFAULT`:

```
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia_drm.modeset=1"
```

Regenera la configuración de GRUB:

```bash
grub-mkconfig -o /boot/grub/grub.cfg
```

---

## Paso 5: Reiniciar y verificar

Reinicia el sistema:

```bash
reboot
```

Una vez dentro, verifica que el driver correcto está en uso:

```bash
lspci -k | grep -A3 VGA
```

Debes ver `Kernel driver in use: nvidia` y **no** `nouveau`.

Para una verificación más completa, usa `nvidia-smi`:

```bash
nvidia-smi
```

Si muestra la información de la tarjeta (temperatura, memoria, procesos), los drivers están funcionando correctamente.

---

## Notas adicionales

### Wayland vs X11

Con los drivers propietarios de NVIDIA y `nvidia_drm.modeset=1` activado, Wayland debería funcionar sin problemas en entornos como KDE Plasma o GNOME. Si experimentas problemas, puedes cambiar a X11 desde el selector del gestor de pantalla (SDDM, GDM...).

### Actualizaciones del kernel

Cada vez que el kernel se actualiza, el módulo de NVIDIA debe recompilarse. Si usaste `nvidia-open` o `nvidia` (sin `-dkms`), pacman lo gestiona automáticamente. Si usaste la variante `-dkms`, el sistema lo compila automáticamente en la actualización gracias a DKMS.

### ¿Y si tengo una GPU AMD o Intel?

No necesitas hacer nada de esto. Los drivers de AMD e Intel están integrados en el kernel y funcionan perfectamente con `mesa` sin configuración adicional.

---

## Referencias

- [NVIDIA — ArchWiki](https://wiki.archlinux.org/title/NVIDIA)
- [Kernel mode setting — ArchWiki](https://wiki.archlinux.org/title/Kernel_mode_setting)
- [mkinitcpio — ArchWiki](https://wiki.archlinux.org/title/Mkinitcpio)
- [GRUB — ArchWiki](https://wiki.archlinux.org/title/GRUB)
