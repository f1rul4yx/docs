---
title: Compilación de un Kernel Linux
date: 2026-01-20 19:37:00 +0200
categories: [Linux, Customizer]
tags: [customizer, kernel, linux]
---

En este tutorial vamos a aprender a compilar un kernel Linux desde cero, firmarlo para que funcione con Secure Boot y configurar un arranque directo mediante EFI Stub, saltándonos GRUB completamente. Este proceso nos permite tener un control total sobre nuestro sistema operativo y entender cómo funciona el arranque de Linux a bajo nivel.

## ¿Por qué compilar tu propio kernel?

Compilar un kernel personalizado tiene varias ventajas:

- **Optimización**: Puedes eliminar módulos innecesarios y reducir el tamaño del kernel
- **Actualización**: Acceso a las últimas características y parches de seguridad
- **Aprendizaje**: Entender cómo funciona el núcleo de tu sistema operativo
- **Personalización**: Añadir o modificar funcionalidades específicas

## Instalación de dependencias

Lo primero que necesitamos es instalar todas las herramientas de desarrollo necesarias para compilar el kernel. Estas incluyen compiladores, herramientas de construcción y librerías de desarrollo:

```bash
sudo apt install build-essential libncurses-dev bison flex libdw-dev libssl-dev libelf-dev bc xz-utils fakeroot debhelper locales rsync sbsigntool -y
```

> **Explicación de algunos paquetes clave:**
> - `build-essential`: Contiene gcc, g++ y make, esenciales para compilar
> - `libssl-dev` y `libelf-dev`: Necesarios para firmar módulos y trabajar con binarios ELF
> - `sbsigntool`: Herramienta para firmar binarios con Secure Boot
> - `fakeroot` y `debhelper`: Permiten crear paquetes .deb del kernel compilado

## Creación del entorno de trabajo

Vamos a crear un directorio dedicado para la compilación del kernel. Es recomendable usar `/usr/src` ya que es la ubicación estándar para código fuente del sistema:

```bash
sudo mkdir /usr/src/kernel-compilation
cd /usr/src/kernel-compilation
```

Ahora descargamos el código fuente del kernel. En este caso usaremos la versión 6.19-rc6 (release candidate), pero puedes usar cualquier versión disponible en [kernel.org](https://kernel.org):

```bash
sudo wget https://git.kernel.org/torvalds/t/linux-6.19-rc6.tar.gz
sudo tar -xzf linux-6.19-rc6.tar.gz
cd linux-6.19-rc6
```

Un paso muy importante es copiar la configuración actual de nuestro kernel en funcionamiento. Esto nos permite mantener la compatibilidad con nuestro hardware:

```bash
sudo cp /boot/config-6.12.63+deb13-amd64 .config
```

> Esta configuración contiene todos los módulos y opciones que tu kernel actual está usando. Es un excelente punto de partida para evitar problemas de compatibilidad.

## Configuración y compilación del kernel

Ahora viene el proceso de configuración. Vamos a adaptar la configuración del kernel antiguo al nuevo:

```bash
sudo make olddefconfig
```

> `olddefconfig` toma tu configuración antigua y la adapta automáticamente a la nueva versión del kernel, usando valores por defecto para las nuevas opciones.

Para optimizar aún más el kernel, eliminamos los módulos que no están actualmente cargados en tu sistema:

```bash
sudo make localmodconfig
```

> Este comando analiza los módulos que tu sistema está usando actualmente (mediante `lsmod`) y desactiva todos los demás, reduciendo significativamente el tiempo de compilación y el tamaño del kernel.

Finalmente, compilamos el kernel y lo empaquetamos en formato .deb. El parámetro `-j$(nproc)` usa todos los núcleos disponibles de tu CPU para acelerar la compilación:

```bash
time sudo make bindeb-pkg -j$(nproc)
```

> El comando `time` nos mostrará cuánto tardó la compilación. Dependiendo de tu hardware, esto puede tomar desde 10 minutos hasta más de una hora.

## Instalación del nuevo kernel

Una vez compilado, encontrarás varios paquetes .deb en el directorio padre. Los instalamos todos con:

```bash
cd ..
sudo dpkg -i linux-*.deb
```

> Esto instalará el kernel, los headers y la imagen del kernel. Los archivos se colocarán automáticamente en `/boot` y se actualizará GRUB.

Si quieres probar sin compilar, puedes descargar los paquetes .deb de este ejemplo desde el siguiente enlace:

> **Descarga de ejemplo:** [https://files.diegovargas.es/compilacion-de-un-kernel-linux/](https://files.diegovargas.es/compilacion-de-un-kernel-linux/)
>
> Los archivos incluyen:
> - `linux-image-6.19.0-rc6_*.deb` - La imagen del kernel
> - `linux-headers-6.19.0-rc6_*.deb` - Los headers para desarrollo de módulos
> - `linux-libc-dev_*.deb` - Headers para desarrollo de aplicaciones en espacio de usuario

## Firmar el kernel para Secure Boot

Si tu sistema usa Secure Boot (la mayoría de equipos modernos), necesitarás firmar el kernel con tu propia clave. Secure Boot es una característica de seguridad que solo permite ejecutar software firmado con claves confiables.

### Creación del entorno para las claves

Primero creamos un directorio para almacenar nuestras claves de firma:

```bash
sudo mkdir /usr/src/kernel-compilation/sign-mok
cd /usr/src/kernel-compilation/sign-mok
```

### Generación del par de claves

Generamos un par de claves (pública y privada) que usaremos para firmar nuestro kernel:

```bash
sudo openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv \
  -outform DER -out MOK.der -days 36500 \
  -subj "/CN=Diego Vargas Secure Boot CA/"
```

> **Explicación de los parámetros:**
> - `-newkey rsa:2048`: Crea una clave RSA de 2048 bits
> - `-days 36500`: La clave será válida por 100 años
> - `-keyout MOK.priv`: Archivo de clave privada (mantener seguro)
> - `-out MOK.der`: Archivo de clave pública en formato DER
> - `CN=Diego Vargas Secure Boot CA`: Nombre del certificado (puedes personalizarlo)

### Conversión de formatos

Convertimos la clave pública de formato DER (binario) a PEM (texto), que es más fácil de manejar:

```bash
sudo openssl x509 -inform der -in MOK.der -out MOK.pem
```

### Importación en MOK (Machine Owner Key)

MOK es el sistema de gestión de claves propietarias en Secure Boot. Importamos nuestra clave:

```bash
sudo mokutil --import MOK.der
```

> Te pedirá una contraseña. Esta contraseña solo se usará una vez, en el siguiente reinicio, para confirmar que realmente quieres importar la clave.

### Firma del kernel

Ahora firmamos el kernel con nuestras claves:

```bash
sudo sbsign --key MOK.priv --cert MOK.pem \
  /boot/vmlinuz-6.19.0-rc6 \
  --output /boot/vmlinuz-6.19.0-rc6.new
sudo mv /boot/vmlinuz-6.19.0-rc6.new /boot/vmlinuz-6.19.0-rc6
```

> `sbsign` añade una firma digital al kernel. Secure Boot verificará esta firma antes de permitir que el kernel arranque.

### Actualización de GRUB

Actualizamos la configuración de GRUB para que reconozca el nuevo kernel firmado:

```bash
sudo update-grub
```

### Confirmación en MOK Manager

Al reiniciar, aparecerá el MOK Manager antes del arranque del sistema operativo. Aquí debemos confirmar la importación de nuestra clave:

```bash
sudo reboot
```

Verás una pantalla azul del MOK Manager. Sigue estos pasos:

![Pantalla inicial MOK Manager](/assets/img/capturas/compilacion-de-un-kernel-linux/firmar-con-mok/2026-01-20_18-51.png)

Selecciona "Enroll MOK" (Inscribir MOK):

![Enroll MOK](/assets/img/capturas/compilacion-de-un-kernel-linux/firmar-con-mok/2026-01-20_18-52.png)

Confirma que quieres continuar:

![Continue](/assets/img/capturas/compilacion-de-un-kernel-linux/firmar-con-mok/2026-01-20_18-53.png)

Selecciona "Yes" para inscribir la clave:

![Yes](/assets/img/capturas/compilacion-de-un-kernel-linux/firmar-con-mok/2026-01-20_18-53_1.png)

Introduce la contraseña que estableciste con `mokutil --import`:

![Password](/assets/img/capturas/compilacion-de-un-kernel-linux/firmar-con-mok/2026-01-20_18-53_2.png)

Finalmente, selecciona "Reboot" para reiniciar con la clave ya importada:

![Reboot](/assets/img/capturas/compilacion-de-un-kernel-linux/firmar-con-mok/2026-01-20_18-53_3.png)

## Verificaciones de seguridad

Una vez que el sistema haya arrancado, es importante verificar que todo está correctamente configurado.

### Verificar que la clave está importada

Comprueba que tu clave MOK está correctamente inscrita en el sistema:

```bash
mokutil --list-enrolled
```

> Este comando mostrará todas las claves MOK inscritas, incluyendo la que acabas de añadir.

### Verificar que el kernel está firmado

Comprueba que el kernel tiene una firma digital válida:

```bash
sudo sbverify --list /boot/vmlinuz-6.19.0-rc6
```

> Debería mostrar información sobre la firma del kernel.

### Verificar que Secure Boot confía en la firma

Verifica que la firma del kernel es confiable para Secure Boot:

```bash
sudo sbverify --cert /usr/src/kernel-compilation/sign-mok/MOK.pem /boot/vmlinuz-6.19.0-rc6
```

> Si la verificación es exitosa, mostrará "Signature verification OK".

### Verificar estado de Secure Boot

Confirma que Secure Boot está activo:

```bash
sudo mokutil --sb-state
```

> Debería mostrar "SecureBoot enabled" si está activado correctamente.

## Arranque directo UEFI → Kernel Linux (EFI Stub)

EFI Stub es una característica que permite que el kernel Linux sea arrancado directamente por el firmware UEFI, sin necesidad de un gestor de arranque como GRUB. Esto reduce la complejidad del proceso de arranque y mejora ligeramente el tiempo de inicio.

### Preparación de los archivos

Primero, copiamos el kernel y el initramfs a la partición EFI:

```bash
sudo cp /boot/vmlinuz-6.19.0-rc6 /boot/efi/EFI/debian/
sudo cp /boot/initrd.img-6.19.0-rc6 /boot/efi/EFI/debian/
```

> El initramfs (Initial RAM File System) es un sistema de archivos temporal que se carga en memoria durante el arranque, conteniendo los drivers necesarios para montar el sistema de archivos raíz real.

### Creación de la entrada de arranque con efibootmgr

Ahora creamos una entrada de arranque UEFI que apunte directamente a nuestro kernel:

```bash
export UUID=$(sudo blkid -s UUID -o value /dev/aso-kernel-vg/root)
sudo efibootmgr --create --disk /dev/vda --part 1 \
  --label "Debian Custom Kernel" \
  --loader '\EFI\debian\vmlinuz-6.19.0-rc6' \
  --unicode "root=UUID=$UUID ro initrd=\\EFI\debian\\initrd.img-6.19.0-rc6"
```

> **Explicación de los parámetros:**
> - `--disk /dev/vda --part 1`: Especifica la partición EFI (ajusta según tu sistema)
> - `--loader`: Ruta al kernel en la partición EFI (usa barras invertidas estilo Windows)
> - `--unicode`: Parámetros del kernel, incluyendo la raíz del sistema y el initramfs
> - `root=UUID=$UUID`: Identifica la partición raíz por su UUID único

### Configuración del orden de arranque

Verificamos las entradas de arranque actuales:

```bash
sudo efibootmgr
```

Configuramos el orden de arranque para que nuestro kernel personalizado sea la primera opción:

```bash
sudo efibootmgr --bootorder 0003,0002,0001,0000
```

> Los números (0003, 0002, etc.) son los identificadores de las entradas de arranque. Ajusta según los números que veas en la salida del comando anterior.

### Configuración de Secure Boot para arranque directo

Para que el arranque directo funcione con Secure Boot, necesitamos que el firmware UEFI confíe en nuestra clave. Copiamos el certificado a la partición EFI:

```bash
sudo cp /usr/src/kernel-compilation/sign-mok/MOK.der /boot/efi/
```

### Importación de la clave en la BIOS/UEFI

Ahora debemos importar la clave directamente en el firmware UEFI. Reinicia el sistema y entra en la configuración UEFI/BIOS (normalmente presionando F2, F10, Del o Esc durante el arranque).

Una vez en la BIOS, navega a la sección de Secure Boot y busca la opción para gestionar claves:

![Menú BIOS Secure Boot](/assets/img/capturas/compilacion-de-un-kernel-linux/arranque-sin-grub/2026-01-20_19-19.png)

Accede a la gestión de claves DB (Database):

![Gestión de claves](/assets/img/capturas/compilacion-de-un-kernel-linux/arranque-sin-grub/2026-01-20_19-19_1.png)

Selecciona la opción para inscribir una nueva clave desde archivo:

![Enroll from file](/assets/img/capturas/compilacion-de-un-kernel-linux/arranque-sin-grub/2026-01-20_19-19_2.png)

Navega a la partición EFI donde copiamos el archivo MOK.der:

![Buscar MOK.der](/assets/img/capturas/compilacion-de-un-kernel-linux/arranque-sin-grub/2026-01-20_19-20.png)

Selecciona el archivo MOK.der:

![Seleccionar MOK.der](/assets/img/capturas/compilacion-de-un-kernel-linux/arranque-sin-grub/2026-01-20_19-20_1.png)

Confirma la inscripción de la clave:

![Confirmar](/assets/img/capturas/compilacion-de-un-kernel-linux/arranque-sin-grub/2026-01-20_19-20_2.png)

Verifica que la clave se ha añadido correctamente:

![Clave añadida](/assets/img/capturas/compilacion-de-un-kernel-linux/arranque-sin-grub/2026-01-20_19-20_3.png)

Guarda los cambios en la configuración UEFI:

![Save changes](/assets/img/capturas/compilacion-de-un-kernel-linux/arranque-sin-grub/2026-01-20_19-20_4.png)

Confirma que deseas guardar:

![Confirm save](/assets/img/capturas/compilacion-de-un-kernel-linux/arranque-sin-grub/2026-01-20_19-20_5.png)

Sal de la BIOS y permite que el sistema se reinicie:

![Exit](/assets/img/capturas/compilacion-de-un-kernel-linux/arranque-sin-grub/2026-01-20_19-20_6.png)

## Conclusión

Has completado exitosamente la compilación de un kernel Linux personalizado, lo has firmado para Secure Boot y has configurado un arranque directo mediante EFI Stub. Este proceso te da un control completo sobre tu sistema operativo y te permite:

- **Optimizar** el kernel eliminando módulos innecesarios
- **Actualizar** a las últimas versiones sin esperar a los repositorios de tu distribución
- **Mantener la seguridad** mediante Secure Boot con tus propias claves
- **Acelerar el arranque** eliminando GRUB del proceso

Recuerda que cada vez que compiles un nuevo kernel, deberás repetir el proceso de firma y, si cambias las claves, volver a importarlas en MOK y en el firmware UEFI.
