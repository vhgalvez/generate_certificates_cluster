#!/bin/bash

# Variables
NODES=("bootstrap" "master1" "master2" "master3" "worker1" "worker2" "worker3")
MASTER_IPS=("10.17.4.21" "10.17.4.22" "10.17.4.23")

# 1. Crear la Estructura de Directorios
echo "Creando estructura de directorios..."
sudo mkdir -p /opt/nginx/certificates/{bootstrap,master1,master2,master3,worker1,worker2,worker3}/kubelet
sudo mkdir -p /opt/nginx/certificates/shared/{ca,apiserver,etcd,sa,apiserver-etcd-client,apiserver-kubelet-client}
sudo mkdir -p /etc/kubernetes/pki

# 2. Generar el Certificado de la CA (Certificados Compartidos)
echo "Generando certificado de la CA..."
openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/ca/ca.key -pkeyopt rsa_keygen_bits:2048
openssl req -x509 -new -nodes -key /opt/nginx/certificates/shared/ca/ca.key -subj "/CN=Kubernetes-CA" -days 3650 -out /opt/nginx/certificates/shared/ca/ca.crt

# Copiar CA a /etc/kubernetes/pki
sudo cp /opt/nginx/certificates/shared/ca/ca.crt /etc/kubernetes/pki/ca.crt
sudo cp /opt/nginx/certificates/shared/ca/ca.key /etc/kubernetes/pki/ca.key

# 3. Generar Certificados de Kubelet para Todos los Nodos
echo "Generando certificados de Kubelet para todos los nodos..."
for NODE in "${NODES[@]}"; do
    openssl genpkey -algorithm RSA -out /opt/nginx/certificates/${NODE}/kubelet/kubelet.key -pkeyopt rsa_keygen_bits:2048
    openssl req -new -key /opt/nginx/certificates/${NODE}/kubelet/kubelet.key -subj "/CN=system:node:${NODE}/O=system:nodes" -out /opt/nginx/certificates/${NODE}/kubelet/kubelet.csr
    openssl x509 -req -in /opt/nginx/certificates/${NODE}/kubelet/kubelet.csr -CA /opt/nginx/certificates/shared/ca/ca.crt -CAkey /opt/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /opt/nginx/certificates/${NODE}/kubelet/kubelet.crt -days 365
done

# 4. Generar Certificados Compartidos
echo "Generando certificados compartidos..."

# API Server Certificate
openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/apiserver/apiserver.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key /opt/nginx/certificates/shared/apiserver/apiserver.key -subj "/CN=kube-apiserver" -out /opt/nginx/certificates/shared/apiserver/apiserver.csr
openssl x509 -req -in /opt/nginx/certificates/shared/apiserver/apiserver.csr -CA /opt/nginx/certificates/shared/ca/ca.crt -CAkey /opt/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /opt/nginx/certificates/shared/apiserver/apiserver.crt -days 365

# Service Account Key Pair
openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/sa/sa.key -pkeyopt rsa_keygen_bits:2048
openssl rsa -in /opt/nginx/certificates/shared/sa/sa.key -pubout -out /opt/nginx/certificates/shared/sa/sa.pub

# Etcd Server Certificate
openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/etcd/etcd.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key /opt/nginx/certificates/shared/etcd/etcd.key -subj "/CN=etcd" -out /opt/nginx/certificates/shared/etcd/etcd.csr
openssl x509 -req -in /opt/nginx/certificates/shared/etcd/etcd.csr -CA /opt/nginx/certificates/shared/ca/ca.crt -CAkey /opt/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /opt/nginx/certificates/shared/etcd/etcd.crt -days 365

# API Server Etcd Client Certificates
openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key /opt/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.key -subj "/CN=apiserver-etcd-client" -out /opt/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.csr
openssl x509 -req -in /opt/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.csr -CA /opt/nginx/certificates/shared/ca/ca.crt -CAkey /opt/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /opt/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.crt -days 365

# API Server Kubelet Client Certificate
openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key /opt/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.key -subj "/CN=kube-apiserver-kubelet-client" -out /opt/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.csr
openssl x509 -req -in /opt/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.csr -CA /opt/nginx/certificates/shared/ca/ca.crt -CAkey /opt/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /opt/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.crt -days 365

# 5. Configuración del archivo etcd-openssl.cnf para cada nodo master
echo "Generando configuración de etcd-openssl.cnf para cada nodo master..."

for i in {1..3}; do
  cat <<EOF | sudo tee /etc/kubernetes/pki/etcd-openssl-${NODES[i]}.cnf
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
IP.2 = ${MASTER_IPS[i-1]}  # IP del nodo ${NODES[i]}

EOF
done

echo "Proceso completado."

# 6. Generar el certificado para apiserver-kubelet-client en /etc/kubernetes/pki si no se generó antes
echo "Generando certificado apiserver-kubelet-client en /etc/kubernetes/pki..."
sudo openssl genpkey -algorithm RSA -out /etc/kubernetes/pki/apiserver-kubelet-client.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key /etc/kubernetes/pki/apiserver-kubelet-client.key -subj "/CN=kube-apiserver-kubelet-client" -out /etc/kubernetes/pki/apiserver-kubelet-client.csr
sudo openssl x509 -req -in /etc/kubernetes/pki/apiserver-kubelet-client.csr \
-CA /opt/nginx/certificates/shared/ca/ca.crt \
-CAkey /opt/nginx/certificates/shared/ca/ca.key \
-CAcreateserial -out /etc/kubernetes/pki/apiserver-kubelet-client.crt -days 365

echo "Todos los certificados se han generado correctamente."