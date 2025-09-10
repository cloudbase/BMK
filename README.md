## Agile Kubernetes deployments

### Purpose

Deploy a K8S cluster on baremetal servers with Cilium L2 CNI, Rook Ceph CSI and KubeVirt on a Virtualized KVM env.

### Hardware setup

Required: one beefy box with Ubuntu 24.04, that supports KVM virtualization. That is all.

Order of operations:

  * Prepare the beefy box: install packages, configure libvirt network, iptables, create the libvirt vms, start the vbmc.
    -> helper script: create-machines.sh 
  * VNC in the libvirt VM (management controller) and setup static networking and SSH
    -> TO DO: automate this part using cloud-init
  * Ssh in the libvirt VM (management controller) and prepare the setup
    -> helper script: rename_repo_and_branch.sh, install-deps-k8s-all.sh 
  * Ssh in the libvirt VM (management controller) and deploy the management and workload cluster
    -> helper script: install-k8s-all.sh

## How to run

Prepare the hardware environment as instructed below and then run:

```
bash install-k8s-all.sh
```

Note: ArgoCD needs SSH key based authentication to the repository with WRITE rights.
It is required to fork this repository and update the repository paths accordingly.

```bash
OLD_BRANCH="insert-here"
CURRENT_BRANCH=$(git branch --show-current)
sed -i "s/${OLD_BRANCH}/${CURRENT_BRANCH}/g" applications/workload/templates/*
sed -i "s/${OLD_BRANCH}/${CURRENT_BRANCH}/g" applications/management/templates/*

OLD_REPO="git@github.com:cloudbase\/BMK.git"
CURRENT_REPO="git@github.com:ader1990\/BMK.git"
sed -i "s/${OLD_REPO}/${CURRENT_REPO}/g" applications/workload/templates/*
sed -i "s/${OLD_REPO}/${CURRENT_REPO}/g" applications/management/templates/*
```

For convenience, there is a helper script for the renaming:

```bash
# example to rename from branch name `cncf_tm_baremetal_kvm`
bash rename_repo_and_branch.sh cncf_tm_baremetal_kvm
```

For convenience, there is helper script to automate the installation of required binaries like k3d/kubectl/clusterctl on the management box.

```
sudo bash install-deps-k8s-all.sh
```

#### Minimum requirements for virtualized PoC all in one (just basic K8S deployment, no Cilium or Ceph/Rook)

Baremetal or virtual machine host:

  * CPU, 4 cores with enabled virtualization
  * 32 GB RAM
  * 200 GB SSD storage
  * NIC with Internet access

Software:

`sudo bash create-machines.sh`:

  * creates a libvirt network tink_network of type "route" using virtual bridge "virbr3": 192.168.56.1/24
  * adds iptables for NAT

  * creates 5 Libvirt QEMU-KVM VMs:

    * one for the controller management K8S cluster -> the K8S cluster that manages the lifecycle of the workload cluster
    * one for the workload K8S cluster --> the end goal
    * an extra 3 VMs for scaling the K8S cluster

Nginx with the Flatcar image:

```
# http://192.168.56.1/flatcar_production_image.bin.bzip2
sudo apt install nginx
sudo systemctl enable nginx
sudo systemct start nginx
sudo wget https://alpha.release.flatcar-linux.net/amd64-usr/current/flatcar_production_image.bin.bz2 -O /var/www/html/flatcar_production_image.bin.bzip2

```

For the virtualized environment, you need to run the `sudo bash create-machines.sh` as the first step,
  `sudo virsh start controller`, then connect to the controller via VNC (:0).

Once connected via VNC to the controller management node:

You need to manually set 192.168.56.2/24, gateway 192.168.56.1, dns 8.8.8.8 in netplan, the enable ssh password auth and set a password on user ubuntu.
Now you can connect to the controller management node: ssh ubuntu@192.168.56.1 from the host machine.

Once connected via SSH to the controller management node:

  * sudo apt install git btop htop screen build-essential
  * add the current user to the /etc/sudoers like root to have passwordless sudo
  * Create a SSH key and add it to https://github.com/ader1990/BMK or to the github account used
  * git clone git@github.com:ader1990/BMK.git
  * cd BMK
  * git checkout <target_branch>
  * sudo bash install-deps-k8s-all.sh
  * sudo usermod -aG docker $USER && newgrp docker (to recreate the docker context, to be able to use docker as the current non-root user)
  * create a SSH key with passwordless access at ~/.ssh/for-u5 only for https://github.com/ader1990/BMK with RW rights
  * configure install-k8s-all.sh with the required IPs and data
  * update "install-k8s-all.sh" with the correct argocd: argocd repo add
  * bash install-k8s-all.sh - it will fail if it needed to change any code
  * git add / git commit / git push
  * bash install-k8s-all.sh - it will fail if there are is sealed secrets master key
  * bash prepare-secrets.sh - prepares the bitnami sealed secrets.
    Remove the resourceVersion and uuid from the sealed_secrets_main.key
  * git add / git commit / git push
  * k3d cluster delete
  * bash install-k8s-all.sh
  * Libvirt vbmc implementation is flaky, you can use the virsh start/stop and vnc client to make sure the VMs pxe boot correctly

```

#### Management K8S cluster:

  * one NIC connected to tink_network with static IP: 192.168.56.2, gateway 192.168.56.1 set in netplan
  * created using k3d, has host pid | network control, no loadbalancer, basically as close to the host as possible
  * uses kube-vip for external IPs
  * ArgoCD installed and exposed at: 192.168.56.133:80, HTTP endpoint.
  * Tinkerbell stack installed and exposed at: 192.168.56.130:50061 and 8080, HTTP endpoint and DHCP listening on the vNIC connected to virbr3

#### Workload K8S cluster:

  * minimal cluster, one control plane that can be untainted to be worker node as well
  * will be installed using Tinkerbell services (DHCP, PXE of Hook linuxkit OS, Tinkerbell actions that dd the CAPI image, reboot, execute cloud-init metadata + userdata hosted by Tinkerbell, metadata and userdata created by Cluster API)

### Workflow:


  * host: manual: install Ubuntu 22.04 server core, clone repo
  * host: manual: execute prepare-k8s.sh:

    * host: automated: create libvirt network and set iptables rules
    * host: automated: create and start 4 libvirt domains, one for Management K8S and 3 for Workload K8S

  * management: manual: configure networking, clone repo (can be automated if an appliance is used)
  * management: manual: configure install-k8s-all.sh according to your extra requirements, if needed
  * management: manual: execute install-k8s-all.sh:

    * management: automated: install Docker
    * management: automated: download all required binaries: k3d, kubectl, helm, clusterctl, argocd
    * management: automated: install ArgoCD
    * management: automated: install Tinkerbell Stack as ArgoCD application
    * management: automated: install CAPI + CAPT services using clusterctl
    * management: automated: deploy Workload Cluster as ArgoCD application

