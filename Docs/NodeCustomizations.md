
# Node Customizations
If you would like an alternate way to install virtual nodes on ACI, the Helm chart in this repo is also published to the chart repository `https://microsoft.github.io/virtualnodesOnAzureContainerInstances/`.

Customizations to the virtual node Node configuration are generally done by modifying the values.yaml file for the HELM install and then running a `HELM upgrade` action. 

# Node Customization in HELM Values
A non-exhaustive list of configuration in the HELM's `values.yaml`, and how to use them

| value | Short Summary |
| -- | -- | 
| replicaCount | Count of VN2 node pods. See [Scaling virtual nodes Up / Down](#updated-replica-count-via-helm) for more details |
| admissionControllerReplicaCount | Count of VN2 admission controller pods. See [Scaling virtual nodes Up / Down](#updated-replica-count-via-helm) for more details |
| aciSubnetName | a comma delimited list of subnets to potentially use as the node default. See [this section on behaviors](#default-aci-subnet-behaviors-with-a-customized-acisubnetname) |

## Default ACI Subnet behaviors with a customized `aciSubnetName`
This suboptimally-named field is actually a comma delimited list of subnets to potentially use as the default for the node. 

What value does it have as a list, when the setting is intended what to use for the default subnet? One would reasonably assume they can only default to one setting!
- It allows the customer to scale outward more naturally to use multiple subnets with a single VN2 configuration. The virutal node code is configured to distribute itself so each individual node replica brought up will pick the least used subnet (with a very niave implementation, but which should still get us decent spread). This "default" subnet it picks will be used for pods which do not have a [subnet override](/Docs/PodCustomizations.md#using-virtual-nodes-with-multiple-subnets).

What values can be in this list? Each value can either be a subnet name OR a subnet resource ID
- If subnet name(s) are provided, they will be used assuming that they are within the AKS VNET. 
- If full resource IDs to the subnet are provided, they will be used as is. 
Normal VNET restrictions apply (EG - must be in same region as resources in VNET)

Can my list have both subnet names and subnet resource Ids? It can indeed!  
EG - 
``` yaml 
aciSubnetName: cg,/subscriptions/mySubGuid/resourceGroups/myAksRg/providers/Microsoft.Network/virtualNetworks/aks-vnet-25784907/subnets/cg,/subscriptions/mySubGuid/resourceGroups/myAksRg/providers/Microsoft.Network/virtualNetworks/adifferentvnet/subnets/adifferentsubnet
```

# How to run more than one type of customized virtual node in the same AKS
You may have a scenario that you want to run more than 1 virtual node HELM configuration in one AKS cluster. 

To achieve this, you will need to ensure only one of those HELM releases' value.yaml files has a non-zero replica count for the the Admission Controller, which also controls implicitly registering the web hook. The default value is 1, as it is a required service to be running for virtual node to function. 
```
admissionControllerReplicaCount: 1
```

It is also strongly recommended to update the values.yaml namespace used for deploying each virtual node configuration so each has its own unique namespace.
```
namespace: <Something unique for each config>
```

# Scaling virtual nodes Up / Down
As would be expected from K8s resources, virtual node can be scaled up or down by modifying the replica count, either in place or with a HELM update. 

The number of virtual node pods and Admission Controller pods can each be scaled seperately. The virtual node pods are responsible for most K8s interactions with the virtualized pods, and can at most support 200 pods each. The Admission Controllers are present to ensure certain state about the virtual nodes is updated for the K8s Control Plane, as well as making modifications to the pods being sent to the virtual nodes which enables some functionalities. 

For every 200 pods you wish to host in virtual node you will need to scale out an additional virtual node replica for it. 

**NOTE**: Regardless which method is used, scaling down your virtual nodes requires some manual cleanup. 

## Manual Cleanup when Scaling Down virtual node pods
If you scale DOWN replicas for the virtual node, this will remove the virtual node backing pods but it will NOT clean up the “fake” K8s Nodes and they will still appear to be “Ready” to the control plane. These will need to be manually cleaned up, via a command like 
```
kubectl delete node <nodeName>
```
To determine which are the nodes which need to be cleaned up, they would be the ones which no longer have backing pods (virtual node node names are the same as the pod backing them)… which can be queried like so: 
```
kubectl get pods -n <HELM NAMESPACE>
kubectl get nodes
```

## Updating Replica Count inplace via Kubectl
Replica count for the resources can be updated inplace via Kubectl commands, like: 
   
    kubectl scale StatefulSet <HELM RELEASE NAME> -n <HELM RELEASE NAMESPACE> --replicas=<DESIRED REPLICA COUNT>

EG: `kubectl scale StatefulSet virtualnode -n vn2 --replicas=1`

**Pitfall**: The danger with this method is if you do not align the HELM chart, the next time you apply a HELM update it will overwrite the replica acount and force a scale up / down to whatever is in the HELM. 

## Updated Replica Count via HELM
The HELM's values.yaml file has two values for controllign replica counts: 
``` yaml
replicaCount: 1
admissionControllerReplicaCount: 1 
```

`replicaCount` controls the virtual node pod replicas, while `admissionControllerReplicaCount` controls the AdmissionController pod replicas. 