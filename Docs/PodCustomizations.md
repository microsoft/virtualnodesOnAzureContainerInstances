# Pod Customizations
This page is here to provide documentation of non-standard-K8s functionality that can be used with virtual node pods!

## Table of Contents

| Pod Annotation | Short Summary | Doc Link | 
| ------------- | ------------- | --- |
| microsoft.containerinstance.virtualnode.ccepolicy | Run in Confidential ACI with provided policy | [Confidential Containers](#confidential-containers)
| microsoft.containerinstance.virtualnode.subnets.primary | Run within a specific Subnet | [Subnet Override](#using-virtual-nodes-with-multiple-subnets)
| microsoft.containerinstance.virtualnode.identity | Run using a provided Azure Identity | [Managed Identity](#running-pods-with-an-azure-managed-identity)
| microsoft.containerinstance.virtualnode.injectkubeproxy | Controlling Kube-Proxy Usage | [Kube-Proxy](#disable-kube-proxy)
| microsoft.containerinstance.virtualnode.injectdns | Controlling K8s DNS Usage | [K8s DNS](#disable-k8s-dns-injection)
| microsoft.containerinstance.virtualnode.zones | Requesting Azure Zone Deployment | [Zones](#zones)


| virtual node Downlevel API | Short Summary | Doc Link |
| ------------- | ------------- | --- |
| ===VIRTUALNODE2.CC.THIM.ENDPOINT=== | Replaced with THIM Endpoint | [THIM Downlevel APIs](#thim-downlevel-apis)
| ===VIRTUALNODE2.CC.THIM.ADDRESS=== | Replaced with THIM Address | [THIM Downlevel APIs](#thim-downlevel-apis)

# Controlling Behaviors through Pod Annotations
The general method for controlling non-K8s behavior of virtual nodes at the pod level is via pod annotations. 

**GENERAL NOTE**: Annotations below all need to be applied to the appropriate part of the K8s resource so that they will be on the pods themselves. For a pod YAML file, this would be the `metadata` for the file itself, while for a Deployment / ScaleSet / etc. YAML the annotation would be in the `template`'s `metadata`. 

Example of annotations for Pod YAML (**it's in the main metadata!**)
``` yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:   
    microsoft.containerinstance.virtualnode.injectdns: "false"
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

Example of annotations for Deployment YAML (**it's in the template metadata!**)
``` yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
  labels:
    type: scaletest
  name: deploy-alpine
spec:
  replicas: 3
  selector:
    matchLabels:
      type: scaletest
  template:
    metadata:
      annotations:
        microsoft.containerinstance.virtualnode.injectkubeproxy: 'false'
      labels:
        type: scaletest
    spec:
      containers:
      - image: mcr.microsoft.com/oss/nginx/nginx:1.17.3-alpine
        name: mypod
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
## Confidential Containers
Confidential containers are a high security offering from ACI that allows customers to have a high degree of confidence what they are running and what that image is allowed to do. 

[Overview of Confidential Containers on ACI](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-confidential-overview)

In order to have virtual node create your containers as Confidential, you must add a pod annotation which will contain the CCE policy the pod will run using: 

    microsoft.containerinstance.virtualnode.ccepolicy

In order to generate that policy, utilize the ConfCom extension which can be added into Az CLI. To add it, run: 

    az extension add -n confcom

Using that tool for virtual nodes is simple, just provide your YAML file with the --virtual-node-yaml parameter like so: 
    
    az confcom acipolicygen --virtual-node-yaml <yourYamlFile>.yaml

This will not only generate the CCE policy, but it will inject the policy annotation into the right section of the file. 

Example Confidential YAML
``` yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    microsoft.containerinstance.virtualnode.ccepolicy: cGFja2FnZSBwb2xpY3kKCmltcG9ydCBmdXR1cmUua2V5d29yZHMuZXZlcnkKaW1wb3J0IGZ1dHVyZS5rZXl3b3Jkcy5pbgoKYXBpX3ZlcnNpb24gOj0gIjAuMTAuMCIKZnJhbWV3b3JrX3ZlcnNpb24gOj0gIjAuMi4zIgoKZnJhZ21lbnRzIDo9IFsKICB7CiAgICAiZmVlZCI6ICJtY3IubWljcm9zb2Z0LmNvbS9hY2kvYWNpLWNjLWluZnJhLWZyYWdtZW50IiwKICAgICJpbmNsdWRlcyI6IFsKICAgICAgImNvbnRhaW5lcnMiLAogICAgICAiZnJhZ21lbnRzIgogICAgXSwKICAgICJpc3N1ZXIiOiAiZGlkOng1MDk6MDpzaGEyNTY6SV9faXVMMjVvWEVWRmRUUF9hQkx4X2VUMVJQSGJDUV9FQ0JRZllacHQ5czo6ZWt1OjEuMy42LjEuNC4xLjMxMS43Ni41OS4xLjMiLAogICAgIm1pbmltdW1fc3ZuIjogIjEiCiAgfQpdCgpjb250YWluZXJzIDo9IFt7ImFsbG93X2VsZXZhdGVkIjpmYWxzZSwiYWxsb3dfc3RkaW9fYWNjZXNzIjp0cnVlLCJjYXBhYmlsaXRpZXMiOnsiYW1iaWVudCI6W10sImJvdW5kaW5nIjpbIkNBUF9BVURJVF9XUklURSIsIkNBUF9DSE9XTiIsIkNBUF9EQUNfT1ZFUlJJREUiLCJDQVBfRk9XTkVSIiwiQ0FQX0ZTRVRJRCIsIkNBUF9LSUxMIiwiQ0FQX01LTk9EIiwiQ0FQX05FVF9CSU5EX1NFUlZJQ0UiLCJDQVBfTkVUX1JBVyIsIkNBUF9TRVRGQ0FQIiwiQ0FQX1NFVEdJRCIsIkNBUF9TRVRQQ0FQIiwiQ0FQX1NFVFVJRCIsIkNBUF9TWVNfQ0hST09UIl0sImVmZmVjdGl2ZSI6WyJDQVBfQVVESVRfV1JJVEUiLCJDQVBfQ0hPV04iLCJDQVBfREFDX09WRVJSSURFIiwiQ0FQX0ZPV05FUiIsIkNBUF9GU0VUSUQiLCJDQVBfS0lMTCIsIkNBUF9NS05PRCIsIkNBUF9ORVRfQklORF9TRVJWSUNFIiwiQ0FQX05FVF9SQVciLCJDQVBfU0VURkNBUCIsIkNBUF9TRVRHSUQiLCJDQVBfU0VUUENBUCIsIkNBUF9TRVRVSUQiLCJDQVBfU1lTX0NIUk9PVCJdLCJpbmhlcml0YWJsZSI6W10sInBlcm1pdHRlZCI6WyJDQVBfQVVESVRfV1JJVEUiLCJDQVBfQ0hPV04iLCJDQVBfREFDX09WRVJSSURFIiwiQ0FQX0ZPV05FUiIsIkNBUF9GU0VUSUQiLCJDQVBfS0lMTCIsIkNBUF9NS05PRCIsIkNBUF9ORVRfQklORF9TRVJWSUNFIiwiQ0FQX05FVF9SQVciLCJDQVBfU0VURkNBUCIsIkNBUF9TRVRHSUQiLCJDQVBfU0VUUENBUCIsIkNBUF9TRVRVSUQiLCJDQVBfU1lTX0NIUk9PVCJdfSwiY29tbWFuZCI6WyJuZ2lueCIsIi1nIiwiZGFlbW9uIG9mZjsiXSwiZW52X3J1bGVzIjpbeyJwYXR0ZXJuIjoiUEFUSD0vdXNyL2xvY2FsL3NiaW46L3Vzci9sb2NhbC9iaW46L3Vzci9zYmluOi91c3IvYmluOi9zYmluOi9iaW4iLCJyZXF1aXJlZCI6ZmFsc2UsInN0cmF0ZWd5Ijoic3RyaW5nIn0seyJwYXR0ZXJuIjoiTkdJTlhfVkVSU0lPTj0xLjE3LjMiLCJyZXF1aXJlZCI6ZmFsc2UsInN0cmF0ZWd5Ijoic3RyaW5nIn0seyJwYXR0ZXJuIjoiTkpTX1ZFUlNJT049MC4zLjUiLCJyZXF1aXJlZCI6ZmFsc2UsInN0cmF0ZWd5Ijoic3RyaW5nIn0seyJwYXR0ZXJuIjoiUEtHX1JFTEVBU0U9MSIsInJlcXVpcmVkIjpmYWxzZSwic3RyYXRlZ3kiOiJzdHJpbmcifSx7InBhdHRlcm4iOiJURVJNPXh0ZXJtIiwicmVxdWlyZWQiOmZhbHNlLCJzdHJhdGVneSI6InN0cmluZyJ9LHsicGF0dGVybiI6Iig/aSkoRkFCUklDKV8uKz0uKyIsInJlcXVpcmVkIjpmYWxzZSwic3RyYXRlZ3kiOiJyZTIifSx7InBhdHRlcm4iOiJIT1NUTkFNRT0uKyIsInJlcXVpcmVkIjpmYWxzZSwic3RyYXRlZ3kiOiJyZTIifSx7InBhdHRlcm4iOiJUKEUpP01QPS4rIiwicmVxdWlyZWQiOmZhbHNlLCJzdHJhdGVneSI6InJlMiJ9LHsicGF0dGVybiI6IkZhYnJpY1BhY2thZ2VGaWxlTmFtZT0uKyIsInJlcXVpcmVkIjpmYWxzZSwic3RyYXRlZ3kiOiJyZTIifSx7InBhdHRlcm4iOiJIb3N0ZWRTZXJ2aWNlTmFtZT0uKyIsInJlcXVpcmVkIjpmYWxzZSwic3RyYXRlZ3kiOiJyZTIifSx7InBhdHRlcm4iOiJJREVOVElUWV9BUElfVkVSU0lPTj0uKyIsInJlcXVpcmVkIjpmYWxzZSwic3RyYXRlZ3kiOiJyZTIifSx7InBhdHRlcm4iOiJJREVOVElUWV9IRUFERVI9LisiLCJyZXF1aXJlZCI6ZmFsc2UsInN0cmF0ZWd5IjoicmUyIn0seyJwYXR0ZXJuIjoiSURFTlRJVFlfU0VSVkVSX1RIVU1CUFJJTlQ9LisiLCJyZXF1aXJlZCI6ZmFsc2UsInN0cmF0ZWd5IjoicmUyIn0seyJwYXR0ZXJuIjoiYXp1cmVjb250YWluZXJpbnN0YW5jZV9yZXN0YXJ0ZWRfYnk9LisiLCJyZXF1aXJlZCI6ZmFsc2UsInN0cmF0ZWd5IjoicmUyIn0seyJwYXR0ZXJuIjoiW0EtWjAtOV9dK19TRVJWSUNFX0hPU1Q9LisiLCJyZXF1aXJlZCI6ZmFsc2UsInN0cmF0ZWd5IjoicmUyIn0seyJwYXR0ZXJuIjoiW0EtWjAtOV9dK19TRVJWSUNFX1BPUlQ9LisiLCJyZXF1aXJlZCI6ZmFsc2UsInN0cmF0ZWd5IjoicmUyIn0seyJwYXR0ZXJuIjoiW0EtWjAtOV9dK19TRVJWSUNFX1BPUlRfW0EtWjAtOV9dKz0uKyIsInJlcXVpcmVkIjpmYWxzZSwic3RyYXRlZ3kiOiJyZTIifSx7InBhdHRlcm4iOiJbQS1aMC05X10rX1BPUlQ9LisiLCJyZXF1aXJlZCI6ZmFsc2UsInN0cmF0ZWd5IjoicmUyIn0seyJwYXR0ZXJuIjoiW0EtWjAtOV9dK19QT1JUX1swLTldK19UQ1A9LisiLCJyZXF1aXJlZCI6ZmFsc2UsInN0cmF0ZWd5IjoicmUyIn0seyJwYXR0ZXJuIjoiW0EtWjAtOV9dK19QT1JUX1swLTldK19UQ1BfUFJPVE89LisiLCJyZXF1aXJlZCI6ZmFsc2UsInN0cmF0ZWd5IjoicmUyIn0seyJwYXR0ZXJuIjoiW0EtWjAtOV9dK19QT1JUX1swLTldK19UQ1BfUE9SVD0uKyIsInJlcXVpcmVkIjpmYWxzZSwic3RyYXRlZ3kiOiJyZTIifSx7InBhdHRlcm4iOiJbQS1aMC05X10rX1BPUlRfWzAtOV0rX1RDUF9BRERSPS4rIiwicmVxdWlyZWQiOmZhbHNlLCJzdHJhdGVneSI6InJlMiJ9XSwiZXhlY19wcm9jZXNzZXMiOlt7ImNvbW1hbmQiOlsiL2Jpbi9zaCJdLCJzaWduYWxzIjpbXX0seyJjb21tYW5kIjpbIi9iaW4vYmFzaCJdLCJzaWduYWxzIjpbXX1dLCJpZCI6Im1jci5taWNyb3NvZnQuY29tL29zcy9uZ2lueC9uZ2lueDoxLjE3LjMtYWxwaW5lIiwibGF5ZXJzIjpbIjdmMDYyYzVlYmIzZGM2ZDNkZjdmMjVmYTY4N2JiZWMwZjYxNTMwNTM2MjY3YWQ2ZDZhZmEzMjUwMWY1MzQwYTYiLCIyOTdkZDI2YjUxMTkxZjg1OTI4NTA4ZmIzNjhlNmIwNjQ1MDJjMTI4YmU2ZjUxZmM1Y2IzMDJkM2IyNTNkNzMwIl0sIm1vdW50cyI6W3siZGVzdGluYXRpb24iOiIvdmFyL3J1bi9zZWNyZXRzL2t1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQiLCJvcHRpb25zIjpbInJiaW5kIiwicnNoYXJlZCIsInJvIl0sInNvdXJjZSI6InNhbmRib3g6Ly8vdG1wL2F0bGFzL2VtcHR5ZGlyLy4rIiwidHlwZSI6ImJpbmQifSx7ImRlc3RpbmF0aW9uIjoiL2V0Yy9ob3N0cyIsIm9wdGlvbnMiOlsicmJpbmQiLCJyc2hhcmVkIiwicnciXSwic291cmNlIjoic2FuZGJveDovLy90bXAvYXRsYXMvZW1wdHlkaXIvLisiLCJ0eXBlIjoiYmluZCJ9LHsiZGVzdGluYXRpb24iOiIvZGV2L3Rlcm1pbmF0aW9uLWxvZyIsIm9wdGlvbnMiOlsicmJpbmQiLCJyc2hhcmVkIiwicnciXSwic291cmNlIjoic2FuZGJveDovLy90bXAvYXRsYXMvZW1wdHlkaXIvLisiLCJ0eXBlIjoiYmluZCJ9LHsiZGVzdGluYXRpb24iOiIvZXRjL2hvc3RuYW1lIiwib3B0aW9ucyI6WyJyYmluZCIsInJzaGFyZWQiLCJydyJdLCJzb3VyY2UiOiJzYW5kYm94Oi8vL3RtcC9hdGxhcy9lbXB0eWRpci8uKyIsInR5cGUiOiJiaW5kIn0seyJkZXN0aW5hdGlvbiI6Ii9ldGMvcmVzb2x2LmNvbmYiLCJvcHRpb25zIjpbInJiaW5kIiwicnNoYXJlZCIsInJ3Il0sInNvdXJjZSI6InNhbmRib3g6Ly8vdG1wL2F0bGFzL2VtcHR5ZGlyLy4rIiwidHlwZSI6ImJpbmQifV0sIm5hbWUiOiJteXBvZCIsIm5vX25ld19wcml2aWxlZ2VzIjpmYWxzZSwic2VjY29tcF9wcm9maWxlX3NoYTI1NiI6IiIsInNpZ25hbHMiOlsxNV0sInVzZXIiOnsiZ3JvdXBfaWRuYW1lcyI6W3sicGF0dGVybiI6IiIsInN0cmF0ZWd5IjoiYW55In1dLCJ1bWFzayI6IjAwMjIiLCJ1c2VyX2lkbmFtZSI6eyJwYXR0ZXJuIjoiIiwic3RyYXRlZ3kiOiJhbnkifX0sIndvcmtpbmdfZGlyIjoiLyJ9LHsiYWxsb3dfZWxldmF0ZWQiOmZhbHNlLCJhbGxvd19zdGRpb19hY2Nlc3MiOnRydWUsImNhcGFiaWxpdGllcyI6eyJhbWJpZW50IjpbXSwiYm91bmRpbmciOlsiQ0FQX0NIT1dOIiwiQ0FQX0RBQ19PVkVSUklERSIsIkNBUF9GU0VUSUQiLCJDQVBfRk9XTkVSIiwiQ0FQX01LTk9EIiwiQ0FQX05FVF9SQVciLCJDQVBfU0VUR0lEIiwiQ0FQX1NFVFVJRCIsIkNBUF9TRVRGQ0FQIiwiQ0FQX1NFVFBDQVAiLCJDQVBfTkVUX0JJTkRfU0VSVklDRSIsIkNBUF9TWVNfQ0hST09UIiwiQ0FQX0tJTEwiLCJDQVBfQVVESVRfV1JJVEUiXSwiZWZmZWN0aXZlIjpbIkNBUF9DSE9XTiIsIkNBUF9EQUNfT1ZFUlJJREUiLCJDQVBfRlNFVElEIiwiQ0FQX0ZPV05FUiIsIkNBUF9NS05PRCIsIkNBUF9ORVRfUkFXIiwiQ0FQX1NFVEdJRCIsIkNBUF9TRVRVSUQiLCJDQVBfU0VURkNBUCIsIkNBUF9TRVRQQ0FQIiwiQ0FQX05FVF9CSU5EX1NFUlZJQ0UiLCJDQVBfU1lTX0NIUk9PVCIsIkNBUF9LSUxMIiwiQ0FQX0FVRElUX1dSSVRFIl0sImluaGVyaXRhYmxlIjpbXSwicGVybWl0dGVkIjpbIkNBUF9DSE9XTiIsIkNBUF9EQUNfT1ZFUlJJREUiLCJDQVBfRlNFVElEIiwiQ0FQX0ZPV05FUiIsIkNBUF9NS05PRCIsIkNBUF9ORVRfUkFXIiwiQ0FQX1NFVEdJRCIsIkNBUF9TRVRVSUQiLCJDQVBfU0VURkNBUCIsIkNBUF9TRVRQQ0FQIiwiQ0FQX05FVF9CSU5EX1NFUlZJQ0UiLCJDQVBfU1lTX0NIUk9PVCIsIkNBUF9LSUxMIiwiQ0FQX0FVRElUX1dSSVRFIl19LCJjb21tYW5kIjpbIi9wYXVzZSJdLCJlbnZfcnVsZXMiOlt7InBhdHRlcm4iOiJQQVRIPS91c3IvbG9jYWwvc2JpbjovdXNyL2xvY2FsL2JpbjovdXNyL3NiaW46L3Vzci9iaW46L3NiaW46L2JpbiIsInJlcXVpcmVkIjp0cnVlLCJzdHJhdGVneSI6InN0cmluZyJ9LHsicGF0dGVybiI6IlRFUk09eHRlcm0iLCJyZXF1aXJlZCI6ZmFsc2UsInN0cmF0ZWd5Ijoic3RyaW5nIn1dLCJleGVjX3Byb2Nlc3NlcyI6W10sImxheWVycyI6WyIxNmI1MTQwNTdhMDZhZDY2NWY5MmMwMjg2M2FjYTA3NGZkNTk3NmM3NTVkMjZiZmYxNjM2NTI5OTE2OWU4NDE1Il0sIm1vdW50cyI6W10sIm5vX25ld19wcml2aWxlZ2VzIjpmYWxzZSwic2VjY29tcF9wcm9maWxlX3NoYTI1NiI6IiIsInNpZ25hbHMiOltdLCJ1c2VyIjp7Imdyb3VwX2lkbmFtZXMiOlt7InBhdHRlcm4iOiIiLCJzdHJhdGVneSI6ImFueSJ9XSwidW1hc2siOiIwMDIyIiwidXNlcl9pZG5hbWUiOnsicGF0dGVybiI6IiIsInN0cmF0ZWd5IjoiYW55In19LCJ3b3JraW5nX2RpciI6Ii8ifV0KCmFsbG93X3Byb3BlcnRpZXNfYWNjZXNzIDo9IHRydWUKYWxsb3dfZHVtcF9zdGFja3MgOj0gdHJ1ZQphbGxvd19ydW50aW1lX2xvZ2dpbmcgOj0gdHJ1ZQphbGxvd19lbnZpcm9ubWVudF92YXJpYWJsZV9kcm9wcGluZyA6PSB0cnVlCmFsbG93X3VuZW5jcnlwdGVkX3NjcmF0Y2ggOj0gZmFsc2UKYWxsb3dfY2FwYWJpbGl0eV9kcm9wcGluZyA6PSB0cnVlCgptb3VudF9kZXZpY2UgOj0gZGF0YS5mcmFtZXdvcmsubW91bnRfZGV2aWNlCnVubW91bnRfZGV2aWNlIDo9IGRhdGEuZnJhbWV3b3JrLnVubW91bnRfZGV2aWNlCm1vdW50X292ZXJsYXkgOj0gZGF0YS5mcmFtZXdvcmsubW91bnRfb3ZlcmxheQp1bm1vdW50X292ZXJsYXkgOj0gZGF0YS5mcmFtZXdvcmsudW5tb3VudF9vdmVybGF5CmNyZWF0ZV9jb250YWluZXIgOj0gZGF0YS5mcmFtZXdvcmsuY3JlYXRlX2NvbnRhaW5lcgpleGVjX2luX2NvbnRhaW5lciA6PSBkYXRhLmZyYW1ld29yay5leGVjX2luX2NvbnRhaW5lcgpleGVjX2V4dGVybmFsIDo9IGRhdGEuZnJhbWV3b3JrLmV4ZWNfZXh0ZXJuYWwKc2h1dGRvd25fY29udGFpbmVyIDo9IGRhdGEuZnJhbWV3b3JrLnNodXRkb3duX2NvbnRhaW5lcgpzaWduYWxfY29udGFpbmVyX3Byb2Nlc3MgOj0gZGF0YS5mcmFtZXdvcmsuc2lnbmFsX2NvbnRhaW5lcl9wcm9jZXNzCnBsYW45X21vdW50IDo9IGRhdGEuZnJhbWV3b3JrLnBsYW45X21vdW50CnBsYW45X3VubW91bnQgOj0gZGF0YS5mcmFtZXdvcmsucGxhbjlfdW5tb3VudApnZXRfcHJvcGVydGllcyA6PSBkYXRhLmZyYW1ld29yay5nZXRfcHJvcGVydGllcwpkdW1wX3N0YWNrcyA6PSBkYXRhLmZyYW1ld29yay5kdW1wX3N0YWNrcwpydW50aW1lX2xvZ2dpbmcgOj0gZGF0YS5mcmFtZXdvcmsucnVudGltZV9sb2dnaW5nCmxvYWRfZnJhZ21lbnQgOj0gZGF0YS5mcmFtZXdvcmsubG9hZF9mcmFnbWVudApzY3JhdGNoX21vdW50IDo9IGRhdGEuZnJhbWV3b3JrLnNjcmF0Y2hfbW91bnQKc2NyYXRjaF91bm1vdW50IDo9IGRhdGEuZnJhbWV3b3JrLnNjcmF0Y2hfdW5tb3VudAoKcmVhc29uIDo9IHsiZXJyb3JzIjogZGF0YS5mcmFtZXdvcmsuZXJyb3JzfQ==
  name: confidential-alpine
spec:
  containers:
  - image: mcr.microsoft.com/oss/nginx/nginx:1.17.3-alpine
    name: mypod
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

### Allow All Confid Policy
For testing / developing containers before the functionality is locked in, often it is useful to run with a very permissive policy. The most permissive policy is below, which provides effectively NO security guarantees... allowing a container to be run with any payload and debug execution allowed, but still running inside the specialized confidential hardware and with the attestation services running. 

This should NOT be used for any production workloads, just as a tool for initial experimentation. 

    "microsoft.containerinstance.virtualnode.ccepolicy":"cGFja2FnZSBwb2xpY3kKCmFwaV9zdm4gOj0gIjAuMTAuMCIKCm1vdW50X2RldmljZSA6PSB7ImFsbG93ZWQiOiB0cnVlfQptb3VudF9vdmVybGF5IDo9IHsiYWxsb3dlZCI6IHRydWV9CmNyZWF0ZV9jb250YWluZXIgOj0geyJhbGxvd2VkIjogdHJ1ZSwgImVudl9saXN0IjogbnVsbCwgImFsbG93X3N0ZGlvX2FjY2VzcyI6IHRydWV9CnVubW91bnRfZGV2aWNlIDo9IHsiYWxsb3dlZCI6IHRydWV9IAp1bm1vdW50X292ZXJsYXkgOj0geyJhbGxvd2VkIjogdHJ1ZX0KZXhlY19pbl9jb250YWluZXIgOj0geyJhbGxvd2VkIjogdHJ1ZSwgImVudl9saXN0IjogbnVsbH0KZXhlY19leHRlcm5hbCA6PSB7ImFsbG93ZWQiOiB0cnVlLCAiZW52X2xpc3QiOiBudWxsLCAiYWxsb3dfc3RkaW9fYWNjZXNzIjogdHJ1ZX0Kc2h1dGRvd25fY29udGFpbmVyIDo9IHsiYWxsb3dlZCI6IHRydWV9CnNpZ25hbF9jb250YWluZXJfcHJvY2VzcyA6PSB7ImFsbG93ZWQiOiB0cnVlfQpwbGFuOV9tb3VudCA6PSB7ImFsbG93ZWQiOiB0cnVlfQpwbGFuOV91bm1vdW50IDo9IHsiYWxsb3dlZCI6IHRydWV9CmdldF9wcm9wZXJ0aWVzIDo9IHsiYWxsb3dlZCI6IHRydWV9CmR1bXBfc3RhY2tzIDo9IHsiYWxsb3dlZCI6IHRydWV9CnJ1bnRpbWVfbG9nZ2luZyA6PSB7ImFsbG93ZWQiOiB0cnVlfQpsb2FkX2ZyYWdtZW50IDo9IHsiYWxsb3dlZCI6IHRydWV9CnNjcmF0Y2hfbW91bnQgOj0geyJhbGxvd2VkIjogdHJ1ZX0Kc2NyYXRjaF91bm1vdW50IDo9IHsiYWxsb3dlZCI6IHRydWV9Cg=="

### Debug Mode
In order to slightly loosen the policy for a Pod to allow certain types of debugging activities like allowing an exec session to shell into the pod with sh or bash, you can generate a policy using the `--debug-mode` arg:

    az confcom acipolicygen -k <yourYamlFile>.yaml --debug-mode

## Using virtual nodes with Multiple Subnets
By default, virtual node pods will run in the subnet configured in the HELM chart as the default ACI subnet. However, some customers may want to run pods in their own isolated subnets (or in a subnet with only a specific set of other pods), and this can be achieved using the subnet override annotation. 

    microsoft.containerinstance.virtualnode.subnets.primary

Example: `microsoft.containerinstance.virtualnode.subnets.primary: /subscriptions/000000-0000-0000-053ca49ab4b5/resourceGroups/definitely_a_fake_RG/providers/Microsoft.Network/virtualNetworks/the_VNET_For_This_Subnet/subnets/your_subnet_name`

## Running pods with an Azure Managed Identity
For some Azure interactions it can be very convienient (and a good security practice) to utilize Azure Managed Identities to make the requests, rather than having your code deal with the unpleasanties of rotating credentials. virtual node can hook up to [Azure Container Instances functionality for running containers with a Managed Identity](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-managed-identity) via a pod annotation: 

    microsoft.containerinstance.virtualnode.identity

Example: `microsoft.containerinstance.virtualnode.identity: /subscriptions/000000-0000-0000-053ca49ab4b5/resourceGroups/definitely_a_fake_RG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/my_MI_name`

## Disable Kube-Proxy
The Kube-Proxy is a standard K8s component that provides benefits like modifying local IP route tables for K8s internal network usage. However, if you do not require this functionality (or explicitly don't want it), the kube-proxy can be disabled for the virtual node pods via this annotation: 

    microsoft.containerinstance.virtualnode.injectkubeproxy: "false"

The default behavior for K8s is to include the Kube-Proxy so that is the behavior if the annotation is not provided. 

**Confidential containers do not support Kube-Proxy usage as it breaks some security guarantees, so regardless what value is provided for this annotation a Confidential pod will ignore it and load without a Kube-Proxy.**

## Disable K8s DNS Injection
By default, K8s Pods are expected to utilize the K8s cluster's DNS. If you want to avoid that interaction, you can add this annotation 

    microsoft.containerinstance.virtualnode.injectdns: "false"

If provided as false, ACI's default DNS will be used by this pod instead of K8s. 

## Zones
Azure has a concept of [Availability Zones](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview?tabs=azure-cli), which are seperated groups of datacenters that exist within the same region. If your scenario calls for it, you can specify a zone for your pod to be hosted on within your given region. 

    microsoft.containerinstance.virtualnode.zones: "<semi-colon delimited string of zones>"

**NOTE**: Today, ACI only supports providing a single zone as part of the request to allocate a sandbox for your pod. If you provide multiple, you should get an informative error effectively saying you can only provide one. 

# virtual node Downlevel APIs
virtual node has a couple of downlevel APIs which don't behave quite like K8s downlevel APIs. They work such that if for a POD if the VALUE of on ENV var is exactly equal to one of the virtual node Downlevel APIs, it will be replaced server size with the appropriate "real" value. 

### THIM Downlevel APIs
[THIM](https://learn.microsoft.com/en-us/azure/security/fundamentals/trusted-hardware-identity-management#how-do-i-request-collateral-in-a-confidential-virtual-machine) (Trusted Hardware Identity Management) is part of the attestation service used for Confidential ACI. In order to avoid hardcoding the address to interact with the attestation service, customers can instead set an environment variable to either of the below and then use the value of that in their container to access THIM:

`===VIRTUALNODE2.CC.THIM.ENDPOINT===` , which will be replaced by something like `http://169.254.128.1:2377/metadata/THIM/amd/certification`

`===VIRTUALNODE2.CC.THIM.ADDRESS===`, which will be replaced by something like `169.254.128.1:2377`

Example Pod YAML using the THIM Downlevel APIs:
``` yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    microsoft.containerinstance.virtualnode.injectkubeproxy: 'false'
  name: thim-downlevel
spec:
  containers:
  - command:
    - /bin/bash
    - -c
    - 'counter=1; while true; do echo "Hello, World! Counter: $counter"; counter=$((counter+1)); sleep 1; done'
    image: mcr.microsoft.com/azure-cli
    name: managed-identity-container
    env: 
    - name: THIM_ENDPOINT
      value: ===VIRTUALNODE2.CC.THIM.ENDPOINT===
    - name: whateverNameYouWant
      value: ===VIRTUALNODE2.CC.THIM.ADDRESS===
    resources:
      limits:
        cpu: 2250m
        memory: 2256Mi
      requests:
        cpu: 100m
        memory: 128Mi
  nodeSelector:
    type: virtual-kubelet
    virtualization: virtualnode2
  tolerations:
  - effect: NoSchedule
    key: virtual-kubelet.io/provider
    operator: Exists

```
Which, assuming you were running a Confidential pod with an image which includes CURL, you could then run something like this to get the THIM attestation: 

    curl GET $THIM_ENDPOINT -H "Metadata: true"