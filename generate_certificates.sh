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
ETCD_NODE="10.17.4.23"  # Assuming etcd runs on this IP, modify as needed

# Create the directory structure
echo "Creating directory structure..."
sudo mkdir -p ${BASE_DIR}/{shared,sa,kubelet,apiserver,etcd,apiserver-etcd-client,kube-controller-manager,kube-scheduler,kube-proxy}

# Function to remove existing certificates
remove_existing_certificates() {
  echo "Removing existing certificates if they exist..."
  sudo rm -f ${BASE_DIR}/shared/ca.crt ${BASE_DIR}/shared/admin.crt ${BASE_DIR}/kubelet/*.crt ${BASE_DIR}/apiserver/apiserver.crt ${BASE_DIR}/etcd/etcd.crt ${BASE_DIR}/apiserver-etcd-client/*.crt
}

# 1. Generate CA certificate (shared)
generate_ca_certificate() {
  echo "Generating CA certificate..."
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

# 2. Generate Kubernetes Admin certificate (shared)
generate_admin_certificate() {
  echo "Generating kubernetes-admin certificate..."
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

# 3. Generate Kubelet certificates for all nodes (individual)
generate_kubelet_certificates() {
  for NODE in "${NODES[@]}"; do
    echo "Generating Kubelet certificate for ${NODE}..."
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
      -hostname=${NODE},${MASTER_IPS[0]} \
      -profile=kubernetes \
      ${BASE_DIR}/kubelet/kubelet-${NODE}-csr.json | cfssljson -bare ${BASE_DIR}/kubelet/${NODE}
  done
}

# 4. Generate API Server certificate (shared)
generate_apiserver_certificate() {
  echo "Generating API Server certificate..."
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
    -hostname=127.0.0.1,${MASTER_IPS[0]},${MASTER_IPS[1]},${MASTER_IPS[2]} \
    -profile=kubernetes \
    ${BASE_DIR}/apiserver/apiserver-csr.json | cfssljson -bare ${BASE_DIR}/apiserver/apiserver
}

# 5. Generate etcd certificates (individual)
generate_etcd_certificates() {
  echo "Generating etcd certificates..."
  cat > ${BASE_DIR}/etcd/etcd-csr.json <<EOF
{
  "CN": "etcd",
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
    -hostname=127.0.0.1,${ETCD_NODE} \
    -profile=kubernetes \
    ${BASE_DIR}/etcd/etcd-csr.json | cfssljson -bare ${BASE_DIR}/etcd/etcd
}

# 6. Generate apiserver-etcd-client certificates (shared)
generate_apiserver_etcd_client_certificates() {
  echo "Generating apiserver-etcd-client certificates..."
  cat > ${BASE_DIR}/apiserver-etcd-client/apiserver-etcd-client-csr.json <<EOF
{
  "CN": "apiserver-etcd-client",
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
    -profile=kubernetes \
    ${BASE_DIR}/apiserver-etcd-client/apiserver-etcd-client-csr.json | cfssljson -bare ${BASE_DIR}/apiserver-etcd-client/apiserver-etcd-client
}

# 7. Generate kube-scheduler and kube-controller-manager certificates (individual)
generate_scheduler_and_controller_certificates() {
  echo "Generating kube-scheduler and kube-controller-manager certificates..."
  # kube-scheduler
  cat > ${BASE_DIR}/kube-scheduler/kube-scheduler-csr.json <<EOF
{
  "CN": "kube-scheduler",
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
    -profile=kubernetes \
    ${BASE_DIR}/kube-scheduler/kube-scheduler-csr.json | cfssljson -bare ${BASE_DIR}/kube-scheduler/kube-scheduler

  # kube-controller-manager
  cat > ${BASE_DIR}/kube-controller-manager/kube-controller-manager-csr.json <<EOF
{
  "CN": "kube-controller-manager",
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
    -profile=kubernetes \
    ${BASE_DIR}/kube-controller-manager/kube-controller-manager-csr.json | cfssljson -bare ${BASE_DIR}/kube-controller-manager/kube-controller-manager
}

# Remove existing certificates, then regenerate them
remove_existing_certificates
generate_ca_certificate
generate_admin_certificate
generate_kubelet_certificates
generate_apiserver_certificate
generate_etcd_certificates
generate_apiserver_etcd_client_certificates
generate_scheduler_and_controller_certificates

echo "All certificates have been regenerated successfully."
