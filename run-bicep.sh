#!/bin/bash

while getopts ":p:s:g:l:" arg; do
    case $arg in
        p) ResourcePrefix=$OPTARG;;
        s) ResourceSuffix=$OPTARG;;
        g) ResourceGroupName=$OPTARG;;
        l) ResourceGroupLocation=$OPTARG;;
    esac
done

usage() {
    script_name=`basename $0`
    echo "Please use ./$script_name -p resourcePrefix -s resourceSuffix -g resourceGroupName -l resourceGroupLocation"
}

if [ -z "$ResourcePrefix" ]; then
    usage
    exit 1
fi

if [ -z "$ResourceSuffix" ]; then
    usage
    exit 1
fi

if [ -z "$ResourceGroupName" ]; then
    usage
    exit 1
fi

if [ -z "$ResourceGroupLocation" ]; then
    usage
    exit 1
fi

resourcePrefix=$ResourcePrefix
resourceSuffix=$ResourceSuffix
resourceGroupName=$ResourceGroupName
resourceGroupLocation=$ResourceGroupLocation
currentUserObjectId=$(az ad signed-in-user show --query objectId --output tsv)
versionTag=$(date | md5sum | awk '{print $1}')

az group create --name $resourceGroupName --location $resourceGroupLocation
az deployment group create --template-file ./acr.bicep --resource-group $resourceGroupName --parameters @acr.parameters.json --parameters "resourcePrefix=${resourcePrefix}" --parameters "resourceSuffix=${resourceSuffix}" --parameters "currentUserObjectId=${currentUserObjectId}"

if az keyvault secret show --vault-name "${resourcePrefix}akv${resourceSuffix}" --name "ssh-key-public" --output none; then
az keyvault secret show --vault-name "${resourcePrefix}akv${resourceSuffix}" --name "ssh-key-private" --query value --output tsv > ./key
az keyvault secret show --vault-name "${resourcePrefix}akv${resourceSuffix}" --name "ssh-key-public" --query value --output tsv > ./key.pub
else
ssh-keygen -q -m PEM -t rsa -b 4096 -N '' -f ./key
az keyvault secret set --name "ssh-key-private" --value "$(cat ./key)" --vault-name "${resourcePrefix}akv${resourceSuffix}"
az keyvault secret set --name "ssh-key-public" --value "$(cat ./key.pub)" --vault-name "${resourcePrefix}akv${resourceSuffix}"
fi

sshKeyPath="/home/azureuser/.ssh/authorized_keys"
sshPublicKey=$(cat ./key.pub)
rm key
rm key.pub

subscriptionId=$(az account show --query id --output tsv)
principalClientId=$(az identity show --resource-group ${resourceGroupName} --name ${resourcePrefix}aumi${resourceSuffix} --query clientId --output tsv)
principalObjectId=$(az identity show --resource-group ${resourceGroupName} --name ${resourcePrefix}aumi${resourceSuffix} --query principalId --output tsv)
az role assignment create --assignee $principalObjectId --scope "/subscriptions/${subscriptionId}" --role Contributor

az acr login --name "${resourcePrefix}acr${resourceSuffix}"
pushd locust-main
cp ../locustfile.py .
az acr build --image locust-main --registry "${resourcePrefix}acr${resourceSuffix}" .
popd
pushd locust-secondary
cp ../locustfile.py .
az acr build --image locust-secondary --registry "${resourcePrefix}acr${resourceSuffix}" .
popd

az deployment group create --template-file ./main.bicep --resource-group $resourceGroupName --parameters @main.parameters.json --parameters "resourcePrefix=${resourcePrefix}" --parameters "resourceSuffix=${resourceSuffix}" --parameters "resourceGroupLocation=${resourceGroupLocation}" --parameters "currentUserObjectId=${currentUserObjectId}" --parameters "sshKeyPath=${sshKeyPath}" --parameters "sshPublicKey=${sshPublicKey}" --parameters "principalClientId=${principalClientId}" --parameters "versionTag=${versionTag}"
