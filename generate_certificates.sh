#!/bin/bash

# Definir la ruta base para los certificados dentro del contenedor
BASE_DIR="/etc/nginx/certificates"

# Variables
NODES=("bootstrap" "master1" "master2" "master3" "worker1" "worker2" "worker3")
MASTER_IPS=("10.17.4.21" "10.17.4.22" "10.17.4.23")

# Crear la estructura de directorios
echo "Creating directory structure..."
mkdir -p ${BASE_DIR}/{shared/ca,shared/apiserver,shared/etcd,shared/sa,shared/apiserver-etcd-client,shared/apiserver-kubelet-client,shared/kube-scheduler}
for NODE in "${NODES[@]}"; do
    mkdir -p ${BASE_DIR}/${NODE}/kubelet
done

# 1. Generar el certificado de la CA (Certificado compartido)
echo "Generating CA certificate..."
openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/ca/ca.key -pkeyopt rsa_keygen_bits:2048
openssl req -x509 -new -key ${BASE_DIR}/shared/ca/ca.key -subj "/CN=Kubernetes-CA" -days 3650 -out ${BASE_DIR}/shared/ca/ca.crt

# 2. Generar el certificado para kubernetes-admin
echo "Generating kubernetes-admin certificate..."
cat <<EOF | tee ${BASE_DIR}/shared/kubernetes-admin/admin-openssl.cnf
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

openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/kubernetes-admin/admin.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key ${BASE_DIR}/shared/kubernetes-admin/admin.key -out ${BASE_DIR}/shared/kubernetes-admin/admin.csr -config ${BASE_DIR}/shared/kubernetes-admin/admin-openssl.cnf
openssl x509 -req -in ${BASE_DIR}/shared/kubernetes-admin/admin.csr -CA ${BASE_DIR}/shared/ca/ca.crt -CAkey ${BASE_DIR}/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/shared/kubernetes-admin/admin.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/shared/kubernetes-admin/admin-openssl.cnf

# 3. Generar certificados Kubelet para todos los nodos
echo "Generating Kubelet certificates for all nodes..."
for NODE in "${NODES[@]}"; do
  cat <<EOF | tee ${BASE_DIR}/shared/kubelet-${NODE}-openssl.cnf
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

  openssl genpkey -algorithm RSA -out ${BASE_DIR}/${NODE}/kubelet/kubelet.key -pkeyopt rsa_keygen_bits:2048
  openssl req -new -key ${BASE_DIR}/${NODE}/kubelet/kubelet.key -out ${BASE_DIR}/${NODE}/kubelet/kubelet.csr -config ${BASE_DIR}/shared/kubelet-${NODE}-openssl.cnf
  openssl x509 -req -in ${BASE_DIR}/${NODE}/kubelet/kubelet.csr -CA ${BASE_DIR}/shared/ca/ca.crt -CAkey ${BASE_DIR}/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/${NODE}/kubelet/kubelet.crt -days 365 -extensions req_ext -extfile ${BASE_DIR}/shared/kubelet-${NODE}-openssl.cnf
done

# 4. Generar el certificado del API Server
echo "Generating API Server certificate..."
cat <<EOF | tee ${BASE_DIR}/shared/apiserver/apiserver-openssl.cnf
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
IP.2 = ${MASTER_IPS[0]}
IP.3 = ${MASTER_IPS[1]}
IP.4 = ${MASTER_IPS[2]}
EOF

openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/apiserver/apiserver.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key ${BASE_DIR}/shared/apiserver/apiserver.key -out ${BASE_DIR}/shared/apiserver/apiserver.csr -config ${BASE_DIR}/shared/apiserver/apiserver-openssl.cnf
openssl x509 -req -in ${BASE_DIR}/shared/apiserver/apiserver.csr -CA ${BASE_DIR}/shared/ca/ca.crt -CAkey ${BASE_DIR}/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/shared/apiserver/apiserver.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/shared/apiserver/apiserver-openssl.cnf

# 5. Generar el par de llaves para la Service Account
echo "Generating Service Account key pair..."
openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/sa/sa.key -pkeyopt rsa_keygen_bits:2048
openssl rsa -in ${BASE_DIR}/shared/sa/sa.key -pubout -out ${BASE_DIR}/shared/sa/sa.pub

# 6. Generar certificados del servidor Etcd
echo "Generating Etcd certificates..."
for i in {0..2}; do
  cat <<EOF | tee ${BASE_DIR}/shared/etcd/etcd-openssl-${NODES[i]}.cnf
[ req ]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[ req_distinguished_name ]
CN = etcd

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[ alt_names ]
IP.1 = 127.0.0.1
IP.2 = ${MASTER_IPS[0]}
IP.3 = ${MASTER_IPS[1]}
IP.4 = ${MASTER_IPS[2]}
EOF

  openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/etcd/etcd-${NODES[i]}.key -pkeyopt rsa_keygen_bits:2048
  openssl req -new -key ${BASE_DIR}/shared/etcd/etcd-${NODES[i]}.key -config ${BASE_DIR}/shared/etcd/etcd-openssl-${NODES[i]}.cnf -out ${BASE_DIR}/shared/etcd/etcd-${NODES[i]}.csr
  openssl x509 -req -in ${BASE_DIR}/shared/etcd/etcd-${NODES[i]}.csr -CA ${BASE_DIR}/shared/ca/ca.crt -CAkey ${BASE_DIR}/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/shared/etcd/etcd-${NODES[i]}.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/shared/etcd/etcd-openssl-${NODES[i]}.cnf
done

# 7. Generar certificados de cliente para el API Server de Etcd
echo "Generating API Server Etcd client certificate..."
openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/apiserver-etcd-client/apiserver-etcd-client.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key ${BASE_DIR}/shared/apiserver-etcd-client/apiserver-etcd-client.key -subj "/CN=apiserver-etcd-client" -out ${BASE_DIR}/shared/apiserver-etcd-client/apiserver-etcd-client.csr
openssl x509 -req -in ${BASE_DIR}/shared/apiserver-etcd-client/apiserver-etcd-client.csr -CA ${BASE_DIR}/shared/ca/ca.crt -CAkey ${BASE_DIR}/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/shared/apiserver-etcd-client/apiserver-etcd-client.crt -days 365

# 8. Generar el certificado del cliente Kubelet del API Server
echo "Generating API Server Kubelet client certificate..."
openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/apiserver-kubelet-client/apiserver-kubelet-client.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key ${BASE_DIR}/shared/apiserver-kubelet-client/apiserver-kubelet-client.key -subj "/CN=kube-apiserver-kubelet-client" -out ${BASE_DIR}/shared/apiserver-kubelet-client/apiserver-kubelet-client.csr
openssl x509 -req -in ${BASE_DIR}/shared/apiserver-kubelet-client/apiserver-kubelet-client.csr -CA ${BASE_DIR}/shared/ca/ca.crt -CAkey ${BASE_DIR}/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/shared/apiserver-kubelet-client/apiserver-kubelet-client.crt -days 365

# 9. Generar el certificado para kube-scheduler
echo "Generating kube-scheduler certificate..."
openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/kube-scheduler/kube-scheduler.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key ${BASE_DIR}/shared/kube-scheduler/kube-scheduler.key -subj "/CN=system:kube-scheduler" -out ${BASE_DIR}/shared/kube-scheduler/kube-scheduler.csr
openssl x509 -req -in ${BASE_DIR}/shared/kube-scheduler/kube-scheduler.csr -CA ${BASE_DIR}/shared/ca/ca.crt -CAkey ${BASE_DIR}/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/shared/kube-scheduler/kube-scheduler.crt -days 365

# 10. Generar el certificado para Kube-proxy
echo "Generating Kube-proxy certificate..."
cat <<EOF | tee ${BASE_DIR}/shared/kube-proxy/kube-proxy-openssl.cnf
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

openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/kube-proxy/kube-proxy.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key ${BASE_DIR}/shared/kube-proxy/kube-proxy.key -out ${BASE_DIR}/shared/kube-proxy/kube-proxy.csr -config ${BASE_DIR}/shared/kube-proxy/kube-proxy-openssl.cnf
openssl x509 -req -in ${BASE_DIR}/shared/kube-proxy/kube-proxy.csr -CA ${BASE_DIR}/shared/ca/ca.crt -CAkey ${BASE_DIR}/shared/ca/ca.key -CAcreateserial -out ${BASE_DIR}/shared/kube-proxy/kube-proxy.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/shared/kube-proxy/kube-proxy-openssl.cnf

echo "All certificates have been generated successfully."