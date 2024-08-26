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
sudo openssl genpkey -algorithm RSA -out /opt/nginx/certificates/shared/ca/ca.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -x509 -new -nodes -key /opt/nginx/certificates/shared/ca/ca.key -subj "/CN=Kubernetes-CA" -days 3650 -out /opt/nginx/certificates/shared/ca/ca.crt

# 3. Generar Certificados de Kubelet para Todos los Nodos
echo "Generando certificados de Kubelet para todos los nodos..."
for NODE in "${NODES[@]}"; do
    sudo openssl genpkey -algorithm RSA -out /opt/nginx/certificates/${NODE}/kubelet/kubelet.key -pkeyopt rsa_keygen_bits:2048
    sudo openssl req -new -key /opt/nginx/certificates/${NODE}/kubelet/kubelet.key -subj "/CN=system:node:${NODE}/O=system:nodes" -out /opt/nginx/certificates/${NODE}/kubelet/kubelet.csr
    sudo openssl x509 -req -in /opt/nginx/certificates/${NODE}/kubelet/kubelet.csr -CA /opt/nginx/certificates/shared/ca/ca.crt -CAkey /opt/nginx/certificates/shared/ca/ca.key -CAcreateserial -out /opt/nginx/certificates/${NODE}/kubelet/kubelet.crt -days 365
done

# 4. Generar Certificados Compartidos
echo "Generando certificados compartidos..."

# API Server Certificate
sudo openssl genpkey -algorithm RSA -out /etc/kubernetes/pki/apiserver.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key /etc/kubernetes/pki/apiserver.key -subj "/CN=kube-apiserver" -out /etc/kubernetes/pki/apiserver.csr
sudo openssl x509 -req -in /etc/kubernetes/pki/apiserver.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out /etc/kubernetes/pki/apiserver.crt -days 365

# Service Account Key Pair
echo "Generando el par de claves del Service Account..."
sudo openssl genpkey -algorithm RSA -out /etc/kubernetes/pki/sa.key -pkeyopt rsa_keygen_bits:2048
sudo openssl rsa -in /etc/kubernetes/pki/sa.key -pubout -out /etc/kubernetes/pki/sa.pub

# Etcd Server Certificate
sudo openssl genpkey -algorithm RSA -out /etc/kubernetes/pki/etcd/etcd.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key /etc/kubernetes/pki/etcd/etcd.key -subj "/CN=etcd" -out /etc/kubernetes/pki/etcd/etcd.csr
sudo openssl x509 -req -in /etc/kubernetes/pki/etcd/etcd.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out /etc/kubernetes/pki/etcd/etcd.crt -days 365

# API Server Etcd Client Certificates
sudo openssl genpkey -algorithm RSA -out /etc/kubernetes/pki/apiserver-etcd-client.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key /etc/kubernetes/pki/apiserver-etcd-client.key -subj "/CN=apiserver-etcd-client" -out /etc/kubernetes/pki/apiserver-etcd-client.csr
sudo openssl x509 -req -in /etc/kubernetes/pki/apiserver-etcd-client.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out /etc/kubernetes/pki/apiserver-etcd-client.crt -days 365

# API Server Kubelet Client Certificate
sudo openssl genpkey -algorithm RSA -out /etc/kubernetes/pki/apiserver-kubelet-client.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key /etc/kubernetes/pki/apiserver-kubelet-client.key -subj "/CN=kube-apiserver-kubelet-client" -out /etc/kubernetes/pki/apiserver-kubelet-client.csr
sudo openssl x509 -req -in /etc/kubernetes/pki/apiserver-kubelet-client.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out /etc/kubernetes/pki/apiserver-kubelet-client.crt -days 365

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

# 6. Generar el certificado para kube-scheduler
echo "Generando certificado kube-scheduler..."
sudo openssl genpkey -algorithm RSA -out /etc/kubernetes/pki/kube-scheduler.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key /etc/kubernetes/pki/kube-scheduler.key -subj "/CN=system:kube-scheduler" -out /etc/kubernetes/pki/kube-scheduler.csr
sudo openssl x509 -req -in /etc/kubernetes/pki/kube-scheduler.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out /etc/kubernetes/pki/kube-scheduler.crt -days 365
sudo chmod 600 /etc/kubernetes/pki/kube-scheduler.key
sudo chmod 644 /etc/kubernetes/pki/kube-scheduler.crt
sudo chown root:root /etc/kubernetes/pki/kube-scheduler.*

echo "Todos los certificados se han generado correctamente."