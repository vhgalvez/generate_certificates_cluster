#!/bin/bash

# Definir la ruta base para los certificados
BASE_DIR="/home/core/nginx-docker/certificates"
LOG_FILE="${BASE_DIR}/generate_certificates.log"

# Crear archivo de log
exec > >(tee -i ${LOG_FILE})
exec 2>&1
set -e  # Detener el script en caso de error

# Variables
NODES=("master1" "master2" "master3" "worker1" "worker2" "worker3")
MASTER_IPS=("10.17.4.21" "10.17.4.22" "10.17.4.23")

# Crear la estructura de directorios
echo "Creating directory structure..."
sudo mkdir -p ${BASE_DIR}/{shared,sa,kubelet,apiserver,etcd,apiserver-etcd-client,kube-controller-manager,kube-scheduler,kube-proxy}

# 1. Generar el certificado de la CA (Certificado compartido)
generate_ca_certificate() {
  if [ ! -f "${BASE_DIR}/shared/ca.crt" ]; then
    echo "Generating CA certificate..."
    sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/ca.key -pkeyopt rsa_keygen_bits:2048
    sudo openssl req -x509 -new -key ${BASE_DIR}/shared/ca.key -subj "/CN=Kubernetes-CA" -days 3650 -out ${BASE_DIR}/shared/ca.crt
  else
    echo "CA certificate already exists. Skipping..."
  fi
}

# 2. Generar certificado para kubernetes-admin (Certificado compartido)
generate_admin_certificate() {
  if [ ! -f "${BASE_DIR}/shared/admin.crt" ]; then
    echo "Generating kubernetes-admin certificate..."
    cat <<EOF | sudo tee ${BASE_DIR}/shared/admin-openssl.cnf
[ req ]
req_extensions = v3_req
distinguished_name = req_distinguished_name
prompt = no

[ req_distinguished_name ]
CN = kubernetes-admin
O = system:masters

[ v3_req ]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = clientAuth
EOF

    sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/admin.key -pkeyopt rsa_keygen_bits:2048
    sudo openssl req -new -key ${BASE_DIR}/shared/admin.key -out ${BASE_DIR}/shared/admin.csr -config ${BASE_DIR}/shared/admin-openssl.cnf
    sudo openssl x509 -req -in ${BASE_DIR}/shared/admin.csr -CA ${BASE_DIR}/shared/ca.crt -CAkey ${BASE_DIR}/shared/ca.key -CAcreateserial -out ${BASE_DIR}/shared/admin.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/shared/admin-openssl.cnf
  else
    echo "kubernetes-admin certificate already exists. Skipping..."
  fi
}

# 3. Generar certificados Kubelet para todos los nodos (Certificados compartidos)
generate_kubelet_certificates() {
  for NODE in "${NODES[@]}"; do
    if [ ! -f "${BASE_DIR}/kubelet/${NODE}.crt" ]; then
      echo "Generating Kubelet certificate for ${NODE}..."
      cat <<EOF | sudo tee /tmp/kubelet-${NODE}-openssl.cnf
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
req_extensions     = req_ext
distinguished_name = dn

[ dn ]
CN = system:node:${NODE}
O = system:nodes

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = ${NODE}
IP.1 = ${MASTER_IPS[0]}
EOF

      sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/kubelet/${NODE}.key -pkeyopt rsa_keygen_bits:2048
      sudo openssl req -new -key ${BASE_DIR}/kubelet/${NODE}.key -out ${BASE_DIR}/kubelet/${NODE}.csr -config /tmp/kubelet-${NODE}-openssl.cnf
      sudo openssl x509 -req -in ${BASE_DIR}/kubelet/${NODE}.csr -CA ${BASE_DIR}/shared/ca.crt -CAkey ${BASE_DIR}/shared/ca.key -CAcreateserial -out ${BASE_DIR}/kubelet/${NODE}.crt -days 365 -extensions req_ext -extfile /tmp/kubelet-${NODE}-openssl.cnf
    else
      echo "Kubelet certificate for ${NODE} already exists. Skipping..."
    fi
  done
}

# 4. Generar certificado del API Server (Solo en nodos master)
generate_apiserver_certificate() {
  if [ ! -f "${BASE_DIR}/apiserver/apiserver.crt" ]; then
    echo "Generating API Server certificate..."
    cat <<EOF | sudo tee ${BASE_DIR}/apiserver/apiserver-openssl.cnf
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = v3_req

[ dn ]
CN = kube-apiserver

[ v3_req ]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = kube-apiserver
IP.1 = 127.0.0.1
IP.2 = ${MASTER_IPS[0]}
IP.3 = ${MASTER_IPS[1]}
IP.4 = ${MASTER_IPS[2]}
EOF

    sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/apiserver/apiserver.key -pkeyopt rsa_keygen_bits:2048
    sudo openssl req -new -key ${BASE_DIR}/apiserver/apiserver.key -out ${BASE_DIR}/apiserver/apiserver.csr -config ${BASE_DIR}/apiserver/apiserver-openssl.cnf
    sudo openssl x509 -req -in ${BASE_DIR}/apiserver/apiserver.csr -CA ${BASE_DIR}/shared/ca.crt -CAkey ${BASE_DIR}/shared/ca.key -CAcreateserial -out ${BASE_DIR}/apiserver/apiserver.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/apiserver/apiserver-openssl.cnf
  else
    echo "API Server certificate already exists. Skipping..."
  fi
}

# 5. Generate etcd certificates
generate_etcd_certificates() {
  echo "Generating etcd certificates..."
  # Define your etcd certificate generation logic here
}

# Define other functions (e.g., for apiserver-etcd-client, sa keys, etc.)

# Ejecutar todas las funciones en orden
generate_ca_certificate
generate_admin_certificate
generate_kubelet_certificates
generate_apiserver_certificate
generate_etcd_certificates
# Add missing functions here

# Eliminar archivos temporales
rm -f /tmp/kubelet-*.cnf

echo "All certificates have been generated successfully."