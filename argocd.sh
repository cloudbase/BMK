#!/bin/bash

# create git repo in k8s (Outbound SSH not working in PoC env)
helm repo add gitea-charts https://dl.gitea.io/charts/
helm upgrade --install gitea \
   --create-namespace \
   --namespace git \
   -f config/git/values.yaml \
   gitea-charts/gitea

# install Argo CD
helm upgrade --install argo-cd \
  --create-namespace \
  --namespace argo-cd \
  -f config/argo-cd/values.yaml \
  argo-cd/argo-cd

kubectl get secret argo-cd-initial-admin-secret -n argo-cd -o jsonpath="{.data.password}" | base64 -d | pbcopy