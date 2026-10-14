# Windows Pods on virtual nodes

Virtual nodes on Azure Container Instances support running Windows pods in addition to Linux pods.

## Prerequisites

### Regional support for Windows preview

The Windows virtual nodes preview is available in the following Azure regions:
- Belgium Central
- Denmark East

Confidential Windows container groups are available only as an internal preview in Germany North (stamp/slice 3) and are not part of the public preview.

### Infrastructure Setup for AKS

Before deploying Windows workloads, ensure you have completed the optional Windows-specific setup steps in the main [README.md](/README.md):

- [Added a Windows user Node Pool to your AKS cluster](/README.md#optional-add-windows-node-pool)
- [Configured the HELM chart for Windows support](/README.md#optional-step-2-modify-helm-chart-for-windows-pod-support)

## Deploy your first Windows pod to a virtual node

Windows pods are scheduled to a virtual node by using the appropriate `nodeSelector` and `tolerations`. Both the `nodeSelector` and `tolerations` shown below are mandatory for the workload to be scheduled onto the Windows virtual node.

Example Windows pod YAML:

``` yaml
apiVersion: v1
kind: Pod
metadata:
  name: windows-virtualnode-demo
spec:
  containers:
  - command:
    - pwsh
    - -Command
    - "$counter = 0; while ($true) { Write-Host \"Hello from Windows pwsh container $counter! 🎊 \"; $counter++; Start-Sleep -Seconds 1 };"
    image: mcr.microsoft.com/dotnet/sdk:8.0-nanoserver-ltsc2025
    name: demo-pwsh
    resources:
      limits:
        cpu: 1
        memory: 2256Mi
      requests:
        cpu: 100m
        memory: 128Mi
  - command:
    - python
    - -c
    - |
        import time
        i = 1
        while True:
            print(f"Hello from Windows Python container #{i}! 🎉", flush=True)
            i += 1
            time.sleep(1)
    image: mcr.microsoft.com/windows-cssc/python:3.13-nanoserver-ltsc2025
    name: demo-python
    resources:
      limits:
        cpu: 1
        memory: 2256Mi
      requests:
        cpu: 100m
        memory: 128Mi
  nodeSelector:
      "kubernetes.io/os": windows
      virtualization: virtualnode2
  tolerations:
  - effect: NoSchedule
    key: virtual-kubelet.io/provider
    operator: Exists
```

Once deployed, you can interact with it as you would any other K8s pod (`kubectl describe`, `kubectl logs`, `kubectl exec`, etc.).

## Current limitations

Compared to regular Windows ACI container groups and to Linux pods running on VN2, Windows pods on virtual nodes currently have the following limitations:

### Kubernetes networking and services

- `kube-proxy` and internal load balancers are not supported. See [Private DNS-based Windows pod-to-pod connectivity](/Docs/ExternalDNS.md) for an ExternalDNS workaround.

### Storage

- CSI drivers are not supported. Persistent volumes that rely on CSI cannot be used.

### Base image support

- Non-confidential workloads support Windows Server 2022 (LTSC2022)-based images. Experimental confidential Windows support uses Windows Server 2025-based images.

### Security and isolation

- Confidential Windows container groups are currently limited to the internal preview described above.
- The [Windows allow-all confidential policy](/Docs/PodCustomizations.md#windows-allow-all-confid-policy) is intended for initial testing and provides no production security guarantees.
- [Windows confidential container considerations](/Docs/PodCustomizations.md#windows-considerations) include a minimum memory requirement of 2048 MB per container.

### Identity and credentials

- Private Link ACR images and inline image registry credentials are not supported.

### Other unsupported features and known limitations

- ["Big containers"](https://learn.microsoft.com/en-us/azure/container-instances/big-containers) are not yet supported for Windows VN2.
- Standby pools are not yet supported for confidential workloads.
- Virtual DaemonSets are not supported.
- `hostname` returns the `caas-id` instead of the pod name.
- Prometheus metrics are emitted, but the corresponding AKS Windows feature is currently in preview. See [Enable Monitoring for Azure Kubernetes Service (AKS) Clusters - Azure Monitor | Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable) → "Enable Windows metrics (Preview)".
