#!/bin/bash

# Definir la ruta base para los certificados expuestos por el servidor web
BASE_DIR="/home/core/nginx-docker/certificates"

# Variables
NODES=("master1" "master2" "master3" "worker1" "worker2" "worker3")
MASTER_IPS=("10.17.4.21" "10.17.4.22" "10.17.4.23")

# Crear la estructura de directorios
echo "Creating directory structure..."
sudo mkdir -p ${BASE_DIR}/{shared,kubernetes-admin,kubelet,kube-proxy,apiserver,etcd,apiserver-etcd-client,apiserver-kubelet-client,kube-scheduler}

# 1. Generar el certificado de la CA (Certificado compartido)
echo "Generating CA certificate..."
sudo mkdir -p ${BASE_DIR}/shared/ca
sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/ca/ca.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -x509 -new -key ${BASE_DIR}/shared/ca/ca.key -subj "/CN=Kubernetes-CA" -days 3650 -out ${BASE_DIR}/shared/ca/ca.crt

# 2. Generar el certificado para kubernetes-admin
echo "Generating kubernetes-admin certificate..."
sudo mkdir -p ${BASE_DIR}/shared/kubernetes-admin
cat <<EOF | sudo tee ${BASE_DIR}/shared/kubernetes-admin/admin-openssl.cnf
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

sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/kubernetes-admin/admin.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key ${BASE_DIR}/shared/kubernetes-admin/admin.key -out ${BASE_DIR}/shared/kubernetes-admin/admin.csr -config ${BASE_DIR}/shared/kubernetes-admin/admin-openssl.cnf
sudo openssl x509 -req -in ${BASE_DIR}/shared/kubernetes-admin/admin.csr -CA ${BASE_DIR}/shared/ca/ca.crt -CAkey ${BASE_DIR}/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/shared/kubernetes-admin/admin.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/shared/kubernetes-admin/admin-openssl.cnf

# 3. Generar certificados Kubelet para todos los nodos
echo "Generating Kubelet certificates for all nodes..."
for NODE in "${NODES[@]}"; do
  sudo mkdir -p ${BASE_DIR}/${NODE}/kubelet
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

  sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/${NODE}/kubelet/kubelet.key -pkeyopt rsa_keygen_bits:2048
  sudo openssl req -new -key ${BASE_DIR}/${NODE}/kubelet/kubelet.key -out ${BASE_DIR}/${NODE}/kubelet/kubelet.csr -config /tmp/kubelet-${NODE}-openssl.cnf
  sudo openssl x509 -req -in ${BASE_DIR}/${NODE}/kubelet/kubelet.csr -CA ${BASE_DIR}/shared/ca/ca.crt -CAkey ${BASE_DIR}/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/${NODE}/kubelet/kubelet.crt -days 365 -extensions req_ext -extfile /tmp/kubelet-${NODE}-openssl.cnf
done

# 4. Generar el certificado del API Server
echo "Generating API Server certificate..."
sudo mkdir -p ${BASE_DIR}/shared/apiserver
cat <<EOF | sudo tee ${BASE_DIR}/shared/apiserver/apiserver-openssl.cnf
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
DNS.2 = kube-apiserver.kube-system
DNS.3 = master1
DNS.4 = master1.cefaslocalserver.com
IP.1 = 127.0.0.1
IP.2 = 10.17.4.21
IP.3 = 10.17.4.22
IP.4 = 10.17.4.23
EOF

sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/apiserver/apiserver.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key ${BASE_DIR}/shared/apiserver/apiserver.key -out ${BASE_DIR}/shared/apiserver/apiserver.csr -config ${BASE_DIR}/shared/apiserver/apiserver-openssl.cnf
sudo openssl x509 -req -in ${BASE_DIR}/shared/apiserver/apiserver.csr -CA ${BASE_DIR}/shared/ca/ca.crt -CAkey ${BASE_DIR}/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/shared/apiserver/apiserver.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/shared/apiserver/apiserver-openssl.cnf

# 5. Generar el certificado para Kube-proxy
echo "Generating Kube-proxy certificate..."
sudo mkdir -p ${BASE_DIR}/shared/kube-proxy
cat <<EOF | sudo tee ${BASE_DIR}/shared/kube-proxy/kube-proxy-openssl.cnf
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = v3_req

[ dn ]
CN = system:kube-proxy

[ v3_req ]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/kube-proxy/kube-proxy.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key ${BASE_DIR}/shared/kube-proxy/kube-proxy.key -out ${BASE_DIR}/shared/kube-proxy/kube-proxy.csr -config ${BASE_DIR}/shared/kube-proxy/kube-proxy-openssl.cnf
sudo openssl x509 -req -in ${BASE_DIR}/shared/kube-proxy/kube-proxy.csr -CA ${BASE_DIR}/shared/ca/ca.crt -CAkey ${BASE_DIR}/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/shared/kube-proxy/kube-proxy.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/shared/kube-proxy/kube-proxy-openssl.cnf

echo "All certificates have been generated successfully."
