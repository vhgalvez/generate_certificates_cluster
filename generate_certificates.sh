#!/bin/bash

# Definir la ruta base
BASE_DIR="/home/core/nginx-docker"

# Variables
NODES=("bootstrap" "master1" "master2" "master3" "worker1" "worker2" "worker3")
MASTER_IPS=("10.17.4.21" "10.17.4.22" "10.17.4.23")

# 1. Crear la estructura de directorios
echo "Creating directory structure..."
sudo mkdir -p ${BASE_DIR}/certificates/{bootstrap,master1,master2,master3,worker1,worker2,worker3}/kubelet
sudo mkdir -p ${BASE_DIR}/certificates/shared/{ca,apiserver,etcd,sa,apiserver-etcd-client,apiserver-kubelet-client,kube-scheduler}

# 2. Generar el certificado de la CA (Certificados compartidos)
echo "Generating CA certificate..."
sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/certificates/shared/ca/ca.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -x509 -new -key ${BASE_DIR}/certificates/shared/ca/ca.key -subj "/CN=Kubernetes-CA" -days 3650 -out ${BASE_DIR}/certificates/shared/ca/ca.crt

# 3. Generar los certificados Kubelet para todos los nodos
echo "Generating Kubelet certificates for all nodes..."
for NODE in "${NODES[@]}"; do
    sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/certificates/${NODE}/kubelet/kubelet.key -pkeyopt rsa_keygen_bits:2048
    sudo openssl req -new -key ${BASE_DIR}/certificates/${NODE}/kubelet/kubelet.key -subj "/CN=system:node:${NODE}/O=system:nodes" -out ${BASE_DIR}/certificates/${NODE}/kubelet/kubelet.csr
    sudo openssl x509 -req -in ${BASE_DIR}/certificates/${NODE}/kubelet/kubelet.csr -CA ${BASE_DIR}/certificates/shared/ca/ca.crt -CAkey ${BASE_DIR}/certificates/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/certificates/${NODE}/kubelet/kubelet.crt -days 365
done

# 4. Generar certificados compartidos
echo "Generating shared certificates..."

# Certificado del API Server
sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/certificates/shared/apiserver/apiserver.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key ${BASE_DIR}/certificates/shared/apiserver/apiserver.key -subj "/CN=kube-apiserver" -out ${BASE_DIR}/certificates/shared/apiserver/apiserver.csr
sudo openssl x509 -req -in ${BASE_DIR}/certificates/shared/apiserver/apiserver.csr -CA ${BASE_DIR}/certificates/shared/ca/ca.crt -CAkey ${BASE_DIR}/certificates/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/certificates/shared/apiserver/apiserver.crt -days 365

# Par de llaves de cuenta de servicio (Service Account)
echo "Generating Service Account key pair..."
sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/certificates/shared/sa/sa.key -pkeyopt rsa_keygen_bits:2048
sudo openssl rsa -in ${BASE_DIR}/certificates/shared/sa/sa.key -pubout -out ${BASE_DIR}/certificates/shared/sa/sa.pub

# Certificado del servidor Etcd con SANs
echo "Generating Etcd certificate with SANs..."
for i in {0..2}; do
  cat <<EOF | sudo tee ${BASE_DIR}/certificates/shared/etcd-openssl-${NODES[i]}.cnf
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = etcd

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
IP.1 = 127.0.0.1
IP.2 = ${MASTER_IPS[0]}
IP.3 = ${MASTER_IPS[1]}
IP.4 = ${MASTER_IPS[2]}
EOF

  sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/certificates/shared/etcd/etcd-${NODES[i]}.key -pkeyopt rsa_keygen_bits:2048
  sudo openssl req -new -key ${BASE_DIR}/certificates/shared/etcd/etcd-${NODES[i]}.key -config ${BASE_DIR}/certificates/shared/etcd-openssl-${NODES[i]}.cnf -out ${BASE_DIR}/certificates/shared/etcd/etcd-${NODES[i]}.csr
  sudo openssl x509 -req -in ${BASE_DIR}/certificates/shared/etcd/etcd-${NODES[i]}.csr -CA ${BASE_DIR}/certificates/shared/ca/ca.crt -CAkey ${BASE_DIR}/certificates/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/certificates/shared/etcd/etcd-${NODES[i]}.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/certificates/shared/etcd-openssl-${NODES[i]}.cnf
done

# Certificados de cliente del API Server Etcd
sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key ${BASE_DIR}/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.key -subj "/CN=apiserver-etcd-client" -out ${BASE_DIR}/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.csr
sudo openssl x509 -req -in ${BASE_DIR}/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.csr -CA ${BASE_DIR}/certificates/shared/ca/ca.crt -CAkey ${BASE_DIR}/certificates/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.crt -days 365

# Certificado del cliente Kubelet del API Server
sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key ${BASE_DIR}/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.key -subj "/CN=kube-apiserver-kubelet-client" -out ${BASE_DIR}/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.csr
sudo openssl x509 -req -in ${BASE_DIR}/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.csr -CA ${BASE_DIR}/certificates/shared/ca/ca.crt -CAkey ${BASE_DIR}/certificates/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.crt -days 365

# 6. Generar el certificado para kube-scheduler
echo "Generating kube-scheduler certificate..."
sudo mkdir -p ${BASE_DIR}/certificates/shared/kube-scheduler

if [ ! -d "${BASE_DIR}/certificates/shared/kube-scheduler" ]; then
  echo "Error: Could not create directory for kube-scheduler"
  exit 1
fi

sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/certificates/shared/kube-scheduler/kube-scheduler.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key ${BASE_DIR}/certificates/shared/kube-scheduler/kube-scheduler.key -subj "/CN=system:kube-scheduler" -out ${BASE_DIR}/certificates/shared/kube-scheduler/kube-scheduler.csr
sudo openssl x509 -req -in ${BASE_DIR}/certificates/shared/kube-scheduler/kube-scheduler.csr -CA ${BASE_DIR}/certificates/shared/ca/ca.crt -CAkey ${BASE_DIR}/certificates/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/certificates/shared/kube-scheduler/kube-scheduler.crt -days 365

if [ -f "${BASE_DIR}/certificates/shared/kube-scheduler/kube-scheduler.key" ] && [ -f "${BASE_DIR}/certificates/shared/kube-scheduler/kube-scheduler.crt" ]; then
  sudo chmod 600 ${BASE_DIR}/certificates/shared/kube-scheduler/kube-scheduler.key
  sudo chmod 644 ${BASE_DIR}/certificates/shared/kube-scheduler/kube-scheduler.crt
  sudo chown root:root ${BASE_DIR}/certificates/shared/kube-scheduler/kube-scheduler.*
else
  echo "Error: kube-scheduler certificate files not found"
  exit 1
fi

echo "All certificates have been generated successfully."
