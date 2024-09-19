#!/bin/bash

# Definir directorios y rutas
BASE_DIR="/home/core/nginx-docker/certificates"
LOG_FILE="${BASE_DIR}/generate_certificates.log"

# Crear archivo de log
exec > >(tee -i ${LOG_FILE})
exec 2>&1
set -e  # Detener el script si ocurre algún error

# Variables
NODES=("master1" "master2" "master3" "worker1" "worker2" "worker3")
MASTER_IPS=("10.17.4.21" "10.17.4.22" "10.17.4.23")
WORKER_IPS=("10.17.4.24" "10.17.4.25" "10.17.4.26")
ETCD_NODES=("10.17.4.21" "10.17.4.22" "10.17.4.23" "10.17.4.27")
BOOTSTRAP_NODE="10.17.4.27"

# Crear la estructura de directorios
echo "Creando la estructura de directorios..."
sudo mkdir -p ${BASE_DIR}/{shared,sa,kubelet,apiserver,etcd,apiserver-etcd-client,kube-controller-manager,kube-scheduler,kube-proxy}

# Función para eliminar certificados existentes
remove_existing_certificates() {
    echo "Eliminando certificados existentes..."
    sudo rm -f ${BASE_DIR}/shared/*.crt ${BASE_DIR}/kubelet/*.crt ${BASE_DIR}/apiserver/*.crt ${BASE_DIR}/etcd/*.crt ${BASE_DIR}/apiserver-etcd-client/*.crt
}

# 1. Generar el archivo de configuración de la CA (ca-config.json)
generate_ca_config() {
    echo "Generando archivo de configuración de CA..."
  cat > ${BASE_DIR}/shared/ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "expiry": "8760h",
        "usages": [
          "signing",
          "key encipherment",
          "server auth",
          "client auth"
        ]
      }
    }
  }
}
EOF
}

# 2. Generar certificado CA (Autoridad Certificadora)
generate_ca_certificate() {
    echo "Generando certificado CA..."
  cat > ${BASE_DIR}/shared/ca-csr.json <<EOF
{
  "CN": "Kubernetes-CA",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "Kubernetes",
      "OU": "CA",
      "L": "Madrid",
      "ST": "Madrid",
      "C": "ES"
    }
  ]
}
EOF
    
    cfssl gencert -initca ${BASE_DIR}/shared/ca-csr.json | cfssljson -bare ${BASE_DIR}/shared/ca
}

# 3. Generar certificado de administrador de Kubernetes
generate_admin_certificate() {
    echo "Generando certificado de administrador de Kubernetes..."
  cat > ${BASE_DIR}/shared/admin-csr.json <<EOF
{
  "CN": "kubernetes-admin",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "system:masters",
      "OU": "Kubernetes",
      "L": "Madrid",
      "ST": "Madrid",
      "C": "ES"
    }
  ]
}
EOF
    
    cfssl gencert \
    -ca=${BASE_DIR}/shared/ca.pem \
    -ca-key=${BASE_DIR}/shared/ca-key.pem \
    -config=${BASE_DIR}/shared/ca-config.json \
    -profile=kubernetes \
    ${BASE_DIR}/shared/admin-csr.json | cfssljson -bare ${BASE_DIR}/shared/admin
}

# 4. Generar certificados de Kubelet para todos los nodos
generate_kubelet_certificates() {
    for i in "${!NODES[@]}"; do
        NODE="${NODES[$i]}"
        NODE_IP="${MASTER_IPS[$i]:-${WORKER_IPS[$i]}}"
        echo "Generando certificado de Kubelet para ${NODE}..."
    cat > ${BASE_DIR}/kubelet/kubelet-${NODE}-csr.json <<EOF
{
  "CN": "system:node:${NODE}",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "system:nodes",
      "L": "Madrid",
      "ST": "Madrid",
      "C": "ES"
    }
  ]
}
EOF
        
        cfssl gencert \
        -ca=${BASE_DIR}/shared/ca.pem \
        -ca-key=${BASE_DIR}/shared/ca-key.pem \
        -config=${BASE_DIR}/shared/ca-config.json \
        -hostname=${NODE},${NODE_IP} \
        -profile=kubernetes \
        ${BASE_DIR}/kubelet/kubelet-${NODE}-csr.json | cfssljson -bare ${BASE_DIR}/kubelet/${NODE}
    done
}

# 5. Generar certificados del servidor API (kube-apiserver)
generate_apiserver_certificate() {
    echo "Generando certificado del servidor API..."
  cat > ${BASE_DIR}/apiserver/apiserver-csr.json <<EOF
{
  "CN": "kube-apiserver",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "Kubernetes",
      "L": "Madrid",
      "ST": "Madrid",
      "C": "ES"
    }
  ]
}
EOF
    
    cfssl gencert \
    -ca=${BASE_DIR}/shared/ca.pem \
    -ca-key=${BASE_DIR}/shared/ca-key.pem \
    -config=${BASE_DIR}/shared/ca-config.json \
    -hostname=127.0.0.1,${MASTER_IPS[0]},${MASTER_IPS[1]},${MASTER_IPS[2]},${BOOTSTRAP_NODE} \
    -profile=kubernetes \
    ${BASE_DIR}/apiserver/apiserver-csr.json | cfssljson -bare ${BASE_DIR}/apiserver/apiserver
}

# 6. Generar certificados de ETCD
generate_etcd_certificates() {
    for NODE in "${ETCD_NODES[@]}"; do
        echo "Generando certificados de ETCD para ${NODE}..."
    cat > ${BASE_DIR}/etcd/etcd-${NODE}-csr.json <<EOF
{
  "CN": "etcd",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "Kubernetes",
      "OU": "ETCD",
      "L": "Madrid",
      "ST": "Madrid",
      "C": "ES"
    }
  ]
}
EOF
        
        cfssl gencert \
        -ca=${BASE_DIR}/shared/ca.pem \
        -ca-key=${BASE_DIR}/shared/ca-key.pem \
        -config=${BASE_DIR}/shared/ca-config.json \
        -hostname=${NODE},${BOOTSTRAP_NODE} \
        -profile=kubernetes \
        ${BASE_DIR}/etcd/etcd-${NODE}-csr.json | cfssljson -bare ${BASE_DIR}/etcd/etcd-${NODE}
    done
}

# 7. Generar certificados de kube-controller-manager
generate_kube_controller_manager_certificate() {
    echo "Generando certificado para kube-controller-manager..."
  cat > ${BASE_DIR}/kube-controller-manager/kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "system:kube-controller-manager",
      "L": "Madrid",
      "ST": "Madrid",
      "C": "ES"
    }
  ]
}
EOF
    
    cfssl gencert \
    -ca=${BASE_DIR}/shared/ca.pem \
    -ca-key=${BASE_DIR}/shared/ca-key.pem \
    -config=${BASE_DIR}/shared/ca-config.json \
    -profile=kubernetes \
    ${BASE_DIR}/kube-controller-manager/kube-controller-manager-csr.json | cfssljson -bare ${BASE_DIR}/kube-controller-manager/kube-controller-manager
}

# 8. Generar certificados de kube-scheduler
generate_kube_scheduler_certificate() {
    echo "Generando certificado para kube-scheduler..."
  cat > ${BASE_DIR}/kube-scheduler/kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "system:kube-scheduler",
      "L": "Madrid",
      "ST": "Madrid",
      "C": "ES"
    }
  ]
}
EOF
    
    cfssl gencert \
    -ca=${BASE_DIR}/shared/ca.pem \
    -ca-key=${BASE_DIR}/shared/ca-key.pem \
    -config=${BASE_DIR}/shared/ca-config.json \
    -profile=kubernetes \
    ${BASE_DIR}/kube-scheduler/kube-scheduler-csr.json | cfssljson -bare ${BASE_DIR}/kube-scheduler/kube-scheduler
}

# 9. Generar certificados de kube-proxy
generate_kube_proxy_certificate() {
    echo "Generando certificado para kube-proxy..."
  cat > ${BASE_DIR}/kube-proxy/kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "system:kube-proxy",
      "L": "Madrid",
      "ST": "Madrid",
      "C": "ES"
    }
  ]
}
EOF
    
    cfssl gencert \
    -ca=${BASE_DIR}/shared/ca.pem \
    -ca-key=${BASE_DIR}/shared/ca-key.pem \
    -config=${BASE_DIR}/shared/ca-config.json \
    -profile=kubernetes \
    ${BASE_DIR}/kube-proxy/kube-proxy-csr.json | cfssljson -bare ${BASE_DIR}/kube-proxy/kube-proxy
}

# 10. Generar certificados de sa.key y sa.pub (para los tokens del ServiceAccount)
generate_service_account_certificates() {
    echo "Generando certificados para ServiceAccount (sa)..."
  cat > ${BASE_DIR}/sa/sa-csr.json <<EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "Kubernetes",
      "OU": "ServiceAccounts",
      "L": "Madrid",
      "ST": "Madrid",
      "C": "ES"
    }
  ]
}
EOF
    
    cfssl gencert \
    -ca=${BASE_DIR}/shared/ca.pem \
    -ca-key=${BASE_DIR}/shared/ca-key.pem \
    -config=${BASE_DIR}/shared/ca-config.json \
    -profile=kubernetes \
    ${BASE_DIR}/sa/sa-csr.json | cfssljson -bare ${BASE_DIR}/sa/sa
}

# 11. Generar certificados para apiserver-etcd-client
generate_apiserver_etcd_client_certificate() {
    echo "Generando certificado apiserver-etcd-client..."
  cat > ${BASE_DIR}/apiserver-etcd-client/apiserver-etcd-client-csr.json <<EOF
{
  "CN": "apiserver-etcd-client",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "Kubernetes",
      "OU": "apiserver-etcd-client",
      "L": "Madrid",
      "ST": "Madrid",
      "C": "ES"
    }
  ]
}
EOF
    
    cfssl gencert \
    -ca=${BASE_DIR}/shared/ca.pem \
    -ca-key=${BASE_DIR}/shared/ca-key.pem \
    -config=${BASE_DIR}/shared/ca-config.json \
    -profile=kubernetes \
    ${BASE_DIR}/apiserver-etcd-client/apiserver-etcd-client-csr.json | cfssljson -bare ${BASE_DIR}/apiserver-etcd-client/apiserver-etcd-client
}

# 12. Generar certificados para apiserver-kubelet-client
generate_apiserver_kubelet_client_certificate() {
    echo "Generando certificado apiserver-kubelet-client..."
  cat > ${BASE_DIR}/apiserver/apiserver-kubelet-client-csr.json <<EOF
{
  "CN": "apiserver-kubelet-client",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "system:masters",
      "OU": "Kubernetes",
      "L": "Madrid",
      "ST": "Madrid",
      "C": "ES"
    }
  ]
}
EOF
    
    cfssl gencert \
    -ca=${BASE_DIR}/shared/ca.pem \
    -ca-key=${BASE_DIR}/shared/ca-key.pem \
    -config=${BASE_DIR}/shared/ca-config.json \
    -profile=kubernetes \
    ${BASE_DIR}/apiserver/apiserver-kubelet-client-csr.json | cfssljson -bare ${BASE_DIR}/apiserver/apiserver-kubelet-client
}

# 13. Generar certificado bootstrap de kubelet
generate_kubelet_bootstrap_certificate() {
    echo "Generando certificado bootstrap de kubelet..."
    cat > ${BASE_DIR}/kubelet/kubelet-bootstrap-csr.json <<EOF
{
  "CN": "system:bootstrap",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "system:bootstrappers",
      "L": "Madrid",
      "ST": "Madrid",
      "C": "ES"
    }
  ]
}
EOF
    
    cfssl gencert \
    -ca=${BASE_DIR}/shared/ca.pem \
    -ca-key=${BASE_DIR}/shared/ca-key.pem \
    -config=${BASE_DIR}/shared/ca-config.json \
    -profile=kubernetes \
    ${BASE_DIR}/kubelet/kubelet-bootstrap-csr.json | cfssljson -bare ${BASE_DIR}/kubelet/kubelet-bootstrap
}

# Llamar a todas las funciones
remove_existing_certificates
generate_ca_config
generate_ca_certificate
generate_admin_certificate
generate_kubelet_certificates
generate_apiserver_certificate
generate_etcd_certificates
generate_kube_controller_manager_certificate
generate_kube_scheduler_certificate
generate_kube_proxy_certificate
generate_service_account_certificates
generate_apiserver_etcd_client_certificate
generate_apiserver_kubelet_client_certificate
generate_kubelet_bootstrap_certificate

echo "Todos los certificados han sido generados exitosamente."

# Ajustar permisos de los archivos
sudo chmod -R 755 ${BASE_DIR}
sudo chown -R core:core ${BASE_DIR}
sudo find ${BASE_DIR}/ -name "*.pem" -exec chmod 644 {} \;
sudo find ${BASE_DIR}/ -name "*-key.pem" -exec chmod 600 {} \;
sudo chown -R root:root ${BASE_DIR}

# Ajustar permisos de directorios
sudo chmod -R 755 /home/core/nginx-docker/certificates

# Ajustar permisos para todos los archivos .pem
sudo find /home/core/nginx-docker/certificates -name "*.pem" -exec chmod 644 {} \;

# Ajustar permisos para todas las claves privadas (-key.pem)
sudo find /home/core/nginx-docker/certificates -name "*-key.pem" -exec chmod 600 {} \;

# Establecer el propietario como root para todos los archivos y directorios
sudo chown -R root:root /home/core/nginx-docker/certificates

# Asegurarse de que el usuario core sea el propietario de los archivos en etcd
sudo chown core:core /home/core/nginx-docker/certificates/etcd/*.pem

sudo chmod 644 /home/core/nginx-docker/certificates/sa/sa-key.pem
sudo chmod 644 /home/core/nginx-docker/certificates/sa/sa.pem
sudo find /home/core/nginx-docker/certificates/ -type d -exec chmod 755 {} \;
sudo chmod -R 644 /home/core/nginx-docker/certificates/*
sudo chown -R root:root /home/core/nginx-docker/certificates/*

# Asigna permisos de lectura a todos los archivos dentro del directorio certificates
sudo find /home/core/nginx-docker/certificates/ -type f -exec chmod 644 {} \;

# Asigna permisos de ejecución (lectura de directorio) a todos los directorios
sudo find /home/core/nginx-docker/certificates/ -type d -exec chmod 755 {} \;

# Cambia el propietario de todos los archivos y directorios a 'root'
sudo chown -R root:root /home/core/nginx-docker/certificates/

sudo chmod 755 /home
sudo chmod 755 /home/core
sudo chmod 755 /home/core/nginx-docker

echo "Permisos ajustados correctamente."