#!/bin/bash
# Commands to run on the management cluster

# Check Rufio logs
kubectl logs -f deployment.apps/rufio -n tink-system
kubectl get task -A
kubectl describe task/job-power-reset-node1-task-2 -n tink-system

# Check Boots logs
kubectl logs -f svc/boots -n tink-system

# Check Tinkerbell resources
kubectl get all -n tink-system
kubectl get machine -n tink-system
kubectl get hardware -n tink-system
kubectl get template -n tink-system
kubectl get workflow -n tink-system

# Check CAPI resources
kubectl get cluster -n tink-system

### Add cluster to Argo CD
# Get kubeconfig for kub-poc cluster
clusterctl get kubeconfig kub-poc -n tink-system > ~/.kube/kub-poc.kubeconfig

# Copy kubeconfig to Argo CD server pod
kubectl cp ~/.kube/kub-poc.kubeconfig -n argo-cd argo-cd-argocd-server-5c87bdc957-b5cqx:/home/argocd -c server

# Get shell into Argo CD server pod name
kubectl exec -it -n argo-cd deploy/argo-cd-argocd-server -c server -- sh -c "clear; (bash || ash || sh)"

# Argo CD login
argocd login argo-cd.mgmt.kub-poc.local \
   --username admin --password B7KrMQcqzzpwYVtI \
   --insecure
   
# Add cluster to Argo CD
argocd cluster add kub-poc-admin@kub-poc \
   --kubeconfig ./kub-poc.kubeconfig \
   --server argo-cd.mgmt.kub-poc.local \
   --insecure

# Cleanup Ceph partitions
for i in {c..g};
do 
   DISK="/dev/sd$i"
   sgdisk --zap-all $DISK 
   blkdiscard $DISK || sudo dd if=/dev/zero of="$DISK" bs=1M count=100 oflag=direct,dsync
   partprobe $DISK
done
rm -rf /var/lib/rook/*

# Commands to run on the workload cluster
export KUBECONFIG=~/.kube/kub-poc.kubeconfig

# Remove taints from master nodes
kubectl patch node kub-poc-cp -p '{"spec":{"taints":[]}}'

# Check Ceph status
kubectl -n rook-ceph get pods
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status

# Upload Windows 2022 Server image
virtctl image-upload --image-path=win2k22-kubevirt-27032022.qcow2 \
   --pvc-name=win2k22-qcow2 --access-mode=ReadWriteOnce --pvc-size=40G \
   --uploadproxy-url=https://10.100.3.51:31001 --insecure --wait-secs=60

 # Check hypervisor for Kubevirt VMs
curl -k -L https://raw.githubusercontent.com/cloudbase/checkhypervisor/master/bin/checkhypervisor -o check 
curl.exe -k -L https://raw.githubusercontent.com/cloudbase/checkhypervisor/master/bin/checkhypervisor.exe -o check.exe

# Port-forward Wordpress
kubectl port-forward svc/wordpress 8080:80 -n wordpress