
# Node Customizations
Customizations to the Virtual Node Node configuration are generally done by modifying the values.yaml file for the HELM install and then running a `HELM upgrade` action. 


# How to run more than one type of customized Virtual Node in the same AKS
You may have a scenario that you want to run more than 1 Virtual Node HELM configuration in one AKS cluster. 

To achieve this, you will need to ensure only one of those HELM releases' value.yaml files has a non-zero replica count for the the Admission Controller, which also controls implicitly registering the web hook. The default value is 1, as it is a required service to be running for Virtual Node to function. 
```
admissionControllerReplicaCount: 1
```

It is also strongly recommended to update the values.yaml namespace used for deploying each Virtual Node configuration so each has its own unique namespace.
```
namespace: <Something unique for each config>
```

# Scaling Virtual Nodes Up / Down
As would be expected from K8s resources, Virtual Node can be scaled up or down by modifying the replica count, either in place or with a HELM update. 

The number of Virtual Node pods and Admission Controller pods can each be scaled seperately. The Virtual Node pods are responsible for most K8s interactions with the virtualized pods, and can at most support 200 pods each. The Admission Controllers are present to ensure certain state about the Virtual Nodes is updated for the K8s Control Plane, as well as making modifications to the pods being sent to the Virtual Nodes which enables some functionalities. 

For every 200 pods you wish to host in Virtual Node you will need to scale out an additional Virtual Node replica for it. 

**NOTE**: Regardless which method is used, scaling down your Virtual Nodes requires some manual cleanup. 

## Manual Cleanup when Scaling Down Virtual Node pods
If you scale DOWN replicas for the Virtual Node, this will remove the Virtual Node backing pods but it will NOT clean up the “fake” K8s Nodes and they will still appear to be “Ready” to the control plane. These will need to be manually cleaned up, via a command like 
```
kubectl delete node <nodeName>
```
To determine which are the nodes which need to be cleaned up, they would be the ones which no longer have backing pods (Virtual Node node names are the same as the pod backing them)… which can be queried like so: 
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

`replicaCount` controls the Virtual Node pod replicas, while `admissionControllerReplicaCount` controls the AdmissionController pod replicas. 