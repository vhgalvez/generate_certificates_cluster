#!/bin/bash

# Define el directorio base para los certificados
BASE_DIR="/home/core/nginx-docker/certificates"
LOG_FILE="${BASE_DIR}/generate_certificates.log"

# Crear un archivo de registro
exec > >(tee -i ${LOG_FILE})
exec 2>&1
set -e  # Detener el script en caso de error

# Variables
NODES=("master1" "master2" "master3" "worker1" "worker2" "worker3")
MASTER_IPS=("10.17.4.21" "10.17.4.22" "10.17.4.23")
ETCD_NODE="10.17.4.23"  # Suponiendo que etcd se ejecuta en esta IP

# Crear la estructura de directorios
echo "Creando estructura de directorios..."
sudo mkdir -p ${BASE_DIR}/{shared,sa,kubelet,apiserver,etcd,apiserver-etcd-client,kube-controller-manager,kube-scheduler,kube-proxy}

# Función para eliminar certificados existentes
remove_existing_certificates() {
  echo "Eliminando certificados existentes si los hay..."
  sudo rm -f ${BASE_DIR}/shared/ca.crt ${BASE_DIR}/shared/admin.crt ${BASE_DIR}/kubelet/*.crt ${BASE_DIR}/apiserver/apiserver.crt ${BASE_DIR}/etcd/etcd.crt ${BASE_DIR}/apiserver-etcd-client/*.crt
}

# 1. Generar certificado de CA (compartido)
generate_ca_certificate() {
  echo "Generando certificado de CA..."
  sudo openssl genpkey -algorithm RSA -out ${BASE_DIR}/shared/ca.key -pkeyopt rsa_keygen_bits:2048
  sudo openssl req -x509 -new -key ${BASE_DIR}/shared/ca.key -subj "/CN=Kubernetes-CA" -days 3650 -out ${BASE_DIR}/shared/ca.crt
}

# 2. Generar certificado Admin de Kubernetes (compartido)
generate_admin_certificate() {
  echo "Generando certificado de admin..."
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

# 3. Generar certificados de Kubelet para todos los nodos
generate_kubelet_certificates() {
  for NODE in "${NODES[@]}"; do
    echo "Generando certificado Kubelet para ${NODE}..."
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

# Resto del código de generación de certificados...
# Se incluyen otras funciones como generate_apiserver_certificate, generate_etcd_certificates, etc.

# Asignar permisos adecuados
set_permissions() {
  echo "Estableciendo permisos correctos para los certificados..."
  sudo chmod 644 ${BASE_DIR}/shared/ca.crt ${BASE_DIR}/shared/admin.crt
  sudo chmod 600 ${BASE_DIR}/shared/ca.key ${BASE_DIR}/shared/admin.key
  sudo chmod 644 ${BASE_DIR}/kubelet/*.crt ${BASE_DIR}/kubelet/*.key
  sudo chmod 644 ${BASE_DIR}/apiserver/*.crt ${BASE_DIR}/apiserver/*.key
  sudo chmod 644 ${BASE_DIR}/etcd/*.crt ${BASE_DIR}/etcd/*.key
  sudo chmod 644 ${BASE_DIR}/apiserver-etcd-client/*.crt ${BASE_DIR}/apiserver-etcd-client/*.key
  sudo chmod 644 ${BASE_DIR}/kube-scheduler/*.crt ${BASE_DIR}/kube-scheduler/*.key
  sudo chmod 644 ${BASE_DIR}/kube-controller-manager/*.crt ${BASE_DIR}/kube-controller-manager/*.key
}

# Eliminar certificados existentes, luego regenerarlos
remove_existing_certificates
generate_ca_certificate
generate_admin_certificate
generate_kubelet_certificates
# Llamadas a otras funciones...

# Configurar los permisos
set_permissions

# Limpiar archivos temporales
rm -f /tmp/kubelet-*.cnf

echo "Todos los certificados han sido regenerados y se han configurado los permisos correctamente."
