# Virtual Node on Azure Container Instances

Virtual Node on Azure Container Instances is an evolution on the existing [Virtual Node](https://learn.microsoft.com/en-us/azure/aks/virtual-nodes) offering for Azure Kuberenetes Service (AKS). It has been reimplemented from the ground up to be closer to vanilla K8s and remove limitations of the prior impementation while also allowing deeper integration with the existing container offerings in Azure Container Instances! It should be noted, this application and installation only works when hosted on the Azure Kubernetes Service (AKS)!

Virtual Node on Azure Container Instances was featured in the Azure Kubernetes Service (AKS) Keynote at KubeCon, with a [segment detailing its numerous improvements and showing a demo](https://www.youtube.com/watch?v=yJOc3D52_Is&t=2330s).

For the rest of this document "Virtual Node" will refer to this new implementation, with "Prior Virtual Node" refering to the previous implementation. 

## Limitations of the Prior Virtual Node vs. this Virtual Node on Azure Container Instances

The following is the documentated limitations of the Prior Virtual Node from [Use virtual nodes - Azure Kubernetes Service | Microsoft Learn](https://learn.microsoft.com/en-us/azure/aks/virtual-nodes#limitations) with their status in the new Virtual Node:

No longer a limitation
- VNet peering, outbound traffic to the internet with network security groups
- Init containers
- Host aliases
- Arguments for exec in ACI
- Persistent volumes and persistent volume claims
- Container hooks

Will be fixed by General Availability
- Using service principal to pull ACR images

Can be addressed in the future
- Kubernetes network policies
- Using IPv6
- Windows containers
- Port Forwarding

Hard limitations
- DaemonSets
- Virtual nodes require AKS clusters with Azure CNI networking (you can use an AKS cluster without VNET but won’t have pod-to-pod communication)
- Using API server authorized IP ranges for AKS (because of the subnet delegation to ACI)

# Setting up a Virtual Node Environment
So we are sure you are excited to try it out for yourself! Here are what you will need to be successful getting your first Virtual Node environment up and running in AKS! 
## Prerequisites
### Tools installed:
- HELM
- Azure CLI
- Kubectl (version 1.29+)
- Git
### Misc
- Azure subscription 

## Limitations
### Product Limitations
Will be fixed by General Availability
- Using service principal to pull ACR images

Can be addressed in the future
- Kubernetes network policies
- Using IPv6
- Windows containers
- Port-Forwarding

Hard limitations
- DaemonSets
- Virtual nodes require AKS clusters with Azure CNI networking (you can use an AKS cluster without VNET but won’t have pod-to-pod communication)
- Using API server authorized IP ranges for AKS (because of the subnet delegation to ACI)

### Region Deployments
Infrastructure for Virtual Node is not widely deployed yet. 

Regions enabled for Virtual Node for both Confidential and non-Confidential usage: 
- Central India
- East Asia
- East US
- East US 2 EUAP
- Germany West Central
- Italy North
- Japan East
- North EU
- Southeast Asia
- Swiss North
- UAE North
- West EU
- West US

## Configuration Considerations
### Virtual Node Resourcing
- Each virtual node requires 3 cores and 12 GB on one of the AKS cluster’s VMs.
- Each virtual node supports 200 pods.
- Ensure you have enough ACI Quota for the pods you want to run. [ACI Resource Availability & Quota documentation](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-resource-and-quota-limits)
- Other AKS service limits are documented at [Limits for resources, SKUs, and regions in Azure Kubernetes Service (AKS) - Azure Kubernetes Service | Microsoft Learn](https://learn.microsoft.com/en-us/azure/aks/quotas-skus-regions#service-quotas-and-limits).

## Setup Infra - AKS
Everything in this section should only have to be done once to set up the AKS environment to deploy VirtualNode into

### Step 1: Azure Resource Group

Not strictly required but we recommend setting up a new resource group to keep components of environment together as well as to put the ACI workload into. Must exist within the Azure Subscription from Prereqs, and placed into the Region from Limitations. 

### Step 2: Azure Virtual Network

Create a new VNet within the new Resource Group, using the same Subscription and Region. 

Requirements: 
- Default subnet must contain 10.0.0.0/24. 
- "aks" subnet must be large enough to accommodate AKS’s address space (CIDR /16)
- “cg” subnet must be 
  - large enough to accommodate all the customer pods you wish to deploy to Virtual Node concurrently. Recommend CIDR /16 because why not 😊
  - Add Subnet Delegation for Microsoft.ContainerInstance/containerGroups

||
|--|
|**IMPORTANT**: The above subnet name (`cg`) with the subnet delegation must be used exactly, as those are the default values in the HELM values.yaml file. Using any other value will require other deployment changes. |
||

VNet needs to have address spaces to put 3 subnets in. Suggested configuration of address spaces:

![Vnet Address Spaces](/Docs/Pictures/vn_vnet_addrspace.png)

Suggested configuration of subnets: 

![Vnet subnets](/Docs/Pictures/vn_vnet_subnet.png)

||
|--|
|**IMPORTANT**: If your pods running in Virtual Node need outbound networking, you **must** set up a NAT gateway and hook it up to the "cg" subnet for ACI to use. [Instructions on how to set up a NAT Gateway with ACI](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-nat-gateway)|
||

### Step 3: Azure Kubernetes Service
Create a new AKS cluster from Azure Portal, in the same RG from Step 1. Must be created using Subscription and Region from Prereqs. Must be configured to use network plugin “Azure CNI Node Subnet”, the VNET from Step 2, with the cluster to use the AKS subnet already created, and service CIDR / DNS need to be configured to be outside the existing VNET subnets. Use Kubernetes version 1.28.* and automatic upgrade to “enabled with patch”. Nodes selected for AKS must be at least 4 CPU and 16 GB RAM to accomodate Virtual Nodes being run on them, though they can be larger. 

Arrows added to below pictures for the important fields

#### AKS Basics Tab

![AKS Basics](/Docs/Pictures/vn_aks_basics.png)

^ Must be created using Subscription from Prereqs and Region from Limitations.
^ Use Kubernetes version 1.28.* and automatic upgrade to “enabled with patch”

#### AKS Node Pools Tab

![AKS Nodes](/Docs/Pictures/vn_aks_nodepool.png)

^ Check the Node Pool VM type
^ Do not select "Virtual Nodes", this is the previous implementation!

![AKS Nodes Size](/Docs/Pictures/vn_aks_nodepool_size.png)

^ Ensure at least 4 CPU and 16 GB

#### AKS Networking Tab:

![AKS Networking](/Docs/Pictures/vn_aks_networking.png)

^ Must be configured to use network plugin “Azure CNI Node Subnet”, the VNET from Step 2, the cluster to use the AKS subnet already created, and service CIDR / DNS need to be configured to be outside the existing VNET subnets.

### Step 4: Update AKS' Managed Identity
AKS will have created resources for it to use for the cluster created in Step 3. By default, they will be created in a new RG of the form `MC_(The RG name from Step 1)_(AKS name from Step 3)_(Region from Steps 1-3)`. As an example: `MC_my-test-aks_test-rg_centralindia`


That RG will have a managed identity in it already, called “(AKS name from Step 3)-agentpool”. We will be modifying that to have permissions to create ACI CGs. Select it. 

![AKS MI Modification](/Docs/Pictures/vn_mi.png)

Within it, select the Azure role assignments pane, and hit the button to add a new role assignment. 

Select Scope Resource Group, Use the subscription from steps 1-3 and the new MC_... Resource Group that the Managed Identity belongs to (will likely autopopulate). Provide it with the role of Contributor, and then hit Save (on the left portion of the screen that opened from the Add Role Assignments button… at the bottom of the screen). 

||
|--|
|**NOTE**: If the cluster VNet is not in the MC_* resourcegroup, <u>as would be the case if you are following the quick-start setup instructions on this README.md</u>, we must also give the AKS Managed Identity permissions to the resource group it is in: 

`You will need to repeat the above steps in this section ( Step 4: Update AKS' Managed Identity) for the VNet’s resource group (from Step 1: Azure Resource Group). This is needed to allow Virtual Node to inject container groups in the VNet.` |
|--|

## Installing the Virtual Node Application via HELM 
### Step 0: Configure Pre-reqs
Use Azure CLI to pull down configuration and credentials for the AKS cluster you created above, which will save them to a location that kubectl. Additionallty, we will permission your subscription to allow Azure ContainerInstance usage: 

    az login

    az account set --subscription <yourSubscription>

    az aks get-credentials --name <yourAksName> --resource-group <yourResourceGroup>

    az provider register -n Microsoft.ContainerInstance

### Step 1: Get the HELM Chart
Clone this repo! 

### Step 2: Install Virtual Node Via HELM
And then install the HELM chart, where you can pick whatever release name you want to keep track of the HELM deployment!

    helm install <yourReleaseName> <GitRepoRoot>\Helm

### Step 3: Validate it's ready for use
A new virtual node should be registered and be in state Ready. Might take on the order of 45 seconds for everything it needs to be in order so K8s marks the node as ready 

    kubectl get nodes

![Kubectl Virtual Node Ready](/Docs/Pictures/vn_k8s_nodeready.png)

**Note**: the name above will match the release name you used for your HELM install, followed by a `-0` for the first replica. 

# Deploy your first pod to a Virtual Node
Virtual nodes are like all K8s nodes in that you can check them via K8s commands to see what their names, taints and labels are... to be used with the various K8s ways of specifying where you want your containers to be hosted!

Let's start with a simple example YAML: 
``` yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:    
  name: demo-pod
spec:
  containers:
  - command:
    - /bin/bash
    - -c
    - 'counter=1; while true; do echo "Hello, World! Counter: $counter"; counter=$((counter+1)); sleep 1; done'
    image: mcr.microsoft.com/azure-cli
    name: hello-world-counter
    resources:
      limits:
        cpu: 2250m
        memory: 2256Mi
      requests:
        cpu: 100m
        memory: 128Mi
  nodeSelector:
    virtualization: virtualnode2
  tolerations:
  - effect: NoSchedule
    key: virtual-kubelet.io/provider
    operator: Exists
```

Then you can interact with it as you would a "normal" K8s pod!

EG: if you wanted to the pod status and events (useful for finding errors!)

    kubectl describe pods demo-pod

EG: if you wanted to view logs

    kubectl logs demo-pod

EG: wanted to shell in to the pod 

    kubectl exec demo-pod -it -- /bin/bash

# Next Steps
Now you have a basic grounding to be able to run K8s pods on your Virtual Node, and you can utilize most K8s capabilities and constructs on those pods out of box! But maybe you are looking for more?

If you are looking to utilize Virtual Node specific capabilities or behaviors for your pods, [check out the Pod Customizations](Docs/PodCustomizations.md)

If you are looking to customize your Virtual Node installation, [check out the Node Customizations](Docs/NodeCustomizations.md)

If you are planning to run at high scale (thousands of pods per minute), we have a [section with best practices and recommendations!](Docs/HighScaleBestPractices.md)

Need Support?  [File a support request via Azure Portal](https://aka.ms/azuresupport)

---
### Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.