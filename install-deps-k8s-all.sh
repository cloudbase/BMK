#!/bin/bash

set -xe

YQ_BINARY_URL="https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64"
ARGOCD_BINARY_URL="https://github.com/argoproj/argo-cd/releases/download/v2.8.4/argocd-linux-amd64"
K3D_BINARY_URL="https://github.com/k3d-io/k3d/releases/download/v5.6.0/k3d-linux-amd64"
CLUSTERCTL_BINARY_URL="https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.3.3/clusterctl-linux-amd64"
KUBESEAL_BINARY_URL="https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.1/kubeseal-0.24.1-linux-amd64.tar.gz"
NODE_SHELL_BINARY_URL="https://github.com/kvaps/kubectl-node-shell/raw/master/kubectl-node_shell"

install_yq() {
    curl -L "${YQ_BINARY_URL}" -o yq 
    chmod 777 yq
    mv yq "/usr/bin/yq"
}

install_argocd() {
    curl -L "${ARGOCD_BINARY_URL}" -o argocd 
    chmod 777 argocd
    mv argocd "/usr/bin/argocd"
}

install_k3d() {
    curl -L "${K3D_BINARY_URL}" -o k3d
    chmod 777 k3d
    mv k3d "/usr/bin/k3d"
}

install_kubectl() {
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod 777 kubectl
    mv kubectl "/usr/bin/kubectl"
}

install_clusterctl() {
    curl -L "${CLUSTERCTL_BINARY_URL}" -o clusterctl
    chmod 777 clusterctl
    mv clusterctl "/usr/bin/clusterctl"
}

install_node_shell() {
    curl -LO "${NODE_SHELL_BINARY_URL}"
    chmod +x ./kubectl-node_shell
    mv ./kubectl-node_shell /usr/local/bin/kubectl-node_shell
}

install_kubeseal() {
    wget "${KUBESEAL_BINARY_URL}"
    tar -xzvf kubeseal-0.24.1-linux-amd64.tar.gz
    install -m 755 kubeseal /usr/local/bin/kubeseal
    rm kubeseal && rm kubeseal-0.24.1-linux-amd64.tar.gz
}

install_helm() {
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 
    bash get_helm.sh --version "v3.9.4"
    rm get_helm.sh
}

install_docker() {
    apt update
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc
    do
        apt-get remove $pkg || true
    done
    apt install ca-certificates curl gnupg -y
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update
    apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    groupadd docker || true
    usermod -aG docker $USER
}

install_dependencies() {
    which yq || install_yq
    which argocd || install_argocd
    which k3d || install_k3d
    which kubectl || install_kubectl
    which clusterctl || install_clusterctl
    which kubectl-node_shell || install_node_shell
    which kubeseal || install_kubeseal
    which helm || install_helm
    which docker || install_docker
}

main() {
    install_dependencies
    echo "ALL DONE!"
}

main
