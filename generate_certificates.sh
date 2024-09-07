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

# 2. Generar certificado para kubernetes-admin
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

# 3. Generar certificados Kubelet para todos los nodos
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

# 4. Generar certificado del API Server
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

# 5. Generar certificados para Etcd
generate_etcd_certificates() {
  if [ ! -f "${BASE_DIR}/etcd/etcd.crt" ]; then
    echo "Generating Etcd certificates..."
    cat <<EOF | sudo tee ${BASE_DIR}/etcd/etcd-openssl.cnf
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = v3_req

[ dn ]
CN = etcd

[ v3_req ]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = etcd
IP.1 = ${MASTER_IPS[0]}
IP.2 = ${MASTER_IPS[1]}
EOF

    sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/etcd/etcd.key -pkeyopt rsa_keygen_bits:2048
    sudo openssl req -new -key ${BASE_DIR}/etcd/etcd.key -out ${BASE_DIR}/etcd/etcd.csr -config ${BASE_DIR}/etcd/etcd-openssl.cnf
    sudo openssl x509 -req -in ${BASE_DIR}/etcd/etcd.csr -CA ${BASE_DIR}/shared/ca.crt -CAkey ${BASE_DIR}/shared/ca.key -CAcreateserial -out ${BASE_DIR}/etcd/etcd.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/etcd/etcd-openssl.cnf
  else
    echo "Etcd certificate already exists. Skipping..."
  fi
}

# 6. Generar certificado de cliente del API server para etcd
generate_apiserver_etcd_client_certificate() {
  if [ ! -f "${BASE_DIR}/apiserver-etcd-client/apiserver-etcd-client.crt" ]; then
    echo "Generating Etcd client certificate for API server..."
    cat <<EOF | sudo tee ${BASE_DIR}/apiserver-etcd-client/etcd-client-openssl.cnf
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = v3_req

[ dn ]
CN = apiserver-etcd-client

[ v3_req ]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

    sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/apiserver-etcd-client/apiserver-etcd-client.key -pkeyopt rsa_keygen_bits:2048
    sudo openssl req -new -key ${BASE_DIR}/apiserver-etcd-client/apiserver-etcd-client.key -out ${BASE_DIR}/apiserver-etcd-client/apiserver-etcd-client.csr -config ${BASE_DIR}/apiserver-etcd-client/etcd-client-openssl.cnf
    sudo openssl x509 -req -in ${BASE_DIR}/apiserver-etcd-client/apiserver-etcd-client.csr -CA ${BASE_DIR}/shared/ca.crt -CAkey ${BASE_DIR}/shared/ca.key -CAcreateserial -out ${BASE_DIR}/apiserver-etcd-client/apiserver-etcd-client.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/apiserver-etcd-client/etcd-client-openssl.cnf
  else
    echo "Etcd client certificate for API server already exists. Skipping..."
  fi
}

# 7. Generar clave de Service Account
generate_sa_keys() {
  if [ ! -f "${BASE_DIR}/shared/sa.key" ]; then
    echo "Generating Service Account keys..."
    sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/sa.key -pkeyopt rsa_keygen_bits:2048
    sudo openssl rsa -in ${BASE_DIR}/shared/sa.key -pubout -out ${BASE_DIR}/shared/sa.pub
  else
    echo "Service Account keys already exist. Skipping..."
  fi
}

# 8. Generar certificados para kube-controller-manager
generate_kube_controller_manager_certificates() {
  if [ ! -f "${BASE_DIR}/kube-controller-manager/kube-controller-manager.crt" ]; then
    echo "Generating kube-controller-manager certificates..."
    sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/kube-controller-manager/kube-controller-manager.key -pkeyopt rsa_keygen_bits:2048
    sudo openssl req -new -key ${BASE_DIR}/kube-controller-manager/kube-controller-manager.key -subj "/CN=system:kube-controller-manager" -out ${BASE_DIR}/kube-controller-manager/kube-controller-manager.csr
    sudo openssl x509 -req -in ${BASE_DIR}/kube-controller-manager/kube-controller-manager.csr -CA ${BASE_DIR}/shared/ca.crt -CAkey ${BASE_DIR}/shared/ca.key -CAcreateserial -out ${BASE_DIR}/kube-controller-manager/kube-controller-manager.crt -days 365
  else
    echo "kube-controller-manager certificates already exist. Skipping..."
  fi
}

# 9. Generar certificados para kube-scheduler
generate_kube_scheduler_certificates() {
  if [ ! -f "${BASE_DIR}/kube-scheduler/kube-scheduler.crt" ]; then
    echo "Generating kube-scheduler certificates..."
    sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/kube-scheduler/kube-scheduler.key -pkeyopt rsa_keygen_bits:2048
    sudo openssl req -new -key ${BASE_DIR}/kube-scheduler/kube-scheduler.key -subj "/CN=system:kube-scheduler" -out ${BASE_DIR}/kube-scheduler/kube-scheduler.csr
    sudo openssl x509 -req -in ${BASE_DIR}/kube-scheduler/kube-scheduler.csr -CA ${BASE_DIR}/shared/ca.crt -CAkey ${BASE_DIR}/shared/ca.key -CAcreateserial -out ${BASE_DIR}/kube-scheduler/kube-scheduler.crt -days 365
  else
    echo "kube-scheduler certificates already exist. Skipping..."
  fi
}

# 10. Generar certificados para kube-proxy
generate_kube_proxy_certificates() {
  if [ ! -f "${BASE_DIR}/kube-proxy/kube-proxy.crt" ]; then
    echo "Generating kube-proxy certificates..."
    sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/kube-proxy/kube-proxy.key -pkeyopt rsa_keygen_bits:2048
    sudo openssl req -new -key ${BASE_DIR}/kube-proxy/kube-proxy.key -subj "/CN=system:kube-proxy" -out ${BASE_DIR}/kube-proxy/kube-proxy.csr
    sudo openssl x509 -req -in ${BASE_DIR}/kube-proxy/kube-proxy.csr -CA ${BASE_DIR}/shared/ca.crt -CAkey ${BASE_DIR}/shared/ca.key -CAcreateserial -out ${BASE_DIR}/kube-proxy/kube-proxy.crt -days 365
  else
    echo "kube-proxy certificates already exist. Skipping..."
  fi
}

# Ejecutar las funciones
generate_ca_certificate
generate_admin_certificate
generate_kubelet_certificates
generate_apiserver_certificate
generate_etcd_certificates
generate_apiserver_etcd_client_certificate
generate_sa_keys
generate_kube_controller_manager_certificates
generate_kube_scheduler_certificates
generate_kube_proxy_certificates

# Eliminar archivos temporales
rm -f /tmp/kubelet-*.cnf

echo "All certificates have been generated successfully."
