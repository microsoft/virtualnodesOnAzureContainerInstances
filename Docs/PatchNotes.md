# Summary of what was changed in each new release

## Chart Versions:
### 1.3208.25092503
- Update to add capability of setting custom ARM tags for generated ACI CGs 🆕

### 1.3208.25082901
- Update K8s Binaries to 1.32.08 🎊
  - **IMPORTANT NOTE:** Previous 1.30.* virtual nodes releases have no regressions being used with 1.30, 1.31, and 1.32 AKS... **but** 1.32.* virtual nodes requires being run on 1.32.* AKS for full functionality. Please update your AKS cluster to 1.32.* before upgrading your virtual node helm install to this version! [More details on compatibility as well as versioning are being documented here!](/Docs/VersionCompatibility.md)
- Scrubbing secrets that were previously being locally logged 🧼
- Fix for /stats/summary API from Kubelet 🗽
- Added ARM endpoint override to allow virtual nodes to be used in non-public Azure clouds 🤐
- Ingesting security patches and dependency updates 🔐

### 1.3012.25080101
- Update to use new file / mount propagation sidecar 🚃
- Ingesting security patches 🔐

### 1.3012.25072501
- Fix for issue rotating credentials for kube-proxy 🐛
- Customization option added to allow customers with niche requirements to hostPath mount container log directory for virtual node infrastructure pods 🛃

### 1.3012.25071301
- Ingesting security patches 🔐

### 1.3012.25061701
- Fix for a potential race condition when rotating log files 🐛
- Fix for potential issue where automated recovery code for PLEG Health issues could cause bootcycling of infra pods 🦟
- New Heath check added to ensure in rare conditions where infra pods running on AKS lose networking they are detected and restarted 🛜
- Misc Vulnerability patches applied to infrastructure pods 🔐

### 1.3012.25060201
- Add option for configuring Pod Disruption Budget resources for the HELM deployed virtual node infra pods 🆕
- Add option for specifying Priority Class names for the HELM deployed virtual node infra pods ☸️

### 1.3012.25050901
- Updating HELM to use configured images.pullSecrets when creating AdmissionController, for parity in a niche scenario 🦜

### 1.3012.25042501
- Enabled the ability to encrypt deployment data in ACI via Customer Managed Keys for on-demand pods (not yet supported for standby pools) 🔑
- Removed local logging which captured an already invalidated credential token, to avoid the false positives on logged credentials 🐛
- Updated packaged K8s binaries to the latest upstream builds for relevant K8s minor versions ⬆️
- Updated dependencies to address vulnerability reports 🆙

### 1.3009.25031902
- Updated Admission Controller to be built / run on more modern .NET 🥅
- Bug fix for potential deadlock of CRI cache state when many pod deletions occur at once 🐛
- Minor bug fix for logs from virtual node infra missing some relevant data 🐛
- Minor HELM fix to clean up warnings ☸️

### 1.3009.25031001
- Updated virtual node's with compatibility with 1.30, updating to use upstream binaries from 1.30.09 🐣
  - While 1.30 has breaking changes for K8s internal implementation compared to 1.29, this virtual node update ships with both 1.29 and 1.30 binaries and will conditionally use those compatible with the AKS node version it is deployed to.
  - Since virtual nodes is compatible on both sides of that breaking change boundary, existing customers should update their virtual nodes deployment to this 1.30.* compatible deployment FIRST, and then allow their AKS up update node images to 1.30.*
- Added capability to specify a default Azure Zone to deploy pods to at the VN2 level. This is in addition to the existing capability for specifying the zone for particular pods... and the pod having an explicit zone specification will take precedence over the virtual node's node configuration. See further details in the pod and node configuration sections 📝

### 1.2912.25013001
- Bug fix for rare issue that if hit could prevent a virtual node infra pod from successfully initializing 🐛
- Provided ability for customer to configure the usage of a different Azure Resource Group to put ACI CGs into to back virtual node pods. This will enable usage of virtual node with AKS's new NRG lockdown feature. 🆕
- Added annotations to virtual node infra pods to enable them to keep functioning when used with an AKS configured for its customer containers to use an http proxy. 🗒️
- Added ability to use Standby Pool functionality, now in Public Preview! For more information, [see here](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-standby-pool-overview) 🎱

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