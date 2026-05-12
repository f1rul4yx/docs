---
title: Guía de arduino-cli — Instalación y primeros pasos
date: 2026-05-12 13:41:00 +0200
categories: [Electrónica, Programación]
tags: [arduino, arduino-cli, electrónica, programación, linux, avr]
---

Guía práctica para instalar `arduino-cli` desde cero, compilar y subir el primer programa a un Arduino Uno, todo desde la terminal, sin IDE gráfico.

---

## ¿Qué es arduino-cli?

`arduino-cli` es la herramienta oficial de línea de comandos de Arduino. Permite compilar sketches, subirlos a la placa y gestionar librerías y placas sin necesidad del editor gráfico.

**¿Por qué usarlo?**

- Ocupa unos pocos MB frente a los cientos del IDE
- Se integra en scripts y pipelines de CI/CD
- Funciona igual en cualquier distribución Linux
- Permite editar el código con cualquier editor (vim, nano, VS Code...)

---

## Paso 1: Instalar arduino-cli

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install arduino-cli
```

### Arch Linux

```bash
sudo pacman -S arduino-cli
```

### Otras distribuciones

`arduino-cli` también se puede instalar mediante el script oficial que descarga el binario estático:

```bash
curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh
```

Este método es útil cuando el paquete no está disponible en los repositorios de la distribución.

---

## Paso 2: Configurar permisos de puerto serie

Para poder escribir en el puerto serie (subir sketches) sin usar `sudo` cada vez, añadimos nuestro usuario al grupo de dialout:

### Debian / Ubuntu

```bash
sudo usermod -aG dialout $USER
```

### Arch Linux

```bash
sudo usermod -aG uucp $USER
```

> El cambio de grupo no tiene efecto hasta la siguiente sesión. Si no quieres reiniciar la sesión ahora, usa `sudo` en el paso de subida (Paso 5) para evitar errores de permisos.
{: .prompt-warning }

---

## Paso 3: Inicializar arduino-cli y descargar el core

Arduino-cli necesita los "cores" para saber compilar para cada tipo de placa. Para el Arduino Uno (chip AVR):

```bash
arduino-cli config init
arduino-cli core update-index
arduino-cli core install arduino:avr
```

| Comando | Qué hace |
|---|---|
| `config init` | Crea el fichero de configuración en `~/.arduino15/arduino-cli.yaml` |
| `core update-index` | Descarga el índice actualizado de cores y placas disponibles |
| `core install arduino:avr` | Descarga las herramientas de compilación (compilador cruzado AVR-GCC, avrdude, etc.) |

> El core `arduino:avr` da soporte a Arduino Uno, Mega, Nano, Leonardo y todas las placas basadas en microcontroladores AVR de 8 bits.
{: .prompt-info }

---

## Paso 4: Crear el primer sketch

Un sketch de Arduino necesita una carpeta con el mismo nombre que el fichero `.ino`.

Creamos el proyecto blink básico:

```bash
mkdir -p blink
cat <<'EOF' > blink/blink.ino
void setup() {
  pinMode(13, OUTPUT);
}

void loop() {
  digitalWrite(13, HIGH);
  delay(500);
  digitalWrite(13, LOW);
  delay(500);
}
EOF
```

### Explicación del código

| Línea | Descripción |
|---|---|
| `pinMode(13, OUTPUT)` | Configura el pin digital 13 como salida. |
| `digitalWrite(13, HIGH)` | Pone el pin 13 a 5V (enciende el LED). |
| `delay(500)` | Espera 500 milisegundos. |
| `digitalWrite(13, LOW)` | Pone el pin 13 a 0V (apaga el LED). |

El pin 13 del Arduino Uno tiene un LED integrado en la placa, marcado con la letra **L**. No hace falta conectar nada externo para ver el resultado.

---

## Paso 5: Compilar y subir

### Compilar

```bash
arduino-cli compile --fqbn arduino:avr:uno blink/
```

El parámetro `--fqbn` (Fully Qualified Board Name) identifica la placa exacta: `fabricante:arquitectura:modelo`. Para el Uno es `arduino:avr:uno`.

### Subir

Conectamos el Arduino por USB y subimos:

```bash
arduino-cli upload -p /dev/ttyACM0 --fqbn arduino:avr:uno blink/
```

### Si falla por permisos

Si no has reiniciado la sesión tras el `usermod` (Paso 2), anteponemos `sudo`:

```bash
sudo arduino-cli upload -p /dev/ttyACM0 --fqbn arduino:avr:uno blink/
```

### Encontrar el puerto correcto

Si no estás seguro de que el puerto sea `/dev/ttyACM0`, puedes listar las placas conectadas:

```bash
arduino-cli board list
```

La salida muestra el puerto y el modelo de la placa detectada:

```
Port         Type              Board Name              FQBN
/dev/ttyACM0 Serial Port (USB) Arduino Uno             arduino:avr:uno
```

> En algunos sistemas el Arduino Uno aparece como `/dev/ttyACM0` y en otros como `/dev/ttyUSB0`. Siempre comprueba con `arduino-cli board list` antes de subir.
{: .prompt-tip }

---

## Monitor serie

Una vez que el programa está subido, el Arduino puede enviar datos de vuelta al ordenador por el puerto serie. Esto es útil para depurar, ver sensores en tiempo real o simplemente confirmar que la placa funciona.

### Código de ejemplo

Modificamos el sketch anterior para que envíe un mensaje cada vez que enciende y apaga el LED:

```cpp
void setup() {
  pinMode(13, OUTPUT);
  Serial.begin(9600);
}

void loop() {
  digitalWrite(13, HIGH);
  Serial.println("LED encendido");
  delay(500);

  digitalWrite(13, LOW);
  Serial.println("LED apagado");
  delay(500);
}
```

| Línea | Descripción |
|---|---|
| `Serial.begin(9600)` | Inicia la comunicación serie a 9600 baudios. |
| `Serial.println("...")` | Envía una línea de texto por el puerto USB. |

### Abrir el monitor

Compila y sube el sketch, y luego ejecuta:

```bash
arduino-cli monitor -p /dev/ttyACM0
```

La salida se muestra en tiempo real:

```
LED encendido
LED apagado
LED encendido
LED apagado
...
```

Para salir pulsa `Ctrl+C`.

> La velocidad de 9600 baudios es la más común y compatible con cualquier sistema. Asegúrate de que el valor en `Serial.begin()` coincide con la configuración por defecto del monitor (9600).
{: .prompt-tip }

> `arduino-cli monitor` puede dar errores de permisos si el usuario no pertenece al grupo `dialout` / `uucp`. Si ocurre, anteponer `sudo` igual que en el paso de subida.
{: .prompt-warning }

---

## Conexión del LED externo (opcional)

Para ver el parpadeo con un LED externo en lugar del integrado:

1. Conecta el **ánodo** (pata larga) del LED al pin digital 13
2. Conecta el **cátodo** (pata corta) a GND a través de una resistencia de **220 Ω – 330 Ω**

```
Arduino Uno              LED
┌─────────┐
│      13 ├────────────── Ánodo (pata larga)
│         │
│     GND ├──[330Ω]───── Cátodo (pata corta)
└─────────┘
```

> La resistencia es necesaria para limitar la corriente que pasa por el LED. Sin ella, el LED se quemaría en segundos.
{: .prompt-warning }

---

## Troubleshooting

### Error de permisos en el puerto

```
Error opening serial port '/dev/ttyACM0'. (Permission denied)
```

**Solución:** Añade tu usuario al grupo `dialout` (Debian) o `uucp` (Arch) y reinicia la sesión, o usa `sudo` en el comando `upload`.

### Core not found

```
Error: required platform 'arduino:avr' not found
```

**Solución:** Ejecuta `arduino-cli core update-index` seguido de `arduino-cli core install arduino:avr`.

### Sketch directory mismatch

```
Error: sketch must be inside a directory with the same name as the .ino file
```

**Solución:** El fichero `.ino` debe estar dentro de una carpeta con el mismo nombre: `blink/blink.ino`.

### Puerto no detectado

```
No boards found in the system
```

**Solución:** Comprueba que el cable USB soporta datos (no solo carga), que el Arduino está correctamente alimentado (LED verde encendido) y que el usuario tiene permisos de lectura en `/dev/ttyACM0`.

---

## Referencias

- [Documentación oficial de arduino-cli](https://arduino.github.io/arduino-cli/)
- [Arduino CLI GitHub](https://github.com/arduino/arduino-cli)
- [Referencia del lenguaje Arduino](https://www.arduino.cc/reference/en/)
