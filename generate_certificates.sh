#!/bin/bash

# Definir la ruta base para los certificados
# El directorio donde se almacenarán todos los certificados generados.
BASE_DIR="/etc/kubernetes/pki"

# Nodos y direcciones IP en el clúster Kubernetes
# Aquí definimos los nombres de los nodos maestros y trabajadores, junto con sus respectivas IPs.
NODES=("master1" "master2" "master3" "worker1" "worker2" "worker3")
NODE_IPS=("10.17.4.21" "10.17.4.22" "10.17.4.23" "10.17.4.24" "10.17.4.25" "10.17.4.26")

# Crear estructura de directorios
# Creamos los directorios necesarios en la ruta de almacenamiento para cada componente que requiere un certificado.
echo "Creating directory structure..."
sudo mkdir -p ${BASE_DIR}/{etcd,apiserver,kubelet,kube-proxy,kubernetes-admin,kube-controller-manager}

# 1. Generar el archivo de configuración etcd-openssl.cnf para etcd
# Este archivo contiene los parámetros necesarios para generar el certificado de etcd.
echo "Generating etcd-openssl.cnf..."
sudo tee /etc/kubernetes/pki/etcd/etcd-openssl.cnf <<EOF
[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = etcd
DNS.2 = etcd.local
IP.1 = 127.0.0.1
IP.2 = 10.17.4.22
EOF

# 2. Generar el archivo de configuración v3_req.cnf para Kubernetes
# Este archivo define las extensiones necesarias para generar el certificado del kube-apiserver.
echo "Generating v3_req.cnf..."
sudo tee /etc/kubernetes/pki/v3_req.cnf <<EOF
[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
IP.1 = 10.17.4.22
IP.2 = 10.96.0.1
EOF

# 3. Generar el certificado del CA (Certificate Authority)
# El certificado CA (Certificate Authority) se utiliza para firmar los demás certificados que se generarán.
echo "Generating CA certificate..."
sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/ca.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -x509 -new -key ${BASE_DIR}/ca.key -subj "/CN=Kubernetes-CA" -days 3650 -out ${BASE_DIR}/ca.crt

# 4. Generar certificados para etcd usando etcd-openssl.cnf
# Aquí generamos la clave privada, el CSR (Certificate Signing Request), y finalmente firmamos el certificado para etcd.
echo "Generating etcd certificates..."
sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/etcd/etcd.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key ${BASE_DIR}/etcd/etcd.key -out ${BASE_DIR}/etcd/etcd.csr -config ${BASE_DIR}/etcd/etcd-openssl.cnf
sudo openssl x509 -req -in ${BASE_DIR}/etcd/etcd.csr -CA ${BASE_DIR}/ca.crt -CAkey ${BASE_DIR}/ca.key -CAcreateserial -out ${BASE_DIR}/etcd/etcd.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/etcd/etcd-openssl.cnf

# 5. Generar certificados para kube-apiserver usando v3_req.cnf
# Generamos la clave privada, el CSR y el certificado para el API server de Kubernetes, que es una pieza central del clúster.
echo "Generating API server certificates..."
sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/apiserver/apiserver.key -pkeyopt rsa_keygen_bits:2048
sudo openssl req -new -key ${BASE_DIR}/apiserver/apiserver.key -out ${BASE_DIR}/apiserver/apiserver.csr -config ${BASE_DIR}/v3_req.cnf
sudo openssl x509 -req -in ${BASE_DIR}/apiserver/apiserver.csr -CA ${BASE_DIR}/ca.crt -CAkey ${BASE_DIR}/ca.key -CAcreateserial -out ${BASE_DIR}/apiserver/apiserver.crt -days 365 -extensions v3_req -extfile ${BASE_DIR}/v3_req.cnf

# 6. Generar certificados Kubelet para todos los nodos
# Para cada nodo (tanto maestros como trabajadores), generamos un certificado Kubelet específico con sus respectivos nombres y direcciones IP.
echo "Generating Kubelet certificates for all nodes..."
for i in "${!NODES[@]}"; do
  NODE=${NODES[$i]}
  NODE_IP=${NODE_IPS[$i]}

  sudo mkdir -p ${BASE_DIR}/${NODE}/kubelet

  # Configuración específica del nodo para el CSR de Kubelet.
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
IP.1 = ${NODE_IP}
EOF

  # Generar la clave privada y el CSR para Kubelet
  sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/${NODE}/kubelet/kubelet.key -pkeyopt rsa_keygen_bits:2048
  sudo openssl req -new -key ${BASE_DIR}/${NODE}/kubelet/kubelet.key -out ${BASE_DIR}/${NODE}/kubelet/kubelet.csr -config /tmp/kubelet-${NODE}-openssl.cnf

  # Firmar el certificado de Kubelet con el CA generado previamente
  sudo openssl x509 -req -in ${BASE_DIR}/${NODE}/kubelet/kubelet.csr -CA ${BASE_DIR}/ca.crt -CAkey ${BASE_DIR}/ca.key -CAcreateserial -out ${BASE_DIR}/${NODE}/kubelet/kubelet.crt -days 365 -extensions req_ext -extfile /tmp/kubelet-${NODE}-openssl.cnf
done

# Mensaje final indicando que todos los certificados se han generado correctamente.
echo "All certificates have been generated successfully."