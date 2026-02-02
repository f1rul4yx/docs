---
title: Guía Rápida: Kubernetes con kubeadm + HAProxy
date: 2026-02-02 13:15:00 +0200
categories: [Linux, Kubeadm]
tags: [kubernetes, kubeadm, linux]
---

# Guía Rápida: Kubernetes con kubeadm + HAProxy

Configuración mínima funcional de un cluster Kubernetes multi-nodo con balanceador HAProxy.

---

## 📋 Requisitos Previos

### Hardware (3 VMs):
- **Master:** 2 CPU, 4 GB RAM, 20 GB disco
- **Worker1:** 2 CPU, 2 GB RAM, 20 GB disco  
- **Worker2:** 2 CPU, 2 GB RAM, 20 GB disco

### Software:
- **OS:** Debian 13 Trixie
- **Hypervisor:** KVM/virt-manager
- **Red:** Todas en misma red (NAT/Bridge)

### IPs ejemplo:
```
192.168.122.120  k8s-master
192.168.122.109  k8s-worker1
192.168.122.169  k8s-worker2
```

---

## 🔧 Instalación en TODAS las VMs

### 1. Configurar hostname

```bash
# En cada VM según corresponda:
sudo hostnamectl set-hostname k8s-master    # En master
sudo hostnamectl set-hostname k8s-worker1   # En worker1
sudo hostnamectl set-hostname k8s-worker2   # En worker2
```

### 2. Configurar /etc/hosts

```bash
sudo nano /etc/hosts
```

Añadir (ajustar IPs):
```
192.168.122.120  k8s-master
192.168.122.109  k8s-worker1
192.168.122.169  k8s-worker2
```

### 3. Deshabilitar swap

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### 4. Módulos del kernel

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

### 5. Parámetros de red

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### 6. Instalar containerd

```bash
sudo apt update
sudo apt install -y containerd

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
```

### 7. Instalar dependencias

```bash
sudo apt install -y conntrack iptables ethtool socat ebtables
```

### 8. Instalar Kubernetes (binarios manuales)

```bash
KUBE_VERSION="v1.31.4"
ARCH="amd64"

cd /tmp
curl -LO "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/${ARCH}/kubeadm"
curl -LO "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/${ARCH}/kubelet"
curl -LO "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/${ARCH}/kubectl"

chmod +x kubeadm kubelet kubectl
sudo install -o root -g root -m 0755 kubeadm /usr/local/bin/kubeadm
sudo install -o root -g root -m 0755 kubelet /usr/local/bin/kubelet
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

### 9. Configurar systemd para kubelet

```bash
RELEASE_VERSION="v0.16.2"
DOWNLOAD_DIR="/usr/local/bin"

sudo curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubelet/kubelet.service" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /etc/systemd/system/kubelet.service

sudo mkdir -p /etc/systemd/system/kubelet.service.d
sudo curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
```

### 10. Instalar CNI plugins

```bash
CNI_PLUGINS_VERSION="v1.4.0"
sudo mkdir -p /opt/cni/bin
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz" | sudo tar -C /opt/cni/bin -xz
```

### 11. Instalar crictl

```bash
CRICTL_VERSION="v1.31.1"
curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz" | sudo tar -C /usr/local/bin -xz

cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF
```

### 12. Habilitar kubelet

```bash
sudo systemctl daemon-reload
sudo systemctl enable kubelet
```

---

## 🎯 Inicializar Cluster (SOLO EN MASTER)

### 1. Inicializar control plane

```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$(hostname -I | awk '{print $1}')
```

⚠️ **IMPORTANTE:** Guarda el comando `kubeadm join` que aparece al final.

### 2. Configurar kubectl

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 3. Instalar Flannel

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

Esperar 30-60 segundos y verificar:

```bash
kubectl get nodes
```

Debe mostrar:
```
NAME         STATUS   ROLES           AGE   VERSION
k8s-master   Ready    control-plane   3m    v1.31.4
```

---

## 👥 Unir Workers (EN CADA WORKER)

Ejecutar el comando guardado del paso anterior:

```bash
sudo kubeadm join 192.168.122.120:6443 --token XXXXX \
    --discovery-token-ca-cert-hash sha256:YYYYY
```

Verificar en el master:

```bash
kubectl get nodes
```

Debe mostrar los 3 nodos:
```
NAME          STATUS   ROLES           AGE   VERSION
k8s-master    Ready    control-plane   10m   v1.31.4
k8s-worker1   Ready    <none>          5m    v1.31.4
k8s-worker2   Ready    <none>          5m    v1.31.4
```

---

## 💾 Configurar StorageClass (EN MASTER)

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

Verificar:
```bash
kubectl get storageclass
```

---

## 🌐 Instalar Ingress Controller (EN MASTER)

### 1. Instalar NGINX Ingress

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml
```

### 2. Esperar a que esté listo

```bash
kubectl get pods -n ingress-nginx -w
```

### 3. Fijar NodePort a 30080

```bash
kubectl edit svc ingress-nginx-controller -n ingress-nginx
```

Modificar:
```yaml
  ports:
  - appProtocol: http
    name: http
    nodePort: 30080  # <-- Cambiar a 30080
    port: 80
    protocol: TCP
    targetPort: http
```

Guardar (`:wq`).

Verificar:
```bash
kubectl get svc -n ingress-nginx
```

Debe mostrar: `80:30080/TCP`

---

## 📦 Desplegar Aplicación (EN MASTER)

### Crear namespace

```bash
kubectl create namespace mi-app
```

### Archivo: mariadb-deployment.yaml

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb-pvc
  namespace: mi-app
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
  namespace: mi-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
      - name: mariadb
        image: mariadb:10.5
        ports:
        - containerPort: 3306
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "rootpass"
        - name: MYSQL_DATABASE
          value: "midb"
        - name: MYSQL_USER
          value: "user"
        - name: MYSQL_PASSWORD
          value: "password"
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: mariadb-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: mariadb-service
  namespace: mi-app
spec:
  type: ClusterIP
  ports:
  - port: 3306
    targetPort: 3306
  selector:
    app: mariadb
```

### Archivo: app-deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mi-app
  namespace: mi-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: mi-app
  template:
    metadata:
      labels:
        app: mi-app
    spec:
      containers:
      - name: app
        image: nginx:alpine  # Reemplazar con tu imagen
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: app-service
  namespace: mi-app
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: mi-app
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: mi-app
spec:
  ingressClassName: nginx
  rules:
  - host: mi-app.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
```

### Aplicar manifiestos

```bash
kubectl apply -f mariadb-deployment.yaml
kubectl apply -f app-deployment.yaml
```

### Verificar

```bash
kubectl get all -n mi-app
kubectl get pvc -n mi-app
kubectl get ingress -n mi-app
```

---

## ⚖️ Configurar HAProxy (EN MASTER)

### 1. Instalar HAProxy

```bash
# Detener nginx si existe
sudo systemctl stop nginx 2>/dev/null
sudo systemctl disable nginx 2>/dev/null

sudo apt update
sudo apt install -y haproxy
```

### 2. Configurar HAProxy

```bash
sudo nano /etc/haproxy/haproxy.cfg
```

Contenido mínimo:

```haproxy
global
    log /dev/log local0
    maxconn 4096
    daemon

defaults
    log     global
    mode    http
    option  httplog
    timeout connect 5000
    timeout client  50000
    timeout server  50000

listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 5s

frontend http_front
    bind *:80
    default_backend k8s_ingress

backend k8s_ingress
    balance roundrobin
    option httpchk GET /healthz
    http-check expect status 200
    
    server k8s-master 192.168.122.120:30080 check inter 2s fall 3 rise 2
    server k8s-worker1 192.168.122.109:30080 check inter 2s fall 3 rise 2
    server k8s-worker2 192.168.122.169:30080 check inter 2s fall 3 rise 2
```

**⚠️ Ajusta las IPs a las de tu cluster.**

### 3. Verificar y arrancar

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy
sudo systemctl enable haproxy
sudo systemctl status haproxy
```

### 4. Probar HAProxy

```bash
curl http://localhost
```

---

## 🎯 Acceso desde tu Máquina Anfitriona

### 1. Configurar /etc/hosts

```bash
sudo nano /etc/hosts
```

Añadir:
```
192.168.122.120  mi-app.local
```

### 2. Probar acceso

**Navegador:**
```
http://mi-app.local
```

**Terminal:**
```bash
curl http://mi-app.local
```

### 3. Ver estadísticas HAProxy

**Navegador:**
```
http://192.168.122.120:8404/stats
```

---

## ✅ Verificación

### Estado del cluster

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

### Estado de la aplicación

```bash
kubectl get all -n mi-app
kubectl get pvc -n mi-app
kubectl get ingress -n mi-app
```

### Probar escalado

```bash
kubectl scale deployment mi-app --replicas=5 -n mi-app
kubectl get pods -n mi-app -o wide
```

Los pods se distribuyen automáticamente entre worker1 y worker2.

### Probar alta disponibilidad

```bash
# Apagar un worker
virsh shutdown k8s-worker1

# La app sigue funcionando
curl http://mi-app.local

# Ver stats - worker1 aparecerá en rojo
# http://192.168.122.120:8404/stats

# Volver a encender
virsh start k8s-worker1
```

---

## 🔍 Troubleshooting

### Pods en Pending

```bash
kubectl describe pod <pod-name> -n mi-app
kubectl get events -n mi-app --sort-by=.metadata.creationTimestamp
```

### CoreDNS no arranca

```bash
kubectl delete pods -n kube-system -l k8s-app=kube-dns
```

### No puedo acceder a la app

```bash
# 1. ¿Pods corriendo?
kubectl get pods -n mi-app

# 2. ¿Service tiene endpoints?
kubectl get endpoints app-service -n mi-app

# 3. ¿Ingress configurado?
kubectl describe ingress app-ingress -n mi-app

# 4. ¿HAProxy corriendo?
sudo systemctl status haproxy

# 5. ¿Puerto 30080 responde?
curl -H "Host: mi-app.local" http://192.168.122.120:30080
```

### Token expirado

```bash
# En el master
kubeadm token create --print-join-command
```

---

## 📊 Arquitectura Final

```
Usuario (navegador)
    ↓
http://mi-app.local (puerto 80)
    ↓
HAProxy en master (192.168.122.120:80)
    ├─→ master:30080   (Ingress Controller)
    ├─→ worker1:30080  (Ingress Controller)
    └─→ worker2:30080  (Ingress Controller)
         ↓
    Ingress Controller (nginx)
         ↓ (match hostname: mi-app.local)
    Service app-service:80
         ↓ (balancea entre pods)
    Pods de la aplicación (x3)
         ↓
    Service mariadb-service:3306
         ↓
    Pod MariaDB (con volumen persistente)
```

---

## 📝 Comandos Útiles

### Gestión básica

```bash
# Ver nodos
kubectl get nodes

# Ver todos los recursos
kubectl get all -n mi-app

# Ver logs
kubectl logs <pod-name> -n mi-app

# Entrar en un pod
kubectl exec -it <pod-name> -n mi-app -- bash

# Escalar
kubectl scale deployment mi-app --replicas=5 -n mi-app
```

### HAProxy

```bash
# Estado
sudo systemctl status haproxy

# Recargar sin cortar conexiones
sudo systemctl reload haproxy

# Ver estadísticas CLI
echo "show stat" | sudo socat stdio /run/haproxy/admin.sock
```

---

## 🎓 Conceptos Clave

### ¿Qué es un NodePort?

Puerto abierto en **todos** los nodos del cluster (rango 30000-32767). Permite acceder al servicio desde fuera del cluster usando cualquier IP de nodo + puerto.

### ¿Por qué HAProxy balancea entre todos los nodos?

Kubernetes configura kube-proxy para que cualquier nodo pueda redirigir tráfico a los pods correctos, incluso si están en otro nodo. HAProxy aprovecha esto para distribuir carga.

### ¿Por qué local-path como StorageClass?

Crea volúmenes en el disco local de cada nodo. Simple para labs, pero en producción se usa almacenamiento distribuido (Ceph, NFS, cloud storage).

### ¿Qué hace el Ingress Controller?

Lee los recursos Ingress y configura nginx para enrutar tráfico HTTP según hostname/path. Es el "router HTTP" del cluster.

---

## 📚 Referencias

- [Kubernetes Docs](https://kubernetes.io/docs/)
- [kubeadm Setup](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Flannel](https://github.com/flannel-io/flannel)
- [NGINX Ingress](https://kubernetes.github.io/ingress-nginx/)
- [HAProxy Docs](http://www.haproxy.org/)

---

**Creado por:** Diego | **Proyecto:** ASIR - Kubernetes con kubeadm | **Fecha:** Febrero 2026
