#!/bin/bash

# Variables
NODES=("bootstrap" "master1" "master2" "master3" "worker1" "worker2" "worker3")
MASTER_IPS=("10.17.4.21" "10.17.4.22" "10.17.4.23")

# 1. Create Directory Structure
echo "Creating directory structure..."
sudo mkdir -p /opt/nginx/certificates/{bootstrap,master1,master2,master3,worker1,worker2,worker3}/kubelet
sudo mkdir -p /opt/nginx/certificates/shared/{ca,apiserver,etcd,sa,apiserver-etcd-client,apiserver-kubelet-client,kube-scheduler}

# 2. Generate CA Certificate (Shared Certificates)
echo "Generating CA certificate..."
sudo openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/ca/ca.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -x509 -new -key /opt/nginx/certificates/shared/ca/ca.key -subj "/CN=Kubernetes-CA" -days 3650 -out /opt/nginx/certificates/shared/ca/ca.crt

# 3. Generate Kubelet Certificates for All Nodes
echo "Generating Kubelet certificates for all nodes..."
for NODE in "${NODES[@]}"; do
    sudo openssl genpkey -algorithm RSA -out /opt/nginx/certificates/${NODE}/kubelet/kubelet.key -pkeyopt rsa_keygen_bits:2048
    sudo openssl req -new -key /opt/nginx/certificates/${NODE}/kubelet/kubelet.key -subj "/CN=system:node:${NODE}/O=system:nodes" -out /opt/nginx/certificates/${NODE}/kubelet/kubelet.csr
    sudo openssl x509 -req -in /opt/nginx/certificates/${NODE}/kubelet/kubelet.csr -CA /opt/nginx/certificates/shared/ca/ca.crt -CAkey /opt/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /opt/nginx/certificates/${NODE}/kubelet/kubelet.crt -days 365
done

# 4. Generate Shared Certificates
echo "Generating shared certificates..."

# API Server Certificate
sudo openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/apiserver/apiserver.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key /opt/nginx/certificates/shared/apiserver/apiserver.key -subj "/CN=kube-apiserver" -out /opt/nginx/certificates/shared/apiserver/apiserver.csr
sudo openssl x509 -req -in /opt/nginx/certificates/shared/apiserver/apiserver.csr -CA /opt/nginx/certificates/shared/ca/ca.crt -CAkey /opt/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /opt/nginx/certificates/shared/apiserver/apiserver.crt -days 365

# Service Account Key Pair
echo "Generating Service Account key pair..."
sudo openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/sa/sa.key -pkeyopt rsa_keygen_bits:2048
sudo openssl rsa -in /opt/nginx/certificates/shared/sa/sa.key -pubout -out /opt/nginx/certificates/shared/sa/sa.pub

# Etcd Server Certificate
sudo openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/etcd/etcd.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key /opt/nginx/certificates/shared/etcd/etcd.key -subj "/CN=etcd" -out /opt/nginx/certificates/shared/etcd/etcd.csr
sudo openssl x509 -req -in /opt/nginx/certificates/shared/etcd/etcd.csr -CA /opt/nginx/certificates/shared/ca/ca.crt -CAkey /opt/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /opt/nginx/certificates/shared/etcd/etcd.crt -days 365

# API Server Etcd Client Certificates
sudo openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key /opt/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.key -subj "/CN=apiserver-etcd-client" -out /opt/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.csr
sudo openssl x509 -req -in /opt/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.csr -CA /opt/nginx/certificates/shared/ca/ca.crt -CAkey /opt/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /opt/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.crt -days 365

# API Server Kubelet Client Certificate
sudo openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key /opt/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.key -subj "/CN=kube-apiserver-kubelet-client" -out /opt/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.csr
sudo openssl x509 -req -in /opt/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.csr -CA /opt/nginx/certificates/shared/ca/ca.crt -CAkey /opt/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /opt/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.crt -days 365

# 5. Generate etcd-openssl.cnf for Each Master Node
echo "Generating etcd-openssl.cnf for each master node..."

for i in {1..3}; do
  cat <<EOF | sudo tee /opt/nginx/certificates/shared/etcd-openssl-${NODES[i]}.cnf
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
done

echo "Process completed."

# 6. Generate the Certificate for kube-scheduler
echo "Generating kube-scheduler certificate..."
sudo mkdir -p /opt/nginx/certificates/shared/kube-scheduler

if [ ! -d "/opt/nginx/certificates/shared/kube-scheduler" ]; then
  echo "Error: Could not create directory for kube-scheduler"
  exit 1
fi

sudo openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/kube-scheduler/kube-scheduler.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key /opt/nginx/certificates/shared/kube-scheduler/kube-scheduler.key -subj "/CN=system:kube-scheduler" -out /opt/nginx/certificates/shared/kube-scheduler/kube-scheduler.csr
sudo openssl x509 -req -in /opt/nginx/certificates/shared/kube-scheduler/kube-scheduler.csr -CA /opt/nginx/certificates/shared/ca/ca.crt -CAkey /opt/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /opt/nginx/certificates/shared/kube-scheduler/kube-scheduler.crt -days 365

if [ -f "/opt/nginx/certificates/shared/kube-scheduler/kube-scheduler.key" ] && [ -f "/opt/nginx/certificates/shared/kube-scheduler/kube-scheduler.crt" ]; then
  sudo chmod 600 /opt/nginx/certificates/shared/kube-scheduler/kube-scheduler.key
  sudo chmod 644 /opt/nginx/certificates/shared/kube-scheduler/kube-scheduler.crt
  sudo chown root:root /opt/nginx/certificates/shared/kube-scheduler/kube-scheduler.*
else
  echo "Error: kube-scheduler certificate files not found"
  exit 1
fi

echo "All certificates have been generated successfully."