# Node Customizations
If you would like an alternate way to install virtual nodes on ACI, the Helm chart in this repo is also published to the chart repository `https://microsoft.github.io/virtualnodesOnAzureContainerInstances/`.

Customizations to the virtual node Node configuration are generally done by modifying the values.yaml file for the HELM install and then running a `HELM upgrade` action. 

High Level Section List for convenient jumping:

- [Standby Pools](#standby-pools)
  - [Preparing](#prepare-subscription)
  - [Configure / Install](#install-vn2-with-standby-pools)
  - [Image Caching](#image-caching)
- [Node Customizations](#non-standbypool-node-customizations)
- [Running Multiple Customized virtual nodes](#how-to-run-more-than-one-type-of-customized-virtual-node-in-the-same-aks)
- [Scaling virtual nodes Up / Down](#scaling-virtual-nodes-up--down)


# Standby Pools
For fast boot latency, Standby Pools allows ACI to pre-create UVMs and cache the images on them. General information about Standby Pools can be [found here](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-standby-pool-overview)

## Prepare subscription
### Register the below providers to get access: 
``` bash
Register-AzResourceProvider -ProviderNameSpace Microsoft.ContainerInstance
Register-AzResourceProvider -ProviderNamespace Microsoft.StandbyPool
Register-AzProviderFeature -FeatureName StandbyContainerGroupPoolPreview -ProviderNamespace Microsoft.StandbyPool
```
### Configure the appropriate RBAC roles:
1.	In the Azure Portal, navigate to your subscriptions.
2.	Select the subscription you want to adjust RBAC permissions.
3.	Select Access Control (IAM).
4.	Select Add -> Add Custom Role.
5.	Name your role ContainersContributor.
6.	Move to the Permissions Tab.
7.	Select Add Permissions.
8.	Search for Microsoft.Container and select Microsoft Container Instance.
9.	Search for Microsoft.Network/virtualNetworks/subnets/join/action and select it.
10.	Select the permissions box to select all the permissions available.
11.	Select Add.
12.	Select Review + create.
13.	Select Create.
14.	Select Add -> Add role assignment
15.	Under the roles tab, search for the custom role you created earlier called ContainersContributor and select it
16.	Move to the Members tab
17.	Select + Select Members
18.	Search for Standby Pool Resource Provider.
19.	Select the Standby Pool Resource Provider and select Review + Assign.
20.	If you do not have Contributor/ Owner/ Administrator roles to the subscription you are using ACI Pools for, you will also need to setup StandbyPools RBAC roles (Standby Pool create, reads, etc.) and assign to yourself.

## Install VN2 with Standby Pools
Modify the Helm chart values.yaml to set up the standby pools using the below parameters.
| value | Short Summary |
| -- | -- | 
| sandboxProviderType | Indicates if virtual node is configured to use standby pools with `StandbyPool`, or `OnDemand` (the default) if not |
| standbyPool.standbyPoolsCpu | How many cores to allocate for each standby pool UVM |
| standbyPool.standbyPoolsMemory | Memory in GB  to allocate for each standby pool UVM |
| standbyPool.maxReadyCapacity | Number of warm, unused UVMs the standby pool will try to keep ready at all times |
| standbyPool.ccePolicy | Set the cce policy for pods that will be applied to pods running on this node if standby pool is used. This policy is applied to the standby pool UVMs. |
| standbyPool.zones | Semi-colon delimited list of zone names for the standby pool to ready UVMs in. |

**Some Notes**, to be explicit on how standby pools move the above settings into the node level:
- If using standby pools, the UVM size will be predetermined by this VN2 configuration, regardless of what the requested pod size is.
- If using standby pools, CCE policy is set at the node level. All pods scheduled to the node should have the same exact matching policy. If the pod has no policy specified it will run with the node's policy. If the pod has a policy specified, it has to match the node's policy or a client side validation will fail the pod creation. 

## Image Caching
To cache an image to your standby pool, you will need to create a pod with annotation 
```yaml
"microsoft.containerinstance.virtualnode.imagecachepod": "true"
```
and schedule it on the virtual node(s). When the virtual nodes see this annotation it will not actually activate this pod, but rather list the images in it and cache them on every standby pool UVM. A pod could have multiple images and also multiple pods could be defined. Any image credential type would work as well.

If this pod is deleted, the virtual node will stop ensuring the images contained in it are pre-cached into the standby pool for the node.

Example Pod YAML: 
``` yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:   
    microsoft.containerinstance.virtualnode.imagecachepod: "true"
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

# Non-StandbyPool Node customizations
A non-exhaustive list of non-standby-pool specific configuration values available, and how to use them

| value | Short Summary |
| -- | -- | 
| replicaCount | Count of VN2 node pods. See [Scaling virtual nodes Up / Down](#updated-replica-count-via-helm) for more details |
| admissionControllerReplicaCount | Count of VN2 admission controller pods. See [Scaling virtual nodes Up / Down](#updated-replica-count-via-helm) for more details |
| aciSubnetName | a comma delimited list of subnets to potentially use as the node default. See [this section on behaviors](#default-aci-subnet-behaviors-with-a-customized-acisubnetname) |
| aciResourceGroupName | the name of the Azure Resource Group to put virtual node's ACI CGs into. See [this section on behaviors](#changing-the-azure-resource-group-used-for-aci-resources-via-aciresourcegroupname) |
| zones | a semi-colon delimited list of Azure Zones to deploy pods to. See [this section on behaviors](#default-azure-zone-behaviors-with-a-customized-zones) |
| priorityClassName | Name of the Kubernetes Priority Class to assign to the virtual node pods. See [Using Priority Classes](#using-priority-classes) for more details |
| admissionControllerPriorityClassName | Name of the Kubernetes Priority Class to assign to the VN2 admission controller pods. See [Using Priority Classes](#using-priority-classes) for more details |
| podDisruptionBudget | Configurations for the Kubernetes Pod Disruption Budget (PDB) resource to use for the virtual node deployment. See [Kubernetes documentation](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) for available fields. |
| admissionControllerPodDisruptionBudget | Configurations for the Kubernetes Pod Disruption Budget (PDB) resource to use for the VN2 admission controller deployment. See [Kubernetes documentation](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) for available fields. |

## Default ACI Subnet behaviors with a customized `aciSubnetName`
This suboptimally-named field is actually a comma delimited list of subnets to potentially use as the default for the node. 

What value does it have as a list, when the setting is intended what to use for the default subnet? One would reasonably assume they can only default to one setting!
- It allows the customer to scale outward more naturally to use multiple subnets with a single VN2 configuration. The virtual node code is configured to distribute itself so each individual node replica brought up will pick the least used subnet (with a very naive implementation, but which should still get us decent spread). This "default" subnet it picks will be used for pods which do not have a [subnet override](/Docs/PodCustomizations.md#using-virtual-nodes-with-multiple-subnets), AND like most node settings will also be used by the Node's Standby Pool for its configuration, if it is enabled.

What values can be in this list? Each value can either be a subnet name OR a subnet resource ID
- If subnet name(s) are provided, they will be used assuming that they are within the AKS VNET. 
- If full resource IDs to the subnet are provided, they will be used as is. 
Normal VNET restrictions apply (EG - must be in same region as resources in VNET)

Can my list have both subnet names and subnet resource Ids? It can indeed!  
EG - 
``` yaml 
aciSubnetName: cg,/subscriptions/mySubGuid/resourceGroups/myAksRg/providers/Microsoft.Network/virtualNetworks/aks-vnet-25784907/subnets/cg,/subscriptions/mySubGuid/resourceGroups/myAksRg/providers/Microsoft.Network/virtualNetworks/adifferentvnet/subnets/adifferentsubnet
```

## Changing the Azure Resource Group used for ACI resources via `aciResourceGroupName`
By default virtual node will put its ACI resources into the same resource group as the AKS infrastructure (default AKS RG name `MC_<aks rg name>_<aks cluster name>_<aks region>`). However, this behavior can be controlled by updating the HELM value `aciResourceGroupName`

When empty the default will be used, but if overridden it should just contain the name of the desired resource group, which must exist within the same subscription as the AKS cluster virtual nodes is being used with. 

**IMPORTANT** Customers must ensure that if this override is used that they do not reuse the same RG for multiple AKS's virtual node targets! The product is actively managing the target RG and ensuring it matches what it expects, so if multiple virtual nodes deployed to different AKS are all targeting the same `aciResourceGroupName` they can and will fight with each other! But this is not an issue with multiple virtual nodes within the same AKS cluster.

``` yaml 
aciResourceGroupName: my_great_rg_name
```

## Default Azure Zone behaviors with a customized `zones`
Azure has a concept of [Availability Zones](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview?tabs=azure-cli), which are separated groups of datacenters that exist within the same region. If your scenario calls for it, you can specify a zone for your pods to be hosted on within your given region. 

``` yaml 
zones: '<semi-colon delimited string of zones>'
```

**NOTE**: Today, ACI only supports providing a single zone as part of the request to allocate a sandbox for your pod. If you provide multiple, you should get an informative error effectively saying you can only provide one. 

This setting applies a node level default zone, so pods which do not have a [pod level annotation for zone](/Docs/PodCustomizations.md#zones) will have this applied. When set with an empty string, no zones will be used as this default. 

## Using Priority Classes

If you would like to use [Kubernetes Priority Classes](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/) with the virtual node pods, you can specify the name of the priority class to use in the `values.yaml` file for the HELM chart using the following settings:

``` yaml
priorityClassName: <name of priority class for virtual node infra pods>
admissionControllerPriorityClassName: <name of priority class for admission controller pods>
```

`priorityClassName` will be used for the virtual node infra pods, while `admissionControllerPriorityClassName` will be used for the Admission Controller pods.

> IMPORTANT: if you specify a priority class name that does not exist in the cluster, the virtual node infra pods will fail to start. Ensure that the specified priority class exists in the cluster before deploying the virtual node infra pods. The assigned priority classes should also exist as long as the virtual nodes infra pods are running.

An example of how to create a priority class in Kubernetes is as follows:

``` yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-virtnode
value: 1000000
globalDefault: false
description: "This priority class should be used for virtual node infra pods only."
```

You can then set the priority class names in the `values.yaml` file:

``` yaml
priorityClassName: high-priority-virtnode
admissionControllerPriorityClassName: high-priority-virtnode
```

Setting separate priority class names for the virtual node pods and the admission controller pods is also possible. You can also specify an existing priority class name that was separately created in the cluster.

# How to run more than one type of customized virtual node in the same AKS
You may have a scenario that you want to run more than 1 virtual node HELM configuration in one AKS cluster. 

To achieve this, you will need to ensure only one of those HELM releases' value.yaml files has a non-zero replica count for the Admission Controller, which also controls implicitly registering the web hook. The default value is 1, as it is a required service to be running for virtual node to function. 
```
admissionControllerReplicaCount: 1
```

It is also strongly recommended to update the values.yaml namespace used for deploying each virtual node configuration so each has its own unique namespace.
```
namespace: <Something unique for each config>
```

# Scaling virtual nodes Up / Down
As would be expected from K8s resources, virtual node can be scaled up or down by modifying the replica count, either in place or with a HELM update. 

The number of virtual node pods and Admission Controller pods can each be scaled separately. The virtual node pods are responsible for most K8s interactions with the virtualized pods, and can at most support 200 pods each. The Admission Controllers are present to ensure certain state about the virtual nodes is updated for the K8s Control Plane, as well as making modifications to the pods being sent to the virtual nodes which enables some functionalities. 

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

## Updating Replica Count in-place via Kubectl
Replica count for the resources can be updated in-place via Kubectl commands, like: 
   
    kubectl scale StatefulSet <HELM RELEASE NAME> -n <HELM RELEASE NAMESPACE> --replicas=<DESIRED REPLICA COUNT>

EG: `kubectl scale StatefulSet virtualnode -n vn2 --replicas=1`

**Pitfall**: The danger with this method is if you do not align the HELM chart, the next time you apply a HELM update it will overwrite the replica count and force a scale up / down to whatever is in the HELM. 

## Updated Replica Count via HELM
The HELM's values.yaml file has two values for controlling replica counts: 
``` yaml
replicaCount: 1
admissionControllerReplicaCount: 1 
```

`replicaCount` controls the virtual node pod replicas, while `admissionControllerReplicaCount` controls the AdmissionController pod replicas.