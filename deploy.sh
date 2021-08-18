RG=aksiptest-RG
LOCATION=EastUS2
AKS=aksip

az group create --name $RG --location $LOCATION

az aks create --location $LOCATION --name $AKS --node-count 3  \
    --no-ssh-key --resource-group $RG --enable-managed-identity 

