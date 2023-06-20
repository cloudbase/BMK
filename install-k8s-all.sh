#!/bin/bash

set -xe

sudo ls

CURRENT_BRANCH=$(git branch --show-current)
OLD_CURRENT_BRANCH="argocd-arm64-altra-flatcar1"

export IP_SUBNET_PREFIX="10.8.10"
export IP_BMC_SUBNET_PREFIX="10.8.0"

export MANAGEMENT_VIP_NIC="enp1s0f0np0"
export MANAGEMENT_HOST_IP="${IP_SUBNET_PREFIX}.2"
export MANAGEMENT_HOST_IP_CIDR="${MANAGEMENT_HOST_IP}/32"

export MANAGEMENT_ARGOCD_IP="${IP_SUBNET_PREFIX}.133"
export MANAGEMENT_TINKERBELL_IP="${IP_SUBNET_PREFIX}.130"
export OLD_MANAGEMENT_TINKERBELL_IP="${IP_SUBNET_PREFIX}.120"
export MANAGEMENT_TINKERBELL_HTTP="http://${MANAGEMENT_TINKERBELL_IP}:8080"
export MANAGEMENT_TINKERBELL_GRPC="${MANAGEMENT_TINKERBELL_IP}:42113"

export WORKLOAD_K8S_GATEWAY="${IP_SUBNET_PREFIX}.1"
export WORKLOAD_K8S_IP="${IP_SUBNET_PREFIX}.151"
export WORKLOAD_K8S_IP_POOL="${IP_SUBNET_PREFIX}.144/29"

export WORKLOAD_K8S_SERVER_IP_1="${IP_SUBNET_PREFIX}.42"
export WORKLOAD_K8S_SERVER_BMC_IP_1="${IP_BMC_SUBNET_PREFIX}.243"

export WORKLOAD_OS_IMG_URL="http:\/\/10.8.10.2:8001\/ubuntu-2204-arm64-kube-v1.26.3.raw.gz"
export OLD_WORKLOAD_OS_IMG_URL="http:\/\/10.8.10.3:8001\/ubuntu-2204-arm64-kube-v1.26.3.raw.gz"

# https://github.com/mikefarah/yq/releases/download/v4.33.3/yq_linux_arm64
yq -i \
  '.controller.service.loadBalancerIP = strenv(MANAGEMENT_ARGOCD_IP)' \
  config/management/ingress-nginx/values.yaml

yq -i \
  '.env.vip_interface = strenv(MANAGEMENT_VIP_NIC)' \
  config/management/ingress-nginx/kube-vip-values.yaml

yq -i \
  '.global.hostAliases[0].ip = strenv(MANAGEMENT_ARGOCD_IP)' \
  config/management/argocd/values.yaml

yq -i \
  '.argocd.values.global.hostAliases[0].ip = strenv(MANAGEMENT_ARGOCD_IP)' \
  applications/management/values.yaml
yq -i \
  '.ingress.values.controller.service.loadBalancerIP = strenv(MANAGEMENT_ARGOCD_IP)' \
  applications/management/values.yaml

yq -i \
  '.tinkstack.values.boots.env[3].value = strenv(MANAGEMENT_TINKERBELL_HTTP)' \
  applications/management/values.yaml
yq -i \
  '.tinkstack.values.boots.env[4].value = strenv(MANAGEMENT_TINKERBELL_IP)' \
  applications/management/values.yaml
yq -i \
  '.tinkstack.values.boots.env[5].value = strenv(MANAGEMENT_TINKERBELL_IP)' \
  applications/management/values.yaml
yq -i \
  '.tinkstack.values.boots.env[7].value = strenv(MANAGEMENT_TINKERBELL_GRPC)' \
  applications/management/values.yaml
yq -i \
  '.tinkstack.values.stack.loadBalancerIP = strenv(MANAGEMENT_TINKERBELL_IP)' \
  applications/management/values.yaml

yq -i \
  '(select(documentIndex == 2) | .spec.controlPlaneEndpoint.host) = strenv(WORKLOAD_K8S_IP)' \
  config/management/cluster/kub-poc-ubuntu.yaml

yq -i \
  '.spec.virtualRouters[0].neighbors[0].peerAddress = strenv(MANAGEMENT_HOST_IP_CIDR)' \
  config/workload/cilium/peering.yaml

sed -i "s/${OLD_WORKLOAD_OS_IMG_URL}/${WORKLOAD_OS_IMG_URL}/g" config/management/cluster/kub-poc-ubuntu.yaml
sed -i "s/${OLD_MANAGEMENT_TINKERBELL_IP}/${MANAGEMENT_TINKERBELL_IP}/g" config/management/cluster/kub-poc-ubuntu.yaml

sed -i "s/${OLD_CURRENT_BRANCH}/${CURRENT_BRANCH}/g" applications/workload/templates/*
sed -i "s/${OLD_CURRENT_BRANCH}/${CURRENT_BRANCH}/g" applications/management/templates/*

check_git_diff=`git diff`

if [[ "${check_git_diff}" != "" ]]
then
  echo "please commit the changes first: ${check_git_diff}"
  exit 1
fi

# Start the deployment
k3d cluster list k3s-default || k3d cluster create --network host --no-lb --k3s-arg "--disable=traefik,servicelb" \
  --k3s-arg "--kube-apiserver-arg=feature-gates=MixedProtocolLBService=true" \
  --host-pid-mode

mkdir -p ~/.kube/
k3d kubeconfig get -a >~/.kube/config
until kubectl wait --for=condition=Ready nodes --all --timeout=600s; do sleep 1; done

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add argo-cd https://argoproj.github.io/argo-helm
helm repo add kube-vip https://kube-vip.github.io/helm-charts/
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --version 4.5.2 --namespace ingress-nginx \
  --create-namespace \
  -f config/management/ingress-nginx/values.yaml -v 6
until kubectl wait deployment -n ingress-nginx ingress-nginx-controller --for condition=Available=True --timeout=90s; do sleep 1; done

helm upgrade --install kube-vip kube-vip/kube-vip \
  --namespace kube-vip --create-namespace \
  -f config/management/ingress-nginx/kube-vip-values.yaml -v 6

helm upgrade --install argo-cd \
  --create-namespace --namespace argo-cd \
  -f config/management/argocd/values.yaml argo-cd/argo-cd
until kubectl wait deployment -n argo-cd argo-cd-argocd-server --for condition=Available=True --timeout=90s; do sleep 1; done
until kubectl wait deployment -n argo-cd argo-cd-argocd-applicationset-controller --for condition=Available=True --timeout=90s; do sleep 1; done
until kubectl wait deployment -n argo-cd argo-cd-argocd-repo-server --for condition=Available=True --timeout=90s; do sleep 1; done

echo "${MANAGEMENT_ARGOCD_IP} argo-cd.mgmt.kub-poc.local" | sudo tee -a /etc/hosts

pass=$(kubectl -n argo-cd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd repo list || argocd login argo-cd.mgmt.kub-poc.local --username admin --password $pass --insecure

argocd repo add git@github.com:ader1990/u5n-k8s-docs.git \
    --ssh-private-key-path ~/.ssh/id_rsa
argocd app sync management-apps || argocd app create management-apps \
    --repo git@github.com:ader1990/u5n-k8s-docs.git \
    --path applications/management --dest-namespace argo-cd \
    --dest-server https://kubernetes.default.svc \
    --revision "${CURRENT_BRANCH}" --sync-policy automated

argocd app sync management-apps
argocd app get management-apps --hard-refresh

# until argocd app sync prometheus; do sleep 5; done

argocd app sync tink-stack
until kubectl wait deployment -n tink-system tink-stack --for condition=Available=True --timeout=90s; do sleep 1; done

argocd app sync hardware

export TINKERBELL_IP="${MANAGEMENT_TINKERBELL_IP}"

mkdir -p ~/.cluster-api
cat > ~/.cluster-api/clusterctl.yaml <<EOF
providers:
  - name: "tinkerbell"
    url: "https://github.com/tinkerbell/cluster-api-provider-tinkerbell/releases/v0.4.0/infrastructure-components.yaml"
    type: "InfrastructureProvider"
EOF

export EXP_KUBEADM_BOOTSTRAP_FORMAT_IGNITION="true"
clusterctl init --infrastructure tinkerbell -v 5
until kubectl wait deployment -n capt-system capt-controller-manager --for condition=Available=True --timeout=90s; do sleep 1; done

until argocd app sync workload-cluster;  do sleep 1; done
argocd app sync machine

sleep 30

clusterctl get kubeconfig kub-poc -n tink-system > ~/kub-poc.kubeconfig || sleep 100 || clusterctl get kubeconfig kub-poc -n tink-system > ~/kub-poc.kubeconfig
until kubectl --kubeconfig ~/kub-poc.kubeconfig get node -A; do sleep 1; done

until kubectl --kubeconfig ~/kub-poc.kubeconfig get node sut01-altra; do sleep 1; done
until kubectl --kubeconfig ~/kub-poc.kubeconfig get node sut02-altra; do sleep 1; done

argocd cluster add kub-poc-admin@kub-poc \
   --kubeconfig ~/kub-poc.kubeconfig \
   --server argo-cd.mgmt.kub-poc.local \
   --insecure --yes

argocd app create workload-cluster-apps \
    --repo git@github.com:ader1990/u5n-k8s-docs.git \
    --path applications/workload --dest-namespace argo-cd \
    --dest-server https://kubernetes.default.svc \
    --revision "${CURRENT_BRANCH}" --sync-policy automated

kubectl --kubeconfig ~/kub-poc.kubeconfig patch node sut01-altra -p '{"spec":{"taints":[]}}' || true
kubectl --kubeconfig ~/kub-poc.kubeconfig patch node sut02-altra -p '{"spec":{"taints":[]}}' || true

argocd app sync bird

argocd app get workload-cluster-apps --hard-refresh
argocd app sync cilium-manifests || argocd app sync cilium-kub-poc

until kubectl --kubeconfig ~/kub-poc.kubeconfig wait deployment -n kube-system cilium-operator --for condition=Available=True --timeout=90s; do sleep 1; done
argocd app sync cilium-manifests --force || argocd app sync cilium-kub-poc

until kubectl get CiliumLoadBalancerIPPoold --kubeconfig ~/kub-poc.kubeconfig || (argocd app sync cilium-manifests && argocd app sync cilium-kub-poc); do sleep 1; done
until (argocd app sync cilium-manifests || argocd app sync cilium-kub-poc) && kubectl get CiliumLoadBalancerIPPool --kubeconfig ~/kub-poc.kubeconfig; do sleep 1; done

# verify cilium load balancer
argocd app sync nginx --force --prune
until kubectl --kubeconfig ~/kub-poc.kubeconfig wait pod -n nginx nginx --for condition=Ready --timeout=90s; do sleep 1; done
# does not work on ARM64 because MSSQL images for ARM64 do not exist

argocd app sync mssql
until kubectl --kubeconfig ~/kub-poc.kubeconfig exec -ti deployment/kub-poc-mssql2022v3 -- /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "P@ssw0rd1" -Q "SELECT name, database_id, create_date  FROM sys.databases"; do sleep 1; done

argocd app sync rook-ceph-operator
until kubectl --kubeconfig ~/kub-poc.kubeconfig wait deployment -n rook-ceph rook-ceph-operator --for condition=Available=True --timeout=90s; do sleep 1; done

# cleanup nodes from previous ceph

KUBECONFIG=~/kub-poc.kubeconfig kubectl node-shell sut01-altra -- sh -c 'export DISK="/dev/nvme1n1" && echo "w" | fdisk $DISK && sgdisk --zap-all $DISK && blkdiscard $DISK || sudo dd if=/dev/zero of="$DISK" bs=1M count=100 oflag=direct,dsync && partprobe $DISK && rm -rf /var/lib/rook'
KUBECONFIG=~/kub-poc.kubeconfig kubectl node-shell sut02-altra -- sh -c 'export DISK="/dev/nvme1n1" && echo "w" | fdisk $DISK && sgdisk --zap-all $DISK && blkdiscard $DISK || sudo dd if=/dev/zero of="$DISK" bs=1M count=100 oflag=direct,dsync && partprobe $DISK && rm -rf /var/lib/rook'
# KUBECONFIG=~/kub-poc.kubeconfig kubectl node-shell sut31-emag -- sh -c 'echo w | fdisk /dev/sdb && rm -rf /var/lib/rook'
# KUBECONFIG=~/kub-poc.kubeconfig kubectl node-shell sut32-emag -- sh -c 'echo w | fdisk /dev/sdb && rm -rf /var/lib/rook'

argocd app sync rook-ceph-cluster

until kubectl  --kubeconfig ~/kub-poc.kubeconfig -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status; do sleep 1; done

# verify ceph pvc
argocd app sync wordpress --force --prune

# verify kubevirt
argocd app sync cdi-manifests
argocd app sync kubevirt

until kubectl --kubeconfig ~/kub-poc.kubeconfig wait deployment -n kubevirt virt-api --for condition=Available=True --timeout=90s; do sleep 1; done
until kubectl --kubeconfig ~/kub-poc.kubeconfig wait deployment -n kubevirt virt-operator --for condition=Available=True --timeout=90s; do sleep 1; done

argocd app sync testvm --force --prune

argocd app sync kubevirt-vncproxy
