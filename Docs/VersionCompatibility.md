# Version Compatibility

## How versioning is provided for virtual nodes
virtual nodes is shipping as HELM releases currently. 

Each HELM release has a version following SemVer, EG - `1.3208.25082901`  
This version is made up of two core bits of information... the K8s binary version used and the build version. 

the MAJOR and MINOR versions of the build `1.3208` are encoding the K8s binary version, in this case `1.32.08`  
the build version is all in the PATCH version `25082901`... in this case, having been the first `01` build of the day for `2025-08-29`.

## Compatibility aims
The ideal is for virtual nodes to be able to release versions which are fully forwards and backwards compatible, but virtual nodes depend on directly utilizing K8s binaries, some of which contain breaking changes and need to be used with only like-versioned control planes.

## virtual node version compatibility with AKS versions

Below are tested configurations which have been verified to be compatible

| Virtual Node Version | AKS 1.29 | AKS 1.30 | AKS 1.31 | AKS 1.32 | AKS 1.33 |
|-----------------------|----------|----------|----------|----------|----------|
| 1.29                 | ✅        | ❌        | ❌        | ❌        | ❌        |
| 1.30                 | ✅        | ✅        | ✅        | ✅        | ❓        |
| 1.32                 | ❌        | ❌        | ❌        | ✅        | ❓        |
| 1.33                 | ❌        | ❌        | ❌        | ✅        | ✅       |
