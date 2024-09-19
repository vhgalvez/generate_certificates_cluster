# Generate Certificates for Kubernetes Cluster


1. Verifica si cfssl está instalado:
Si no tienes cfssl y cfssljson instalados, sigue los siguientes pasos:

bash
Copiar código
sudo curl -L -o /usr/local/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
sudo curl -L -o /usr/local/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
sudo chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson

This repository contains scripts to automate the generation of certificates for a Kubernetes cluster, including the control plane (API server, etcd, and kube-controller-manager) and worker nodes.

## Overview

This script helps to generate certificates for a Kubernetes cluster running various components like:

- Kubernetes API Server
- kube-controller-manager
- kube-scheduler
- etcd
- kubelet
- kube-proxy

The script automates the creation of shared and node-specific certificates, which are required to secure communication across the Kubernetes cluster.

## Features

- Automated certificate generation for both control plane and worker nodes.
- Generates individual certificates for each node and service.
- Supports setting up certificates for both etcd and kube-apiserver client communication.
- Script is adaptable to custom IP ranges and node names.

## Prerequisites

Before running the script, ensure that the following are installed on your system:

- **OpenSSL**: Required for generating certificates.
- **Git**: To clone the repository.
- **Bash**: Ensure you are using a Linux system with a bash shell.

You should also have root or sudo privileges to execute some of the commands.

## Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/vhgalvez/generate_certificates_cluster.git
   cd generate_certificates_cluster
   ```

## Usage

1. Configure the script by editing variables like NODES and MASTER_IPS inside generate_certificates.sh to fit your environment. For example:

```bash
NODES=("master1" "master2" "master3" "worker1" "worker2" "worker3")
MASTER_IPS=("10.17.4.21" "10.17.4.22" "10.17.4.23")
```
2. Run the script:


```bash
./generate_certificates.sh
```


3. The script will generate all the necessary certificates and store them in the specified directory.

4. After running the script, the certificates will be available in:

* /home/core/nginx-docker/certificates/shared/
* /home/core/nginx-docker/certificates/kubelet/
* /home/core/nginx-docker/certificates/apiserver/
* /home/core/nginx-docker/certificates/etcd/

The log file `generate_certificates.log` will be created in the same base directory for troubleshooting.

##  Generated Certificates

The following certificates are generated:

* CA Certificates: Used to sign other certificates.
* Admin Certificates: Allows admin-level access to the Kubernetes cluster.
* Kubelet Certificates: For secure communication between kubelets and the API server.
* API Server Certificates: For the Kubernetes API server.
* etcd Certificates: For etcd communication.
* apiserver-etcd-client Certificates: For the API server to communicate securely with etcd.




/home/core/nginx-docker/certificates/
│
├── shared/                     # Certificados compartidos (CA, admin)
│   ├── ca.pem
│   ├── ca-key.pem
│   ├── admin.pem
│   └── admin-key.pem
│
├── apiserver/                  # Certificados del servidor API
│   ├── apiserver.pem
│   └── apiserver-key.pem
│
├── apiserver-etcd-client/       # Certificados del cliente apiserver-etcd
│   ├── apiserver-etcd-client.pem
│   └── apiserver-etcd-client-key.pem
│
├── etcd/                       # Certificados para etcd
│   ├── etcd.pem
│   └── etcd-key.pem
│
├── kubelet/                    # Certificados para los nodos kubelet (worker y master)
│   ├── kubelet-master1.pem
│   ├── kubelet-master2.pem
│   ├── kubelet-master3.pem
│   ├── kubelet-worker1.pem
│   ├── kubelet-worker2.pem
│   ├── kubelet-worker3.pem
│   └── [clave de cada uno]
│
├── kube-proxy/                 # Certificados para Kube Proxy
│   ├── kube-proxy.pem
│   └── kube-proxy-key.pem
│
├── kube-scheduler/             # Certificados para el planificador (kube-scheduler)
│   ├── kube-scheduler.pem
│   └── kube-scheduler-key.pem
│
└── kube-controller-manager/    # Certificados para el administrador del controlador (kube-controller-manager)
    ├── kube-controller-manager.pem
    └── kube-controller-manager-key.pem

## Customization

You can adjust the following variables in the script as needed:

* NODES: List of all control plane and worker nodes.
* MASTER_IPS: IP addresses of master nodes.
* ETCD_NODE: IP address of the etcd node.
* Certificate Validity: Modify the -days flag in OpenSSL commands to set a custom validity period for the certificates.

## License

This project is licensed under the MIT License. See the LICENSE file for more details.

## Contributing

Feel free to fork the project, make changes, and create a pull request. Contributions are welcome!