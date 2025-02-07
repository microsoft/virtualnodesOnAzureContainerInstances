# Summary of what was changed in each new release

## Chart Versions:
### 1.2912.25013001
- Bug fix for rare issue that if hit could prevent a virtual node infra pod from successfully initializing
- Provided ability for customer to configure the usage of a different Azure Resource Group to put ACI CGs into to back virtual node pods. This will enable usage of virtual node with AKS's new NRG lockdown feature. 
- Added annotations to virtual node infra pods to enable them to keep functioning when used with an AKS configured for its customer containers to use an http proxy. 
- Added ability to use Standby Pool functionality, now in Public Preview! For more information, [see here](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-standby-pool-overview)

### 1.2912.25010701
- Updated virtual node's upstream binaries to 1.29.12 🐣
- Updated Chart Versioning to match (K8sMajor).(K8sMinor)(K8sPatch).(virtualnodeBuildDate)(virtualnodeBuildNumber) 📰
  - Resolves an issue with web publishing of HELM... HELM isn't fully supportive of SEMVER standards, so removing the `+`
  - Preserves ability for matching virtual nodes' K8s version with AKS control plane 
- Updated build processes / dependencies for virtual node's infra containers to resolve security advisories 🔐

### 1.2908.24110801
- Updated virtual node's Kubelet to upstream K8s' 1.29.8 🐣
  - When run with AKS 1.29.*, now enables new 1.29 functionalities for K8s! EG - new K8s style sidecars, now running on virtual nodes!
- Updated Chart Versioning to match K8sVersion+BuildDate.BuildNumber 📰
  - This should enable customers to take updates while also keeping within version compatibility of their AKS's K8s version. 
- Enable VNET override at virtual node level 🛜
  - If `aciSubnetName` provided to `values.yaml` is a full resource ID, it will be used as-is as the default subnet (instead of defaulting to the AKS VNET and looking for the value as a subnet name within it). This allows overriding the default behavior for the whole node.
- Configure Kubelet to auto-rotate certificates ♻️
  - Today, virtual nodes have a node certificate generated for them to access the K8s control plane, which expires in 100 days. With this updated configuration, the kubelet will auto-rotate that certificate when it is in the 10-30% lifetime remaining range. 