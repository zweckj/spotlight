TENANT_ID=""
AKS_NAME=""
RG_NAME=""
IDENTITY_NAME=""
IDENTITY_CLIENT_ID=""
SA_NAME=""

az feature register --namespace "Microsoft.ContainerService" --name "EnableWorkloadIdentityPreview"

# wait for feature registration to complete
register_state=""
while [ "$register_state" != "Registered" ]; do
  sleep 10
  register_state=$(az feature show --namespace "Microsoft.ContainerService" --name "EnableWorkloadIdentityPreview" --query "properties.state" -o tsv)
done

# install helm if not installed
if ! command -v <the_command> &> /dev/null
then
    echo "helm could not be found. Installing..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

az provider register -n Microsoft.ContainerService

az aks update -n $AKS_NAME -g $RG_NAME --enable-oidc-issuer

OIDC_URL=$(az aks show --resource-group $RG_NAME --name $AKS_NAME --query "oidcIssuerProfile.issuerUrl" -o tsv)

helm repo add azure-workload-identity https://azure.github.io/azure-workload-identity/charts
helm repo update
helm install workload-identity-webhook azure-workload-identity/workload-identity-webhook \
   --namespace azure-workload-identity-system \
   --create-namespace \
   --set azureTenantID="${TENANT_ID}"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: ${IDENTITY_CLIENT_ID}
  labels:
    azure.workload.identity/use: "true"
  name: ${SA_NAME}
EOF

az identity federated-credential create \
  --name "${AKS_NAME}-federated-credential" \
  --identity-name "${IDENTITY_NAME}" \
  --resource-group "${RG_NAME}" \
  --issuer "${OIDC_URL}" \
  --subject "system:serviceaccount:default:${SA_NAME}"



