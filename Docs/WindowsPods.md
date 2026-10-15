# Windows Pods on virtual nodes

Virtual nodes on Azure Container Instances support running Windows pods in addition to Linux pods. 

## Prerequisites: 

### Regional Support for Windows Preview

Currently, we are supporting only these Azure regions for this Windows virtual nodes preview: 
- Denmark East
- Belgium Central
- Germany North Stamp/Slice 3 (Confidential)

### Infrastructure Setup for AKS

Before deploying Windows workloads, ensure you have completed the optional Windows-specific setup steps in the main [README.md](/README.md):

- [Added a Windows user Node Pool to your AKS cluster](/README.md#optional-add-windows-node-pool)
- [Configured the HELM chart for Windows support](/README.md#optional-step-2-modify-helm-chart-for-windows-pod-support) 

# Deploy your first Windows pod to a virtual node

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

# Current Limitations (Windows VN2)

Compared to regular Windows ACI container groups and to Linux pods running on VN2, Windows pods on virtual nodes currently have the following limitations:

## Kubernetes Networking and Services

- `kube-proxy` and internal load balancers are not supported. See  [External DNS workarounds foe Windows pod-to-pod connectivity](/Docs/ExternalDNS.md).

## Storage

- CSI drivers are not supported. Persistent volumes that rely on CSI cannot be used.

## Base Image Support

- For Non-Confidential workloads, only Windows Server 2022 (LTSC2022)–based images are supported. Other Windows base versions (for example, older LTSC releases) are not currently supported on Windows VN2. Experimental support for confidential workloads using Windows Server 2025-based images.

## Security and Isolation

- Confidential container groups are currently only supported on Germany North Stamp/Slice 3, in Internal Preview. To utilize this capability, your subscription must be enabled so that traffic is redirected to this Slice. If you want to test this feature, please request your relevant subscription(s) to be added by reaching out to Sundari Selvarajan (Sundari.Selvarajan@microsoft.com), Gabriel Fuhrman (gfuhrm@microsoft.com) or Adrian Cotolan (adrian.cotolan@microsoft.com).
- The [Windows allow-all confidential policy](/Docs/PodCustomizations.md#windows-allow-all-confid-policy) is intended for initial testing and provides no production security guarantees.
- [Windows confidential container considerations](/Docs/PodCustomizations.md#windows-considerations) include a minimum memory requirement of 2048 MB per container.

## Identity and Credentials

- The following are not supported: PrivateLink ACR images, and inline image registry credentials.

## Other features not supported / known bugs / limitations
- ["BigContainers"](https://learn.microsoft.com/en-us/azure/container-instances/big-contaiqners) are not yet supported yet for Windows VN2, but should be coming soon!
- Standby pools are not yet supported for confidential workloads.
- Virtual DaemonSets are not supported.
- `hostname` returns the `caas-id` instead of the pod name.
- Prometheus metrics are emitted, but the corresponding AKS Windows feature is currently in preview. See [Enable Monitoring for Azure Kubernetes Service (AKS) Clusters - Azure Monitor | Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable) → "Enable Windows metrics (Preview)".
