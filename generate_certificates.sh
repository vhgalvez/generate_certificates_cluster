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
ETCD_NODE="10.17.4.23"  # Dirección IP de etcd
BOOTSTRAP_NODE="10.17.4.27"

# Crear la estructura de directorios
echo "Creando la estructura de directorios..."
sudo mkdir -p ${BASE_DIR}/{shared,sa,kubelet,apiserver,etcd,apiserver-etcd-client,kube-controller-manager,kube-scheduler,kube-proxy}

# Función para eliminar certificados existentes
remove_existing_certificates() {
  echo "Eliminando certificados existentes..."
  sudo rm -f ${BASE_DIR}/shared/ca.crt ${BASE_DIR}/shared/admin.crt ${BASE_DIR}/kubelet/*.crt ${BASE_DIR}/apiserver/*.crt ${BASE_DIR}/etcd/*.crt ${BASE_DIR}/apiserver-etcd-client/*.crt
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
    "size": 2048
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
    "size": 2048
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
  for NODE in "${NODES[@]}"; do
    echo "Generando certificado de Kubelet para ${NODE}..."
    cat > ${BASE_DIR}/kubelet/kubelet-${NODE}-csr.json <<EOF
{
  "CN": "system:node:${NODE}",
  "key": {
    "algo": "rsa",
    "size": 2048
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
      -hostname=${NODE},$(eval echo \$"${NODE^^}_IP") \
      -profile=kubernetes \
      ${BASE_DIR}/kubelet/kubelet-${NODE}-csr.json | cfssljson -bare ${BASE_DIR}/kubelet/${NODE}
  done
}

# 5. Generar certificados del servidor API
generate_apiserver_certificate() {
  echo "Generando certificado de servidor API..."
  cat > ${BASE_DIR}/apiserver/apiserver-csr.json <<EOF
{
  "CN": "kube-apiserver",
  "key": {
    "algo": "rsa",
    "size": 2048
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

# Llamar a todas las funciones
remove_existing_certificates
generate_ca_config
generate_ca_certificate
generate_admin_certificate
generate_kubelet_certificates
generate_apiserver_certificate

echo "Todos los certificados han sido generados exitosamente."
