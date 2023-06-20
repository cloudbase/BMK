## ArgoCD HOWTO

### ENVIRONMENT:

* SERVERS: 1 MGMT + 1 ARM64 ALTRA K8S control plane + 1 ARM64 ALTRA K8S worker node + 1 X64 VM worker node
* SUBNET TO BE USED: 10.8.10.0/24
* MGMT SERVER IP: 10.8.10.2 on nic 2 SUT33-EMAG
* ARGO-CD IP: 10.8.10.133 on nic 2 SUT33-EMAG
* TINKERBELL IP: 10.8.10.130 on nic 2 SUT33-EMAG


### WORKFLOW

* On MGMT node:
    * Install Ubuntu 22.04
    * Install packages & services
      * docker
    * Download binaries
      * k3d
      * kubectl
      * clusterctl
      * helm
      * argocd

