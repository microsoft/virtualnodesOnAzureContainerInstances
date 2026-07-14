# Virtual DaemonSets

Virtual DaemonSets extends the existing Virtual Node v2 architecture to support DaemonSet-style workloads on ACI-backed nodes, enabling new platform and infrastructure scenarios with serverless capacity while remaining close to the familiar Kubernetes DaemonSet programming model. Like K8s DaemonSets, they can be updated out of sync with pods running on the virtual nodes and need not be specified as part of the workload pod specs. 

Virtual DaemonSets use cases: 
-	Sidecar-like workloads: Attach log collectors, metrics agents, service mesh components, or helper daemons dynamically.
-	Multi-process workloads: Run secondary processes in isolated pods within the same sandbox.
-	Ephemeral debugging: Inject debugging pods into live environments.
-	Auxiliary tasks: Add temporary profilers, backup agents, or scanners.

These VDS workloads are injected into the ACI container group of targeted pods, and are surfaced to the Kubernetes control plane as distinct pods. We will call these pods used for auxiliary workloads "companion pods" below. 

## Setup

There are two new components needed to utilize Virtual DaemonSets: the CRD (Custom Resource Definition) and the CRD's controller which reconciles the state of the cluster. The controller runs as a pod in the namespace of the VN2 installation. There can only be one CRD and one controller installed per cluster. Both are installed by default, i.e. when running:

`helm install vn2release ./`

In the case of multiple installs, the CRD and controller can be skipped for an install using the `virtualdaemonsets.crd.enable` flag and the `virtualdaemonsetControllerManager.enable` flag:

`helm install vn2release ./ --set "virtualdaemonsets.crd.enable=false" --set "virtualdaemonsetControllerManager.enable=false"`

The CRD also has a flag that defines whether it should be kept or not when the release is uninstalled, which is by default set to false: `virtualdaemonsets.crd.keep`

## Usage

A simple example for how to use Virtual DaemonSets is shown below:

``` yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod1
spec:
  nodeName: vn2release-virtualnode-0
  restartPolicy: Always
  volumes:
    - name: scratch-volume
      hostPath:
        path: /data/host
        type: DirectoryOrCreate
  containers:
    - name: ubuntu1
      image: ubuntu:16.04
      imagePullPolicy: Always
      command:
        - sh
        - -c
        - |
          mkdir -p /mnt/scratch && \
          echo Simple pod 1 > /mnt/scratch/a.txt; \
          tail -f /mnt/scratch/a.txt
      volumeMounts:
        - name: scratch-volume
          mountPath: /mnt/scratch
      resources:
        limits:
          cpu: "2250m"
          memory: "2256Mi"
        requests:
          cpu: "100m"
          memory: "128Mi"
---
kind: VirtualDaemonSet
apiVersion: virtualdaemonsets.aci.azure.microsoft.com/v1alpha1
metadata:
  name: virtualdaemonset1
spec:
  selector:
    matchExpressions:
      - key: virtualdaemonset.kubernetes.io/virtualdaemonset
        operator: DoesNotExist

  template:
    apiVersion: virtualdaemonsets.aci.azure.microsoft.com/v1alpha1
    kind: VirtualDaemonSet
    metadata:
      labels:
        role: companion
    spec:
      volumes:
        - name: scratch-volume
          hostPath: 
            path: /data/host
            type: DirectoryOrCreate
      containers:
        - name: my-container
          image: ubuntu:16.04
          command: ["/bin/sh", "-c", "echo Hello;while true; do echo $(date) VirtualDaemonSet 1 log >> /usr/share/scratch/a.txt; sleep 2;done;"]
          volumeMounts:
            - name: scratch-volume
              mountPath: /usr/share/scratch

      nodeName: vn2release-virtualnode-0
```

Applying the above YAML should result in a pod, a Virtual DaemonSet and a companion pod created for the pod (whose containers run in the same container group). The companion pod constantly adds logs to the shared volume mount, which should be visible from the regular pod by running

`kubectl logs pod1`

The Virtual DaemonSet will create companion pods for all the pods matched by the selector. Any selector can be used, as long as it matches the pods you want to target. It is however necessary to exclude the companion pods, since we can't create companion pods for other companion pods. Excluding companion pods is done in the above sample using this condition that checks for the `virtualdaemonset.kubernetes.io/virtualdaemonset` key that is automatically added to companion pods:

``` yaml
matchExpressions:
      - key: virtualdaemonset.kubernetes.io/virtualdaemonset
        operator: DoesNotExist
```

>
> Note: VDS selectors only match against pods in the same namespace as the VDS object.
>

Virtual DaemonSet can be deleted using `kubectl delete virtualdaemonset {vds_name}` or `kubectl delete vds {vds_name}`. Each companion pod is associated to a pod and a VDS, and deleting either the pod or the VDS will result in the deletion of the companion pod.

## Limitations

Since companion pod containers run in the hyper-v isolated UVM in ACI, they share the same environment, setup, and resources for the original pod (Eg - will be hooked up to the same MI, if relevant).

## Associating Companion Pods to their Host Pod
Companion pod names are of the form `vds-<vdsName>-<hostPodName>-<differentiator>`, which can be used to quickly associate them to their host pods. 

This can also be associated based on the container IDs of the pods, as both the host and companion pods will share the start of the container ID (in form `virtualcri://pods/<host pod UID>/`). The companion pod will have `/podlets/` section present which its container id portions will be within. 

## Under the hood
Native DaemonSets is not supported by ACI's virtual nodes nor our competitors at AWS / GCP. This is because DaemonSets as a concept (a workload tied to the shared infrastructure of the node VM, often modifying the underlying shared OS) do not map well to running in a serverless environment (where by design very little can be shared between workloads). 

Virtual DaemonSets allow customers to specify a workload that they want to run within the same hyper-v isolated UVM as their container payload in ACI, sharing the same resources and permissions as the UVM. In defining a Virtual DaemonSet, customers can specify their desired workload itself as well as selectors to determine which UVMs the workload should run alongside. Like normal DaemonSets, this specification will span all virtual nodes installed to the customer’s K8s cluster. 

![VDS custom object scope diagram](/Docs/Pictures/vds.png)

Key Advantages: 
-	No pre-running daemons: VirtualDaemonSets eliminate the need for persistent node-level daemons.
-	Declarative management: Operators define attachment logic via Kubernetes resources, not manual scripting.
-	Auxiliary tasks: Add temporary profilers, backup agents, or scanners.
-	Independent lifecycle: VirtualDaemonSets can be added, removed, or upgraded at any time, without requiring changes to the main workload pod specification. This enables rapid iteration and operational flexibility for auxiliary workloads. 
