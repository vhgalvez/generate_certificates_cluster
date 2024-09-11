#!/bin/bash

# Define the base directory for the certificates
BASE_DIR="/home/core/nginx-docker/certificates"
LOG_FILE="${BASE_DIR}/generate_certificates.log"

# Create a log file
exec > >(tee -i ${LOG_FILE})
exec 2>&1
set -e  # Stop the script on error

# Variables
NODES=("master1" "master2" "master3" "worker1" "worker2" "worker3")
MASTER_IPS=("10.17.4.21" "10.17.4.22" "10.17.4.23")

# Create the directory structure
echo "Creating directory structure..."
sudo mkdir -p ${BASE_DIR}/{shared,sa,kubelet,apiserver,etcd,apiserver-etcd-client,kube-controller-manager,kube-scheduler,kube-proxy}

# Function to remove existing certificates
remove_existing_certificates() {
  echo "Removing existing certificates if they exist..."   
  sudo rm -f ${BASE_DIR}/shared/ca.crt ${BASE_DIR}/shared/admin.crt ${BASE_DIR}/kubelet/*.crt ${BASE_DIR}/apiserver/apiserver.crt ${BASE_DIR}/etcd/etcd.crt
}

# 1. Generate CA certificate
generate_ca_certificate() {
  echo "Generating CA certificate..."
  sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/ca.key -pkeyopt rsa_keygen_bits:2048
  sudo openssl req -x509 -new -key ${BASE_DIR}/shared/ca.key -subj "/CN=Kubernetes-CA" -days 3650 -out ${BASE_DIR}/shared/ca.crt
}

# 2. Generate Kubernetes Admin certificate
generate_admin_certificate() {
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
}

# 3. Generate Kubelet certificates for all nodes
generate_kubelet_certificates() {
  for NODE in "${NODES[@]}"; do
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
  done
}

# 4. Generate API Server certificate
generate_apiserver_certificate() {
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
}

# 5. Generate etcd certificates
generate_etcd_certificates() {
  echo "Generating etcd certificates..."
  # Define your etcd certificate generation logic here
}

# Remove existing certificates, then regenerate them
remove_existing_certificates
generate_ca_certificate
generate_admin_certificate
generate_kubelet_certificates
generate_apiserver_certificate
generate_etcd_certificates

# Clean up temporary files
rm -f /tmp/kubelet-*.cnf

echo "All certificates have been regenerated successfully."