# High Scale Best Practices

**This section is for 2K+ pods on virtual node, and high deployment rates in order of 1K pods/minute. If you are not at this scale, it is unlikely that you need these optimizations.**

**Work with the ACI team to get quota and capacity provisioned for high scale testing.** You can see the default quota limits at [ACI Resource Availability & Quota documentation](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-resource-and-quota-limits). To request more quota and capacity, create a support request in Azure Portal with the following parameters:

- Issue type: Service and subscription limits (quotas)
- Quota type: Other Requests
- Description: please answer the following questions
  1. What is your team/product name?
  2. Will you deploy confidential or non-confidential pods in virtual nodes?
  3. For each subscription ID you will use with virtual nodes, please specify the region (and availability zones, if applicable) you plan to use, the number of pods that will be simultaneously running, and the size (CPU/memory) of each pod.
  4. Do these values represent steady state load/peak load? Is your traffic pattern generally more consistent or bursty?
  5. Do these values have any buffer already built into them? If so, how much?

Given that virtual node runs the workloads remotely, here are a few guidelines to work around scaling bottlenecks.


## Kube-Proxy
Kube-Proxy is a k8s component that facilitates service discovery. On node pools, it works as a daemonset, watches the api-server for service changes, and applies iptables rules. In virtual node, we inject kube-proxy as a sidecar in each pod. The problem at large scale is that the number of api-server listeners chokes the api-server.

**Recommendation**: [Opt-out of kube-proxy](/Docs/PodCustomizations.md#disable-kube-proxy). As an alternative for service discovery, use internal load balancer services and external-dns.

## Use workload identity to authenticate with Azure resources

If your application requires access to Azure resources such as storage, service bus, key vault etc, you need to follow this guide to create a workload identity in AKS which will federate with an Azure user assigned identity (UAI). Steps to take: 
1.	Enable OIDC issuer and workload identity in your AKS cluster.
```    
az aks update -g "${RESOURCE_GROUP}" -n "${CLUSTER_NAME}" --enable-oidc-issuer
az aks update -g "${RESOURCE_GROUP}" -n "${CLUSTER_NAME}" --enable-workload-identity
```
2.	Create a UAI in Azure and export the client identifier.
```    
az identity create --resource-group "${RESOURCE_GROUP}" --name "${USER_ASSIGNED_IDENTITY_NAME}"

export USER_ASSIGNED_CLIENT_ID="$(az identity show --resource-group "${RESOURCE_GROUP}" --name "${USER_ASSIGNED_IDENTITY_NAME}" --query 'clientId' --output tsv)"
```
3. 	Create an AKS service account linked to the UAI and federate it

``` bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "${USER_ASSIGNED_CLIENT_ID}"
  name: "${SERVICE_ACCOUNT_NAME}"
  namespace: "${SERVICE_ACCOUNT_NAMESPACE}"
EOF
```
```
az identity federated-credential create --name ${FEDERATED_IDENTITY_CREDENTIAL_NAME} --identity-name "${USER_ASSIGNED_IDENTITY_NAME}" --resource-group "${RESOURCE_GROUP}" --issuer "${AKS_OIDC_ISSUER}" --subject system:serviceaccount:"${SERVICE_ACCOUNT_NAMESPACE}":"${SERVICE_ACCOUNT_NAME}" --audience api://AzureADTokenExchange
```
4.	Include labels in your pod spec to use the workload identity.
``` yaml
…
metadata
  labels:
      azure.workload.identity/use: "true"  # Required. Only pods with this label can use workload identity.
…
spec:
  serviceAccountName: ${SERVICE_ACCOUNT_NAME}
```

5.	Use Azure.Identity nupkg in your app and deploy a container.
