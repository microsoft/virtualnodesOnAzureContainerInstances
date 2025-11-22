# Storage Options

This is a non-exhaustive list of storage options to use with containers in virtual nodes. We are adding new / interesting options here, but should not be taken as loss of support for any already supported storage options. 

## Azure File w/ MI Auth
Azure File Shares recently added support for using ManagedIdentity Auth instead of Client Secrets. We have added support for this in virtual nodes as well as of version 1.3305.25112102, though support does not yet include for Confidential Containers. 

In order to use it, [follow these steps to create an AKS PVC with Az File w/ MI auth](https://github.com/kubernetes-sigs/azurefile-csi-driver/blob/master/docs/managed-identity-mount.md)
Then you can use that PVC normally, with two caveats: 
- The Pods that are using this PVC must be [using the ManagedIdentity](/Docs/PodCustomizations.md#running-pods-with-an-azure-managed-identity) that lines up with the ClientID that is saved into the PVC
- Doesn't yet work for Confidential pods
