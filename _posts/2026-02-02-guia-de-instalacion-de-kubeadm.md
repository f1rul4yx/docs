---
title: Guía de Instalación de kubeadm
date: 2026-02-02 13:15:00 +0200
categories: [Linux, Kubeadm]
tags: [kubernetes, kubeadm, linux]
---

Guía paso a paso para instalar kubeadm en Linux sin gestor de paquetes.

---

## ¿Qué es kubeadm?

**kubeadm** es una herramienta oficial de Kubernetes que permite crear clústeres de forma sencilla mediante dos comandos principales:

- `kubeadm init` → Inicializa el nodo maestro (control plane)
- `kubeadm join` → Une nodos trabajadores al clúster

---

## Componentes que instalaremos

| Componente | Función |
|------------|---------|
| **kubeadm** | Herramienta para crear y gestionar el clúster |
| **kubelet** | Agente que corre en cada nodo y gestiona los pods/contenedores |
| **kubectl** | Cliente de línea de comandos para interactuar con el clúster |

---

## Paso 1: Configurar Swap

**¿Por qué?** → El kubelet por defecto no arranca si detecta swap activo, ya que puede afectar al rendimiento y la predicción de recursos de los contenedores.

```bash
# Desactivar swap temporalmente
sudo swapoff -a

# Desactivar swap permanentemente (comentar línea de swap en fstab)
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

---

## Paso 2: Instalar un Container Runtime

**¿Por qué?** → Kubernetes necesita un runtime de contenedores para ejecutar los pods. Kubernetes usa la interfaz CRI (Container Runtime Interface) para comunicarse con el runtime.

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

---

## Paso 3: Cargar módulos del kernel necesarios

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

## Paso 4: Configurar parámetros de red del kernel

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

## Paso 5: Instalar kubeadm, kubelet y kubectl

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

# 5. Instalar kubectl
cd ~
curl -LO "https://dl.k8s.io/release/${RELEASE}/bin/linux/${ARCH}/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
```

---

## Paso 6: Habilitar el servicio kubelet

**¿Por qué?** → El kubelet debe estar activo para que kubeadm pueda configurarlo durante la inicialización del clúster.

```bash
sudo systemctl enable --now kubelet
```

> **Nota:** En este punto el kubelet estará en un bucle de reinicio (crashloop). Esto es **normal** porque está esperando instrucciones de kubeadm.

---

## Paso 7: Crear enlace simbólico para plugins CNI

**¿Por qué?** → Algunos componentes (como CoreDNS) buscan los plugins CNI en `/usr/lib/cni`, pero la instalación estándar los coloca en `/opt/cni/bin`. Sin este enlace, los pods de sistema como CoreDNS pueden quedarse en estado `ContainerCreating` o `CrashLoopBackOff`.

Ejecutar en **todos los nodos** (control-plane y workers):

```bash
# Crear directorio si no existe
sudo mkdir -p /usr/lib/cni

# Crear enlaces simbólicos a los plugins CNI
sudo ln -s /opt/cni/bin/* /usr/lib/cni/
```

Si ya habías inicializado el clúster y tienes pods en estado fallido:

```bash
# En el nodo control-plane, reiniciar kubelet
sudo systemctl restart kubelet

# Eliminar pods del sistema para que se regeneren
kubectl delete pod -n kube-system --all

# Si tienes ingress-nginx instalado
kubectl delete pod -n ingress-nginx --all
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

# Verificar que los enlaces CNI existen
ls -la /usr/lib/cni/

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
   # Flannel
   kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
   ```

4. **Instalar NGINX Ingress Controller:**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/baremetal/deploy.yaml
   
   # Verificar que está corriendo
   kubectl get pods -n ingress-nginx
   ```

5. **Unir nodos worker al clúster:**
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

### CoreDNS o pods del sistema no arrancan (ContainerCreating)

Problema típico: los plugins CNI están en `/opt/cni/bin` pero se buscan en `/usr/lib/cni`.

```bash
# Ver el estado de los pods del sistema
kubectl get pods -n kube-system

# Si CoreDNS está en ContainerCreating, verificar logs
kubectl describe pod -n kube-system -l k8s-app=kube-dns
```

Solución (ejecutar en todos los nodos):

```bash
sudo mkdir -p /usr/lib/cni
sudo ln -s /opt/cni/bin/* /usr/lib/cni/

# En el control-plane
sudo systemctl restart kubelet
kubectl delete pod -n kube-system --all
```

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
