# Private DNS-based Windows pod-to-pod connectivity

This example uses ExternalDNS and an Azure Private DNS zone to provide direct
HTTP connectivity between two confidential Windows pods on virtual nodes. The
headless Service publishes the server pod IP, so kube-proxy and a load balancer
are not required.

## Prerequisites

- An AKS cluster with Windows virtual nodes on ACI and Azure CNI networking.
- Azure CLI, kubectl, and PowerShell.
- The identity represented by the virtual node `azure.json` file can manage
  records in the target Azure Private DNS zone.
- Valid client and server CCE policies. See [Confidential Containers](/Docs/PodCustomizations.md#confidential-containers).
- Replace every `<PLACEHOLDER>` below before running the example.

## Configure Azure Private DNS

```powershell
$aksContext = '<AKS_CONTEXT>'
$subscriptionId = '<AZURE_SUBSCRIPTION_ID>'
$resourceGroup = '<RESOURCE_GROUP>'
$vnetName = '<VNET_NAME>'
$zoneName = '<PRIVATE_DNS_ZONE>'

kubectl config use-context $aksContext
az account set --subscription $subscriptionId

# Copy the ExternalDNS Azure configuration from C:\k in the virtual node pod.
$azureConfig = kubectl exec -n '<VN2_NAMESPACE>' '<VN2_POD_NAME>' -c kubelet -- cmd.exe /d /c type C:\k\azure.json
if ($LASTEXITCODE -ne 0) { throw 'Failed to retrieve C:\k\azure.json from the VN2 pod.' }

$azureConfigJson = $azureConfig -join [Environment]::NewLine
$null = ConvertFrom-Json -InputObject $azureConfigJson -ErrorAction Stop

$azureConfigPath = Join-Path (Get-Location) 'azure.json'
[IO.File]::WriteAllText($azureConfigPath, $azureConfigJson, [Text.UTF8Encoding]::new($false))

az network private-dns zone create `
  --resource-group $resourceGroup `
  --name $zoneName

$vnetId = az network vnet show `
  --resource-group $resourceGroup `
  --name $vnetName `
  --query id `
  --output tsv

az network private-dns link vnet create `
  --resource-group $resourceGroup `
  --zone-name $zoneName `
  --name vn2-private-dns-link `
  --virtual-network $vnetId `
  --registration-enabled false

kubectl create secret generic azure-config-file `
  --from-file=azure.json `
  --dry-run=client `
  --output yaml | kubectl apply -f -
```

## Deploy

Replace the placeholders and save this Kubernetes `List` as
`windows-vn2-private-dns.json`. The CCE policies must allow the exact images and
commands shown; the client policy must also allow the curl exec used below.

```json
{
  "apiVersion": "v1",
  "kind": "List",
  "items": [
    {
      "apiVersion": "v1",
      "kind": "ServiceAccount",
      "metadata": {
        "name": "externaldns",
        "namespace": "default"
      }
    },
    {
      "apiVersion": "rbac.authorization.k8s.io/v1",
      "kind": "ClusterRole",
      "metadata": {
        "name": "externaldns"
      },
      "rules": [
        {
          "apiGroups": [""],
          "resources": ["services", "pods"],
          "verbs": ["get", "watch", "list"]
        },
        {
          "apiGroups": ["discovery.k8s.io"],
          "resources": ["endpointslices"],
          "verbs": ["get", "watch", "list"]
        },
        {
          "apiGroups": ["extensions", "networking.k8s.io"],
          "resources": ["ingresses"],
          "verbs": ["get", "watch", "list"]
        },
        {
          "apiGroups": [""],
          "resources": ["nodes"],
          "verbs": ["get", "watch", "list"]
        }
      ]
    },
    {
      "apiVersion": "rbac.authorization.k8s.io/v1",
      "kind": "ClusterRoleBinding",
      "metadata": {
        "name": "externaldns-viewer"
      },
      "roleRef": {
        "apiGroup": "rbac.authorization.k8s.io",
        "kind": "ClusterRole",
        "name": "externaldns"
      },
      "subjects": [
        {
          "kind": "ServiceAccount",
          "name": "externaldns",
          "namespace": "default"
        }
      ]
    },
    {
      "apiVersion": "apps/v1",
      "kind": "Deployment",
      "metadata": {
        "name": "externaldns",
        "namespace": "default"
      },
      "spec": {
        "selector": {
          "matchLabels": {
            "app": "externaldns"
          }
        },
        "strategy": {
          "type": "Recreate"
        },
        "template": {
          "metadata": {
            "labels": {
              "app": "externaldns"
            }
          },
          "spec": {
            "serviceAccountName": "externaldns",
            "containers": [
              {
                "name": "externaldns",
                "image": "registry.k8s.io/external-dns/external-dns:v0.21.0",
                "args": [
                  "--source=service",
                  "--source=ingress",
                  "--domain-filter=<PRIVATE_DNS_ZONE>",
                  "--provider=azure-private-dns",
                  "--azure-resource-group=<RESOURCE_GROUP>",
                  "--azure-subscription-id=<AZURE_SUBSCRIPTION_ID>",
                  "--azure-maxretries-count=1"
                ],
                "volumeMounts": [
                  {
                    "name": "azure-config-file",
                    "mountPath": "/etc/kubernetes",
                    "readOnly": true
                  }
                ]
              }
            ],
            "volumes": [
              {
                "name": "azure-config-file",
                "secret": {
                  "secretName": "azure-config-file"
                }
              }
            ]
          }
        }
      }
    },
    {
      "apiVersion": "apps/v1",
      "kind": "Deployment",
      "metadata": {
        "name": "vn2-dns-client",
        "namespace": "default"
      },
      "spec": {
        "selector": {
          "matchLabels": {
            "app": "vn2-dns-client"
          }
        },
        "template": {
          "metadata": {
            "labels": {
              "app": "vn2-dns-client"
            },
            "annotations": {
              "microsoft.containerinstance.virtualnode.injectkubeproxy": "false",
              "microsoft.containerinstance.virtualnode.injectdns": "false",
              "microsoft.containerinstance.virtualnode.ccepolicy": "<CLIENT_CCE_POLICY>"
            }
          },
          "spec": {
            "containers": [
              {
                "name": "client",
                "image": "mcr.microsoft.com/windows/nanoserver:ltsc2025",
                "command": [
                  "cmd",
                  "/d",
                  "/s",
                  "/c",
                  "echo Windows VN2 DNS client ready && ping -t 127.0.0.1 > nul"
                ],
                "resources": {
                  "requests": {
                    "cpu": "1",
                    "memory": "2G"
                  }
                }
              }
            ],
            "nodeSelector": {
              "kubernetes.io/os": "windows",
              "type": "virtual-kubelet",
              "virtualization": "virtualnode2",
              "pool": "<VN2_POOL_LABEL>"
            },
            "tolerations": [
              {
                "effect": "NoSchedule",
                "key": "virtual-kubelet.io/provider",
                "operator": "Exists"
              }
            ]
          }
        }
      }
    },
    {
      "apiVersion": "apps/v1",
      "kind": "Deployment",
      "metadata": {
        "name": "vn2-dns-server",
        "namespace": "default"
      },
      "spec": {
        "selector": {
          "matchLabels": {
            "app": "vn2-dns-server"
          }
        },
        "template": {
          "metadata": {
            "labels": {
              "app": "vn2-dns-server"
            },
            "annotations": {
              "microsoft.containerinstance.virtualnode.injectkubeproxy": "false",
              "microsoft.containerinstance.virtualnode.injectdns": "false",
              "microsoft.containerinstance.virtualnode.ccepolicy": "<SERVER_CCE_POLICY>"
            }
          },
          "spec": {
            "containers": [
              {
                "name": "server",
                "image": "mcr.microsoft.com/dotnet/samples:aspnetapp-nanoserver-ltsc2025",
                "command": [
                  "cmd",
                  "/d",
                  "/s",
                  "/c",
                  "AspNetCoreRazorApp"
                ],
                "ports": [
                  {
                    "containerPort": 8080
                  }
                ],
                "resources": {
                  "requests": {
                    "cpu": "1",
                    "memory": "2G"
                  }
                }
              }
            ],
            "nodeSelector": {
              "kubernetes.io/os": "windows",
              "type": "virtual-kubelet",
              "virtualization": "virtualnode2",
              "pool": "<VN2_POOL_LABEL>"
            },
            "tolerations": [
              {
                "effect": "NoSchedule",
                "key": "virtual-kubelet.io/provider",
                "operator": "Exists"
              }
            ]
          }
        }
      }
    },
    {
      "apiVersion": "v1",
      "kind": "Service",
      "metadata": {
        "name": "vn2-dns-server",
        "namespace": "default",
        "annotations": {
          "external-dns.alpha.kubernetes.io/internal-hostname": "server.<PRIVATE_DNS_ZONE>"
        }
      },
      "spec": {
        "clusterIP": "None",
        "selector": {
          "app": "vn2-dns-server"
        },
        "ports": [
          {
            "port": 8080
          }
        ]
      }
    }
  ]
}
```

Apply the resources and wait for the workloads:

```powershell
kubectl apply -f .\windows-vn2-private-dns.json
kubectl rollout status deployment/externaldns --timeout=2m
kubectl rollout status deployment/vn2-dns-client --timeout=10m
kubectl rollout status deployment/vn2-dns-server --timeout=10m
```

## Validate

```powershell
$serverIP = kubectl get pods -l app=vn2-dns-server -o jsonpath='{.items[0].status.podIP}'
$deadline = (Get-Date).AddMinutes(2)
$dnsIP = $null

do {
  $dnsIP = az network private-dns record-set a show `
    --resource-group $resourceGroup `
    --zone-name $zoneName `
    --name server `
    --query 'aRecords[0].ipv4Address' `
    --output tsv 2>$null

  if (-not $dnsIP) { Start-Sleep -Seconds 5 }
} while (-not $dnsIP -and (Get-Date) -lt $deadline)

if ($dnsIP -ne $serverIP) {
  kubectl logs deployment/externaldns --tail=100
  throw "DNS IP '$dnsIP' does not match server pod IP '$serverIP'."
}

$clientPod = kubectl get pods -l app=vn2-dns-client -o jsonpath='{.items[0].metadata.name}'
$target = "http://server.${zoneName}:8080/"
$status = kubectl exec $clientPod -c client -- cmd /d /s /c `
  "curl.exe -sS -o NUL -w `"%{http_code}`" $target"
$curlExitCode = $LASTEXITCODE
$status = (($status | Out-String).Trim()).Trim('"')

if ($curlExitCode -ne 0 -or $status -ne '200') {
  throw "Expected HTTP 200, got '$status' (kubectl exec exit code $curlExitCode)."
}

Write-Host 'PASS: private DNS and direct Windows VN2 pod-to-pod HTTP connectivity work.' -ForegroundColor Green
```

## Cleanup

```powershell
kubectl delete -f .\windows-vn2-private-dns.json --ignore-not-found
kubectl delete secret azure-config-file --ignore-not-found

az network private-dns link vnet delete `
  --resource-group $resourceGroup `
  --zone-name $zoneName `
  --name vn2-private-dns-link `
  --yes

az network private-dns zone delete `
  --resource-group $resourceGroup `
  --name $zoneName `
  --yes

Remove-Item -LiteralPath .\azure.json -Force
```