---
title: Instalación servidor ssh Windows 11
date: 2025-10-08 22:26:00 +0200
categories: [Windows, Instalación]
tags: [ssh, windows]
---

A continuación voy a explicar como instalar el servidor ssh en Windows 11 para poder conectarnos a el.

1. Lo primero será abrir la PowerShell con permisos de administrador e instalar OpenSSH.Server.

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/1-powershell.png)

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/2-instalar-openssh.png)

2. Después tendremos que añadir el puerto 22 al firwall.

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/3-windows-firewall.png)

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/4-nueva-regla.png)

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/5-regla-sshd-1.png)

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/6-regla-sshd-2.png)

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/7-regla-sshd-3.png)

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/8-regla-sshd-4.png)

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/9-regla-sshd-5.png)

3. Ahora en el panel de Servicios vamos a configurar para que el servicio se ejecute automáticamente.

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/10-servicios.png)

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/11-modificacion-servicios-1.png)

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/12-modificacion-servicios-2.png)

## Extra

Como configuración extra voy a habilitar la entrada de paquetes icmp4 para poder realizar ping a la máquina Windows.

![](/assets/img/capturas/instalacion-servidor-ssh-windows-11/13-firewall-icmp4.png)
