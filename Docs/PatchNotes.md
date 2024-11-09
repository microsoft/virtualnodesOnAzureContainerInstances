# Summary of what was changed in each new release

## Chart Versions:
### 1.29.8+241108.01  
- Updated VN2's Kubelet to upstream K8s' 1.29.8 🐣
  - When run with AKS 1.29.*, now enables new 1.29 functionalities for K8s! EG - new K8s style sidecars, now running on virtual nodes!
- Updated Chart Versioning to match K8sVersion+BuildDate.BuildNumber 📰
  - This should enable customers to take updates while also keeping within version compatibility of their AKS's K8s version. 
- Enable VNET override at virtual node level 🛜
  - If `aciSubnetName` provided to `values.yaml` is a full resource ID, it will be used as-is as the default subnet (instead of defaulting to the AKS VNET and looking for the value as a subnet name within it). This allows overriding the default behavior for the whole node.
- Configure Kubelet to auto-rotate certificates ♻️
  - Today, virtual nodes have a node certificate generated for them to access the K8s control plane, which expires in 100 days. With this updated configuration, the kubelet will auto-rotate that certificate when it is in the 10-30% lifetime remaining range. 