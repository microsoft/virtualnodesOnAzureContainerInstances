# Security Customizations

This section provides instructions for optional security updates or supporting alternative setups. The goal is to help you enhance the security of your deployment according to your specific requirements.

## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Creating a Custom Azure Role for virtual nodes](#creating-a-custom-azure-role-for-virtual-nodes)
4. [Locking Down virtual nodes Infra](#locking-down-virtual-nodes-infra)
5. [Outbound FQDN Rules for virtual nodes](#outbound-fqdn-rules-for-virtual-nodes)
6. [Encrypting Deployment Data via Customer Managed Keys](#encrypt-deployment-data)

## Introduction

In this section, we will cover various security customizations that you can apply to your deployment. These customizations are optional and can be tailored to fit your unique security needs.

## Prerequisites

Before you begin, ensure that you have the following:

- Basic understanding of your current security setup
- Administrative access to your deployment environment
- Familiarity with security best practices

## Creating a Custom Azure Role for virtual nodes

In this section, we will guide you through the process of creating a custom Azure role with the minimum viable set of permissions required by virtual nodes, to enhance the security of your deployment. Note that this covers only the basic scenarios, and adding additional capabilities (like using PVC for Azure storage accounts) will require additional permissions to be added specific to them. 

For more information about custom roles and updating them programmatically, see [here](https://learn.microsoft.com/en-us/azure/role-based-access-control/custom-roles-cli)

### Step 1: Create the Role

Use the following Azure CLI command to create the custom role:

```powershell
# Writing JSON to file and then using splatting operator to avoid quoting issues
# see https://github.com/Azure/azure-cli/blob/dev/doc/quoting-issues-with-powershell.md for details

if(Test-Path .\role.json) { Write-Host "Exiting to not overwrite existing file"; return}

$subId = "yourSubscriptionGuid"
$targetRgName = "virtualNodesTargetResourceGroupName"
$vnetRgName = "virtualNodesVnetResourceGroupName"

'{
    "Name": "virtualnodeCustomRole",
    "Description": "More limited set of permissions that allow virtual node to still function",
    "Actions": [
        "Microsoft.ContainerInstance/containerGroups/read",
        "Microsoft.ContainerInstance/containerGroups/write",
        "Microsoft.ContainerInstance/containerGroups/delete",
        "Microsoft.ContainerInstance/containerGroups/containers/exec/action",
        "Microsoft.Network/virtualNetworks/subnets/join/action"
    ],
    "AssignableScopes": [
        "/subscriptions/$($subId)/resourcegroups/$($targetRgName)",
        "/subscriptions/$($subId)/resourcegroups/$($vnetRgName)"
    ]
}' > role.json


az role definition create --role-definition "@role.json"
```
Note the above custom role name is only a suggestion, virtual nodes don't care what the role name is... only that it has sufficient permissions to all referenced resources! 😊 But if you do use a different name, update the next step to use the role name you decided on

Assignable scopes must include the resource group your virtual nodes is configured to put ACI pods into (default - `MC_<aks rg name>_<aks cluster name>_<aks region>`) as well as the resource group that holds the VNET used by the AKS instance (default - <aks rg name>, if followed quick setup README).

### Step 2: Assign the Role

Assign the custom role to a user, group, or service principal using the following Azure CLI command:
```powershell
# retrieve the principal ID for your MI
$miRgName = "resourceGroupNameThatContainsAKSMI"
$miName = "miNameUsedForVirtualNodes"
$managedIdentityPrincipalId=$(az identity show --resource-group $miRgName --name $miName --query principalId --output tsv)

# apply the new role to all appropriate scopes
$subId = "yourSubscriptionGuid"
$targetRgName = "virtualNodesTargetResourceGroupName"
$vnetRgName = "virtualNodesVnetResourceGroupName"
az role assignment create --assignee $managedIdentityPrincipalId --role "virtualnodeCustomRole" --scope "/subscriptions/$($subId)/resourcegroups/$($targetRgName)"
az role assignment create --assignee $managedIdentityPrincipalId --role "virtualnodeCustomRole" --scope "/subscriptions/$($subId)/resourcegroups/$($vnetRgName)"
```

## Locking Down virtual nodes Infra

There are those who might want to provide extra protection for their AKS and virtual nodes infra from changes outside a limited set of accounts / services.

virtual nodes is compatible with AKS's new [NRG Lockdown](https://learn.microsoft.com/en-us/azure/aks/node-resource-group-lockdown), but requires some changes to both work when it's enabled and to provide similar protections for its resources. 

### Step 0: AKS's VNET must be outside the AKS managed RG
AKS's NRG lockdown makes it so virtual nodes is unable to join pods running in ACI with the AKS VNET if that VNET is inside the RG AKS locked down. 

The setup instructions from the virtual nodes [README](/README.md#step-2-azure-virtual-network) already recommend all users are in a state where the VNET used by AKS isn't owned by AKS itself, which makes this a non-issue. However, if you didn't follow this recommendation you will receive errors while trying to start pods in the virtual node saying they do not have permissions to join the subnet. 

A clever and determined user might work around this via other customization options for using a different VNET subnet that is not inside that AKS managed RG... either via the [node configuration](NodeCustomizations.md#default-aci-subnet-behaviors-with-a-customized-acisubnetname) or by running ALL virtual node pods with their [subnet overridden](PodCustomizations.md#using-virtual-nodes-with-multiple-subnets). However, such steps would cause AKS and the pods to no longer be running on a shared VNET and block non-public-internet communications between them, so for most users it is **strongly recommended** if running with NRG lockdown to have provided AKS their own VNET outside the AKS managed RG as directed in the initial setup instructions. 

### Step 1: Clean up the subscription's built-in roles
Subscription scoped built-in roles are inherited to all resources within the subscription, so the number of people / accounts in those built-in roles at this level should be reduced as much as possible. 

Custom roles can be instead limited to much smaller scopes and more limited permissions, so for customers who are interested in protections like lockdown they are the way to go. 

### Step 2 (Optional): Use Azure Policy to prevent new built-in role assignments
In order to keep the cleaned up built-in roles for your subscription clean going forward, you can apply an [Azure Policy](https://learn.microsoft.com/en-us/azure/governance/policy/tutorials/create-custom-policy-definition) to ensure new users cannot be assigned built-in roles. 

### Step 3: Update virtual nodes to use a separate RG
With AKS's NRG Lockdown applied, virtual nodes will be unable to place resources into the AKS locked resource group... so we need to update the virtual node configuration to use a different resource group for virtual nodes infra. 

Create a new resource group in the same subscription as the AKS cluster running virtual nodes, and then follow the steps [here](NodeCustomizations.md#changing-the-azure-resource-group-used-for-aci-resources-via-aciresourcegroupname) to customize your HELM install to configure virtual nodes to use it. Also update the AKS MI per the [above steps](#creating-a-custom-azure-role-for-virtual-nodes) to use a custom role scoped to this RG as the "target RG" to ensure continued operation.

## Outbound FQDN Rules for virtual nodes

You can reference the information below if you want to restrict outbound traffic from your virtual nodes. This section describes connectivity that is uniquely required by virtual nodes infrastructure. AKS clusters and nodes have additional requirements that are documented at [Outbound network and FQDN rules for Azure Kubernetes Service (AKS) clusters](https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress).

### Required FQDN rules

| Destination FQDN | Port | Use |
| ------------- | --- | ------------- |
| `management.azure.com`, or `Azure Resource Manager` service tag | 443 (HTTPS) | Required for the virtual node infrastructure to manage container groups that are deployed through the ACI ARM APIs for pods in the virtual node. |
| `*.atlas.cloudapp.azure.com` | 19390 (HTTPS/TCP) | Required for the virtual node infrastructure to set up initial communication with the ACI clusters where container groups are deployed. It is also used to handle communication for CRI streaming APIs such as Exec and Attach. |
| `*.atlas.cloudapp.azure.com` | 33391 (HTTPS/TCP) | Required for the virtual node infrastructure to communicate with the container runtime on the ACI clusters where container groups are deployed, for the purpose of performing lifecycle/management operations on containers. |

The ACI cluster FQDN will always have the format `<clusterName>.<regionName>.atlas.cloudapp.azure.com`, where the value of `clusterName` is unique per cluster and the value of `regionName` corresponds to the region where the ACI cluster is deployed. For instance, a FQDN for an ACI cluster in Central India may look something like `sbzip4leutnry21.centralindia.atlas.cloudapp.azure.com`.

The ACI cluster IP addresses will be assigned from the `AzureCloud` [service tag](https://learn.microsoft.com/en-us/azure/virtual-network/service-tags-overview). For those looking for a more limited scope, one could use the service tag targeted to only the region they are looking to use with ACI, which will be of the format `AzureCloud.<Region>` (EG - AzureCloud.CentralIndia). The IP address prefixes corresponding to Azure service tags can be found [here](https://www.microsoft.com/en-us/download/details.aspx?id=56519). 

Note that a single virtual node may be communicating with multiple ACI clusters - there is no guarantee of a 1:1 mapping from virtual node to ACI cluster.

## Encrypt Deployment Data
ACI's capability to use [encrypted deployment data via customer managed keys](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-encrypt-data) is now supported in virtual nodes (currently only for On-Demand usage, not yet with Standby Pools). Additional documentation can be found in the [Pod Customization section for CMK](/Docs/PodCustomizations.md#encrypting-aci-deployment-info-via-customer-managed-keys)