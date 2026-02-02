---
title: Guía de Instalación de kubeadm
date: 2026-02-02 13:15:00 +0200
categories: [Linux, Kubeadm]
tags: [kubernetes, kubeadm, linux]
---

Guía paso a paso para instalar kubeadm en Linux, basada en la documentación oficial de Kubernetes.

---

## ¿Qué es kubeadm?

**kubeadm** es una herramienta oficial de Kubernetes que permite crear clústeres de forma sencilla mediante dos comandos principales:

- `kubeadm init` → Inicializa el nodo maestro (control plane)
- `kubeadm join` → Une nodos trabajadores al clúster

kubeadm se encarga únicamente del **bootstrapping** (arranque inicial) del clúster, no de aprovisionar máquinas ni instalar addons adicionales.

---

## Componentes que instalaremos

| Componente | Función |
|------------|---------|
| **kubeadm** | Herramienta para crear y gestionar el clúster |
| **kubelet** | Agente que corre en cada nodo y gestiona los pods/contenedores |
| **kubectl** | Cliente de línea de comandos para interactuar con el clúster |

---

## Requisitos previos

### Hardware mínimo

| Recurso | Requisito |
|---------|-----------|
| RAM | 2 GB mínimo |
| CPU | 2 cores (para nodos control plane) |
| Red | Conectividad completa entre todos los nodos |

### Requisitos del sistema

Cada nodo debe tener:

- **Hostname único**
- **MAC address única**
- **product_uuid único**

Para verificar esto:

```bash
# Ver MAC address
ip link

# Ver product_uuid
sudo cat /sys/class/dmi/id/product_uuid
```

---

## Paso 1: Verificar puertos necesarios

Kubernetes necesita ciertos puertos abiertos para la comunicación entre componentes.

### Nodo Control Plane (Maestro)

| Puerto | Protocolo | Uso |
|--------|-----------|-----|
| 6443 | TCP | API Server |
| 2379-2380 | TCP | etcd |
| 10250 | TCP | Kubelet API |
| 10259 | TCP | kube-scheduler |
| 10257 | TCP | kube-controller-manager |

### Nodos Worker

| Puerto | Protocolo | Uso |
|--------|-----------|-----|
| 10250 | TCP | Kubelet API |
| 10256 | TCP | kube-proxy |
| 30000-32767 | TCP | NodePort Services |

Para verificar si un puerto está abierto:

```bash
nc 127.0.0.1 6443 -zv -w 2
```

---

## Paso 2: Configurar Swap

**¿Por qué?** → El kubelet por defecto no arranca si detecta swap activo, ya que puede afectar al rendimiento y la predicción de recursos de los contenedores.

### Opción A: Desactivar Swap (recomendado)

```bash
# Desactivar swap temporalmente
sudo swapoff -a

# Desactivar swap permanentemente (comentar línea de swap en fstab)
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### Opción B: Tolerar Swap

Si necesitas mantener swap, añade en la configuración del kubelet:

```yaml
failSwapOn: false
```

---

## Paso 3: Instalar un Container Runtime

**¿Por qué?** → Kubernetes necesita un runtime de contenedores para ejecutar los pods. Kubernetes usa la interfaz CRI (Container Runtime Interface) para comunicarse con el runtime.

### Runtimes compatibles

| Runtime | Socket |
|---------|--------|
| containerd | `unix:///var/run/containerd/containerd.sock` |
| CRI-O | `unix:///var/run/crio/crio.sock` |
| Docker + cri-dockerd | `unix:///var/run/cri-dockerd.sock` |

### Instalar containerd (recomendado)

```bash
# En Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y containerd

# Crear configuración por defecto
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Habilitar SystemdCgroup (importante para kubelet)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Reiniciar containerd
sudo systemctl restart containerd
sudo systemctl enable containerd
```

> **Nota:** Docker Engine no implementa CRI directamente. Si usas Docker, necesitas instalar `cri-dockerd` como puente.

---

## Paso 4: Cargar módulos del kernel necesarios

**¿Por qué?** → Kubernetes necesita ciertos módulos del kernel para el networking entre contenedores.

```bash
# Crear archivo de configuración para cargar módulos al arranque
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Cargar módulos ahora
sudo modprobe overlay
sudo modprobe br_netfilter
```

**Explicación de los módulos:**

- `overlay` → Sistema de archivos usado por los contenedores
- `br_netfilter` → Permite que el tráfico de red de bridges pase por iptables

---

## Paso 5: Configurar parámetros de red del kernel

**¿Por qué?** → Permite que los paquetes de red sean procesados correctamente entre pods.

```bash
# Configurar parámetros sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Aplicar parámetros sin reiniciar
sudo sysctl --system
```

**Explicación:**

- `bridge-nf-call-iptables` → El tráfico del bridge pasa por iptables (necesario para Network Policies)
- `ip_forward` → Permite que el nodo actúe como router (necesario para routing entre pods)

---

## Paso 6: Instalar kubeadm, kubelet y kubectl

### Para distribuciones basadas en Debian/Ubuntu

```bash
# 1. Instalar dependencias
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# 2. Añadir la clave GPG del repositorio de Kubernetes
# (Crea el directorio si no existe)
sudo mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | \
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# 3. Añadir el repositorio de Kubernetes
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list

# 4. Instalar los paquetes
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# 5. Bloquear versiones para evitar actualizaciones automáticas
# (Las actualizaciones de Kubernetes requieren un proceso especial)
sudo apt-mark hold kubelet kubeadm kubectl
```

### Para distribuciones basadas en Red Hat/CentOS/Fedora

```bash
# 1. Configurar SELinux en modo permisivo
# (Necesario para que los contenedores accedan al filesystem del host)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# 2. Añadir el repositorio de Kubernetes
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.35/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.35/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# 3. Instalar los paquetes
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
```

### Instalación manual (sin gestor de paquetes)

```bash
# 1. Instalar plugins CNI (necesarios para la red de pods)
CNI_PLUGINS_VERSION="v1.3.0"
ARCH="amd64"
DEST="/opt/cni/bin"
sudo mkdir -p "$DEST"
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-${CNI_PLUGINS_VERSION}.tgz" | sudo tar -C "$DEST" -xz

# 2. Definir directorio de descarga
DOWNLOAD_DIR="/usr/local/bin"
sudo mkdir -p "$DOWNLOAD_DIR"

# 3. Instalar kubeadm y kubelet
RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
ARCH="amd64"
cd $DOWNLOAD_DIR
sudo curl -L --remote-name-all https://dl.k8s.io/release/${RELEASE}/bin/linux/${ARCH}/{kubeadm,kubelet}
sudo chmod +x {kubeadm,kubelet}

# 4. Configurar servicio systemd para kubelet
RELEASE_VERSION="v0.16.2"
curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubelet/kubelet.service" | \
    sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /usr/lib/systemd/system/kubelet.service

sudo mkdir -p /usr/lib/systemd/system/kubelet.service.d
curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf" | \
    sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
```

---

## Paso 7: Habilitar el servicio kubelet

**¿Por qué?** → El kubelet debe estar activo para que kubeadm pueda configurarlo durante la inicialización del clúster.

```bash
sudo systemctl enable --now kubelet
```

> **Nota:** En este punto el kubelet estará en un bucle de reinicio (crashloop). Esto es **normal** porque está esperando instrucciones de kubeadm.

---

## Paso 8: Configurar el cgroup driver

**¿Por qué?** → El container runtime y el kubelet deben usar el mismo cgroup driver para gestionar recursos correctamente. Si no coinciden, el kubelet fallará.

Los cgroup drivers disponibles son:

- `cgroupfs` → Driver nativo
- `systemd` → Usa systemd para gestionar cgroups (recomendado en sistemas con systemd)

### Verificar el cgroup driver del runtime

Para containerd:

```bash
containerd config dump | grep SystemdCgroup
```

### Configurar kubelet para usar systemd

Crea o edita `/var/lib/kubelet/config.yaml`:

```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
```

---

## Verificación final

Antes de ejecutar `kubeadm init`, verifica que todo esté listo:

```bash
# Verificar que los módulos están cargados
lsmod | grep br_netfilter
lsmod | grep overlay

# Verificar parámetros de red
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.ipv4.ip_forward

# Verificar que swap está desactivado
free -h

# Verificar que el runtime está funcionando
sudo systemctl status containerd

# Verificar versiones instaladas
kubeadm version
kubelet --version
kubectl version --client
```

---

## Siguientes pasos

Una vez completada la instalación, puedes:

1. **Inicializar el nodo maestro:**
   ```bash
   sudo kubeadm init --pod-network-cidr=10.244.0.0/16
   ```

2. **Configurar kubectl para tu usuario:**
   ```bash
   mkdir -p $HOME/.kube
   sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config
   ```

3. **Instalar un plugin de red (CNI):**
   ```bash
   # Ejemplo con Flannel
   kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
   ```

4. **Unir nodos worker al clúster:**
   ```bash
   # Usar el comando que devuelve kubeadm init
   kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
   ```

---

## Comandos útiles de kubeadm

| Comando | Descripción |
|---------|-------------|
| `kubeadm init` | Inicializa el control plane |
| `kubeadm join` | Une un nodo al clúster |
| `kubeadm reset` | Deshace cambios de init/join |
| `kubeadm token` | Gestiona tokens de bootstrap |
| `kubeadm upgrade` | Actualiza el clúster |
| `kubeadm certs` | Gestiona certificados |
| `kubeadm version` | Muestra la versión |

---

## Troubleshooting común

### El kubelet no arranca

```bash
# Ver logs del kubelet
journalctl -xeu kubelet
```

### Problemas de red

```bash
# Verificar que los módulos están cargados
lsmod | grep br_netfilter

# Si no están, cargarlos manualmente
sudo modprobe br_netfilter
```

### Swap activo

```bash
# Verificar swap
swapon --show

# Desactivar
sudo swapoff -a
```

---

## Referencias

- [Documentación oficial de kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/)
- [Instalación de kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Crear un clúster con kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)

---

*Documento generado a partir de la documentación oficial de Kubernetes v1.35*
