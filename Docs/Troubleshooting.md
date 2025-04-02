# Troubleshooting

## Table of Contents

1. [Networking](#network-troubleshooting)
2. [Confidential Containers](#confidential-troubleshooting) 

## Network Troubleshooting

Are your pods deployed to virtual nodes experiencing issues or high latency with outbound network calls?

- Is the Subnet you configured for ACI (default name `cg`) configured with a NAT Gateway?
  - It should be! See the **IMPORTANT** tag in the [VNET configuration section from the setup](/README.md#step-2-azure-virtual-network). Update the subnet to use a NAT Gateway and re-create the pod! 

- Is the problem only occurring in pods with [kube-proxy disabled](/Docs/PodCustomizations.md#disable-kube-proxy) or in [Confidential pods](/Docs/PodCustomizations.md#confidential-containers)?
  - The default AKS configuration is to use an internal cluster DNS, which works great... except, it runs on a cluster IP. That means the DNS is only accessible from a machine while kube-proxy is running, updating network routing. Disabling kube-proxy explicitly via the pod annotation or implicitly by using Confidential (which doesn't support kube-proxy usage, see note in [kube-proxy pod annotation](/Docs/PodCustomizations.md#disable-kube-proxy)) is making the K8s injected DNS entry unreachable. Clients which support multi-DNS configuration may succeed but with added latency from waiting on the first DNS entry return. Our recommendation is to [disable K8s DNS injection](/Docs/PodCustomizations.md#disable-k8s-dns-injection) in this case.

## Confidential Troubleshooting

### Policy Decision Information

Like with all K8s containers, a diagnostic step to understand what might have happened is to check the pod's event logs (for example, via `kubectl describe`). However, for confidential containers the errors are often not immediately understandable. 

For example, you might see an event like this: 
``` text
failed to create containerd task: failed to create shim task: failed to create container 18197025abfacf6365ef65d083687e1d9f03b9792779e15796247a7281043065: guest RPC failure: container creation denied due to policy: policyDecision< eyJkZWNpc2lvbiI6ImRlbnkiLCJyZWFzb24iOnsiZXJyb3JzIjpbImludmFsaWQgY29tbWFuZCJdfSwidHJ1bmNhdGVkIjpbImlucHV0Il19 >policyDecision: unknown
```
While not immediately obvious, the policy decision section is actually a base64 encoded string with the underlying error. 

Decoding the above example (any base64 decoder will do, the built-in utility for PowerShell used here for portability): 
``` powershell
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("eyJkZWNpc2lvbiI6ImRlbnkiLCJyZWFzb24iOnsiZXJyb3JzIjpbImludmFsaWQgY29tbWFuZCJdfSwidHJ1bmNhdGVkIjpbImlucHV0Il19"))

{"decision":"deny","reason":{"errors":["invalid command"]},"truncated":["input"]}
```

So, for this example the issue was that the container's CCE Policy didn't have the same command for the container as what was actually being run for it. 

### `deviceHash not found` Error

You might decode a confidential policy decision error that says something like this: 

``` json
{"decision":"deny","input":{"deviceHash":"deab9495e4a3c245e3be675a350d0e7a9fe6dcdc95a73582f8586dd759ca7a0b","rule":"mount_device","target":"/run/mounts/m9"},"reason":{"errors":["deviceHash not found"]}}
```

This type of error most commonly occurs when the image layers for the container provided in the CCE Policy do not align with the actual pulled image layers for the container. 

This can happen in cases where an image is updated without regenerating the CCE policy... which can happen unexpectedly when using public images or images with tags that are overwritten (a common example being `latest`). 

Confidential containers are behaving as designed and explicitly protecting your usage from these unauthorized updates (that do not align with the Confidential Policy provided), but in so doing will prevent the pods from going into a running state. 

The recommendation would be to use images from an image registry you control and to not overwrite tags... both of which will make it easier for you to control what you are deploying and avoid unexpected updates.