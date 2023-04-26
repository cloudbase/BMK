#!/bin/bash

set -e

function log_msg() {
  echo "$(date) - ${1}"
}

function upgrade_az_cli() {
  az upgrade --yes
}

function install_extensions_az_cli() {
    az extension add --upgrade --yes -n connectedk8s
    az extension add --upgrade --yes -n customlocation
    az extension add --upgrade --yes -n k8s-extension
    # az extension remove -n appservice-kube || true
    az extension add --upgrade --yes -n appservice-kube
}

function register_azure_providers() {
    az provider register --namespace Microsoft.Kubernetes --wait
    az provider register --namespace Microsoft.KubernetesConfiguration --wait
    az provider register --namespace Microsoft.ExtendedLocation --wait
    az provider register --namespace Microsoft.Web --wait

    az provider show -n Microsoft.Kubernetes --query "[registrationState,resourceTypes[?resourceType=='connectedClusters'].locations]"
    az provider show -n Microsoft.Web --query "resourceTypes[?resourceType=='kubeEnvironments'].locations"
}

function connect_cluster() {
    log_msg "Connected cluster create..."
    az connectedk8s show \
        --resource-group $groupName \
        --name $clusterName 1>/dev/null 2>/dev/null \
        || az connectedk8s connect \
            --resource-group $groupName \
            --name $clusterName

    connectedk8sId=$(az connectedk8s show \
        --name $clusterName \
        --resource-group $groupName \
        --query id \
        --output tsv)

    az resource wait --ids $connectedk8sId \
        --custom "properties.provisioningState=='Succeeded'" \
        --api-version "2022-10-01-preview"

    log_msg "Connected cluster created: ${connectedk8sId}"
}

function create_log_analytics() {
    log_msg "Log analytics workspace create..."
    az monitor log-analytics workspace show \
        --resource-group $groupName \
        --workspace-name $workspaceName 1>/dev/null 2>/dev/null \
        || az monitor log-analytics workspace create \
            --resource-group $groupName \
            --workspace-name $workspaceName

    logAnalyticsId=$(az monitor log-analytics workspace show \
        --resource-group $groupName \
        --workspace-name $workspaceName \
        --query id \
        --output tsv)

    az resource wait --ids $logAnalyticsId \
        --custom "properties.provisioningState=='Succeeded'" \
        --api-version "2022-10-01"

    logAnalyticsWorkspaceId=$(az monitor log-analytics workspace show \
        --resource-group $groupName \
        --workspace-name $workspaceName \
        --query customerId \
        --output tsv)
    
    export logAnalyticsWorkspaceIdEnc=$(printf %s $logAnalyticsWorkspaceId | base64 -w0) # Needed for the next step
    logAnalyticsKey=$(az monitor log-analytics workspace get-shared-keys \
        --resource-group $groupName \
        --workspace-name $workspaceName \
        --query primarySharedKey \
        --output tsv)
    export logAnalyticsKeyEnc=$(printf %s $logAnalyticsKey | base64 -w0) # Needed for the next step
    log_msg "Log analytics workspace created: ${logAnalyticsId}"
}

function create_extension() {
    log_msg "Cluster extension install..."
    az k8s-extension show \
        --cluster-type connectedClusters \
        --cluster-name $clusterName \
        --resource-group $groupName \
        --name $extensionName 1>/dev/null 2>/dev/null \
	|| az k8s-extension create \
        --resource-group $groupName \
        --name $extensionName \
        --cluster-type connectedClusters \
        --cluster-name $clusterName \
        --extension-type 'Microsoft.Web.Appservice' \
        --release-train stable \
        --auto-upgrade-minor-version true \
        --scope cluster \
        --release-namespace $namespace \
        --configuration-settings "Microsoft.CustomLocation.ServiceAccount=default" \
        --configuration-settings "appsNamespace=${namespace}" \
        --configuration-settings "clusterName=${kubeEnvironmentName}" \
        --configuration-settings "keda.enabled=true" \
        --configuration-settings "buildService.storageClassName=${storageClassName}" \
        --configuration-settings "buildService.storageAccessMode=ReadWriteOnce" \
        --configuration-settings "customConfigMap=${namespace}/kube-environment-config" \
        --configuration-settings "logProcessor.appLogs.destination=log-analytics" \
        --config-protected-settings "logProcessor.appLogs.logAnalyticsConfig.customerId=${logAnalyticsWorkspaceIdEnc}" \
        --config-protected-settings "logProcessor.appLogs.logAnalyticsConfig.sharedKey=${logAnalyticsKeyEnc}"

    extensionId=$(az k8s-extension show \
        --cluster-type connectedClusters \
        --cluster-name $clusterName \
        --resource-group $groupName \
        --name $extensionName \
        --query id \
        --output tsv)

    az resource wait --ids $extensionId \
        --custom "properties.installState=='Installed'" \
        --api-version "2020-07-01-preview"
    log_msg "Cluster extension installed: ${extensionId}"
}

function create_custom_location() {

    log_msg "Custom location create.."
    connectedClusterId=$(az connectedk8s show \
        --resource-group $groupName \
        --name $clusterName \
        --query id \
        --output tsv)

    az customlocation show \
        --resource-group $groupName \
        --name $customLocationName 1>/dev/null 2>/dev/null \
    || az customlocation create \
        --resource-group $groupName \
        --name $customLocationName \
        --host-resource-id $connectedClusterId \
        --namespace $namespace \
        --cluster-extension-ids $extensionId

    export customLocationId=$(az customlocation show \
        --resource-group $groupName \
        --name $customLocationName \
        --query id \
        --output tsv)

    az resource wait --ids $customLocationId \
        --custom "properties.provisioningState=='Succeeded'" \
        --api-version "2021-08-31-preview"
    log_msg "Custom location created: ${customLocationId}"
}

function create_kube_app_service() {

    log_msg "Appservice kube create..."
    az appservice kube show \
        --resource-group $groupName \
        --name $kubeEnvironmentName 1>/dev/null 2>/dev/null \
    || az appservice kube create \
        --resource-group $groupName \
        --name $kubeEnvironmentName \
        --custom-location $customLocationId
    
    appserviceId=$(az appservice kube show \
        --resource-group $groupName \
        --name $kubeEnvironmentName \
        --query id \
        --output tsv)

    export appserviceDomain=$(az appservice kube show \
        --resource-group $groupName \
        --name $kubeEnvironmentName \
        --query defaultDomain \
        --output tsv)
    
    az resource wait --ids $appserviceId \
        --custom "properties.provisioningState=='Succeeded'" \
        --api-version "2022-09-01"
    log_msg "Appservice kube created ${kubeEnvironmentName} with domain ${appserviceDomain}: ${appserviceId}"
}

function deploy_test_app() {
    log_msg "Application create..."
    az webapp show \
        --resource-group $groupName \
        --name $appName 1>/dev/null 2>/dev/null \
    ||  az webapp create \
        --resource-group $groupName \
        --name $appName \
        --custom-location $customLocationId \
        --runtime 'NODE|14-lts'

    az webapp config appsettings set \
         --resource-group $groupName --name $appName \
         --settings SCM_DO_BUILD_DURING_DEPLOYMENT=true 1>/dev/null
    rm -rf /tmp/nodejs-docs-hello-world || true
    git clone https://github.com/Azure-Samples/nodejs-docs-hello-world /tmp/nodejs-docs-hello-world --quiet
    pushd /tmp/nodejs-docs-hello-world
      zip -r package.zip . 1>/dev/null
      az webapp deployment source config-zip --resource-group $groupName --name $appName --src package.zip || true
      rm -rf /tmp/nodejs-docs-hello-world
    popd

    log_msg "Application ${appName} deployed at https://${appName}.${appserviceDomain}"
}

function deploy_test_container() {
    appName="$clusterName-aspnetapp1"
    log_msg "Application from mcr.microsoft.com/dotnet/samples:aspnetapp container create..."
    az webapp show \
        --resource-group $groupName \
        --name $appName 1>/dev/null 2>/dev/null \
    ||  az webapp create \
        --resource-group $groupName \
        --name $appName \
        --custom-location $customLocationId \
        --deployment-container-image-name mcr.microsoft.com/dotnet/samples:aspnetapp

    log_msg "Application ${appName} deployed at https://${appName}.${appserviceDomain}"
}

function deploy_test_container_aspnet() {
    log_msg "Application from mcr.microsoft.com/dotnet/samples:aspnetapp container create..."
    az webapp show \
        --resource-group $groupName \
        --name $appNameContainer 1>/dev/null 2>/dev/null \
    ||  az webapp create \
        --resource-group $groupName \
        --name $appNameContainer \
        --custom-location $customLocationId \
        --deployment-container-image-name mcr.microsoft.com/dotnet/samples:aspnetapp

    log_msg "Application ${appNameContainer} deployed at https://${appNameContainer}.${appserviceDomain}"
}

function deploy_test_container_mssql() {
    log_msg "Application from mcr.microsoft.com/mssql/server:2022-latest container create"
    az webapp show \
        --resource-group $groupName \
        --name $appNameContainerMssql 1>/dev/null 2>/dev/null \
    ||  az webapp create \
        --resource-group $groupName \
        --name $appNameContainerMssql \
        --custom-location $customLocationId \
        --deployment-container-image-name mcr.microsoft.com/mssql/server:2022-latest

    log_msg "Application ${appNameContainer} deployed"
}


function prepare_variables() {
  export groupName="aks-metal"
  export clusterName="kub-poc"
  export extensionName="appservice-ext"
  export namespace="appservice-ns"
  export storageClassName="ceph-block"

  export workspaceName="$clusterName-workspace"
  export kubeEnvironmentName="$clusterName-kube-environment"
  export customLocationName="$clusterName-customloc"
  export appName="$clusterName-nodejsapp1"
  export appNameContainer="$clusterName-aspnetapp1"
  export appNameContainerMssql="$clusterName-mssql2022v1"
}

function main() {

  upgrade_az_cli
  install_extensions_az_cli
  register_azure_providers

  prepare_variables
  connect_cluster
  create_log_analytics
  create_extension
  create_custom_location
  create_kube_app_service
  deploy_test_container_aspnet
  
  deploy_test_container_mssql
  deploy_test_app
}

main
