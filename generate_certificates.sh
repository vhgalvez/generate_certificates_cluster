#!/bin/bash

# Variables
NODES=("bootstrap" "master1" "master2" "master3" "worker1" "worker2" "worker3")
MASTER_IPS=("10.17.4.21" "10.17.4.22" "10.17.4.23")

# 1. Crear la Estructura de Directorios
echo "Creando estructura de directorios..."
sudo mkdir -p /usr/share/nginx/certificates/{bootstrap,master1,master2,master3,worker1,worker2,worker3}/kubelet
sudo mkdir -p /usr/share/nginx/certificates/shared/{ca,apiserver,etcd,sa,apiserver-etcd-client,apiserver-kubelet-client}

# 2. Generar el Certificado de la CA (Certificados Compartidos)
echo "Generando certificado de la CA..."
openssl genpkey -algorithm RSA -out /usr/share/nginx/certificates/shared/ca/ca.key -pkeyopt rsa_keygen_bits:2048
openssl req -x509 -new -nodes -key /usr/share/nginx/certificates/shared/ca/ca.key -subj "/CN=Kubernetes-CA" -days 3650 -out /usr/share/nginx/certificates/shared/ca/ca.crt

# 3. Generar Certificados de Kubelet para Todos los Nodos
echo "Generando certificados de Kubelet para todos los nodos..."
for NODE in "${NODES[@]}"; do
    openssl genpkey -algorithm RSA -out /usr/share/nginx/certificates/${NODE}/kubelet/kubelet.key -pkeyopt rsa_keygen_bits:2048
    openssl req -new -key /usr/share/nginx/certificates/${NODE}/kubelet/kubelet.key -subj "/CN=system:node:${NODE}/O=system:nodes" -out /usr/share/nginx/certificates/${NODE}/kubelet/kubelet.csr
    openssl x509 -req -in /usr/share/nginx/certificates/${NODE}/kubelet/kubelet.csr -CA /usr/share/nginx/certificates/shared/ca/ca.crt -CAkey /usr/share/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /usr/share/nginx/certificates/${NODE}/kubelet/kubelet.crt -days 365
done

# 4. Generar Certificados Compartidos
echo "Generando certificados compartidos..."

# API Server Certificate
openssl genpkey -algorithm RSA -out /usr/share/nginx/certificates/shared/apiserver/apiserver.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key /usr/share/nginx/certificates/shared/apiserver/apiserver.key -subj "/CN=kube-apiserver" -out /usr/share/nginx/certificates/shared/apiserver/apiserver.csr
openssl x509 -req -in /usr/share/nginx/certificates/shared/apiserver/apiserver.csr -CA /usr/share/nginx/certificates/shared/ca/ca.crt -CAkey /usr/share/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /usr/share/nginx/certificates/shared/apiserver/apiserver.crt -days 365

# Service Account Key Pair
openssl genpkey -algorithm RSA -out /usr/share/nginx/certificates/shared/sa/sa.key -pkeyopt rsa_keygen_bits:2048
openssl rsa -in /usr/share/nginx/certificates/shared/sa/sa.key -pubout -out /usr/share/nginx/certificates/shared/sa/sa.pub

# Etcd Server Certificate
openssl genpkey -algorithm RSA -out /usr/share/nginx/certificates/shared/etcd/etcd.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key /usr/share/nginx/certificates/shared/etcd/etcd.key -subj "/CN=etcd" -out /usr/share/nginx/certificates/shared/etcd/etcd.csr
openssl x509 -req -in /usr/share/nginx/certificates/shared/etcd/etcd.csr -CA /usr/share/nginx/certificates/shared/ca/ca.crt -CAkey /usr/share/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /usr/share/nginx/certificates/shared/etcd/etcd.crt -days 365

# API Server Etcd Client Certificates
openssl genpkey -algorithm RSA -out /usr/share/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key /usr/share/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.key -subj "/CN=apiserver-etcd-client" -out /usr/share/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.csr
openssl x509 -req -in /usr/share/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.csr -CA /usr/share/nginx/certificates/shared/ca/ca.crt -CAkey /usr/share/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /usr/share/nginx/certificates/shared/apiserver-etcd-client/apiserver-etcd-client.crt -days 365

# API Server Kubelet Client Certificate
openssl genpkey -algorithm RSA -out /usr/share/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.key -pkeyopt rsa_keygen_bits:2048
openssl req -new -key /usr/share/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.key -subj "/CN=kube-apiserver-kubelet-client" -out /usr/share/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.csr
openssl x509 -req -in /usr/share/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.csr -CA /usr/share/nginx/certificates/shared/ca/ca.crt -CAkey /usr/share/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /usr/share/nginx/certificates/shared/apiserver-kubelet-client/apiserver-kubelet-client.crt -days 365

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
-CA /usr/share/nginx/certificates/shared/ca/ca.crt \
-CAkey /usr/share/nginx/certificates/shared/ca/ca.key \
-CAcreateserial -out /etc/kubernetes/pki/apiserver-kubelet-client.crt -days 365

# 7. Reiniciar el servicio kube-apiserver después de generar los certificados
echo "Reiniciando kube-apiserver..."
sudo systemctl daemon-reload
sudo systemctl restart kube-apiserver

echo "Todos los certificados se han generado y el servicio kube-apiserver ha sido reiniciado."