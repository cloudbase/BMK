### Baremetal Kubernetes

This repository contains the automation to create a K8S cluster on baremetal.
Please follow the blog post series here for more information: https://cloudbase.it/bare-metal-kubernetes-on-mixed-x64-and-arm64 .

### ENVIRONMENT:

* SERVERS: 1 MGMT + 1 ARM64 ALTRA K8S control plane + 1 ARM64 ALTRA K8S worker node
* SUBNET TO BE USED: 10.8.10.0/24
* MGMT SERVER IP: 10.8.10.2 on nic 2 SUT33-EMAG
* ARGO-CD IP: 10.8.10.133 on nic 2 SUT33-EMAG
* TINKERBELL IP: 10.8.10.130 on nic 2 SUT33-EMAG

### Configure ArgoCD

  * git and a github ssh key with push/pull permissions
  * private subnets, public subnets and ethernet device names for Cilium
  * storage devices for Ceph

### Run the script

```bash
bash install-k8s-all.sh
```

### Management cluster

  * k3d k8s cluster
  * ArgoCD
  * Tinkerbel stack
  * CAPI stack
  * CAPT (Cluster API Provider for Tinkerbell)


### Workload cluster

  * CAPI k8s cluster
  * Cilium with L2 Announcement
  * Ceph
  * KubeVirt

