RG=aksiptest-RG
LOCATION=EastUS2
AKS=aksip

az group create --name $RG --location $LOCATION

az aks create --location $LOCATION --name $AKS --node-count 3  \
    --no-ssh-key --resource-group $RG --enable-managed-identity 

az aks get-credentials -n $AKS -g $RG
######
# Install ingress controller

# Set the namespace to be used 
NAMESPACE=ingress-basic

# Add the ingress-nginx repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

# Use Helm to deploy an NGINX ingress controller
# we are intentionally NOT assigning a static IP!
helm install nginx-ingress ingress-nginx/ingress-nginx \
    --create-namespace --namespace $NAMESPACE \
    --set controller.replicaCount=2 \
    --set controller.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux 

######
# Deploy 'blue' version of app
export version="blue"
envsubst < aks-helloworld.yaml |kubectl apply -f -
# kubectl port-forward svc/aks-helloworld-blue 8000:80

# Deploy 'green' version of app
export version="green"
envsubst < aks-helloworld.yaml |kubectl apply -f -
# kubectl port-forward svc/aks-helloworld-green 8001:80

# Deploy 'root' version of app
export version="root"
envsubst < aks-helloworld.yaml |kubectl apply -f -
# kubectl port-forward svc/aks-helloworld-root 8002:80


##############
# Deploy ingress
kubectl apply -f hello-ingress.yaml
kubectl get ingress
kubectl describe ingress hello-world-ingress

# get the ip address of the LB  (it's the full output, not just the ip)
DYNIP=$(kubectl get svc -n ingress-basic)
echo $DYNIP

#######
# Now let's try to redeploy with a static IP per  https://docs.microsoft.com/en-us/azure/aks/ingress-static-ip
IPNAME=testiplnc
NODERG=$(az aks show -n $AKS -g $RG -o tsv --query nodeResourceGroup)

PUBLICIP=$(az network public-ip create --resource-group $NODERG \
    --name $IPNAME --sku Standard --allocation-method static --query publicIp.ipAddress -o tsv)
echo $PUBLICIP


helm upgrade nginx-ingress ingress-nginx/ingress-nginx --namespace $NAMESPACE \
    --set controller.service.loadBalancerIP=$PUBLICIP

# This returns the old output! -> you can't add a static IP to a previously deploy LB
kubectl get svc -n ingress-basic

#### 
# lets fix this!
# first, delete the prior ingress controller
helm delete nginx-ingress -n ingress-basic

# next, recreate it with a static IP
helm install nginx-ingress ingress-nginx/ingress-nginx \
    --create-namespace --namespace $NAMESPACE \
    --set controller.replicaCount=2 \
    --set controller.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.service.loadBalancerIP=$PUBLICIP

# now, check the public IP -- this should be the static IP that was set.
kubectl get svc -n ingress-basic
