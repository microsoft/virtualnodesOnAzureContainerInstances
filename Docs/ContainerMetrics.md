# Container Metrics
## Utilizing new metrics endpoint w/ Prometheus
Prometheus is a popular open-source systems monitoring and alerting toolkit used in K8s.

By default, Prometheus uses some older metrics APIs which are on the path to deprecation, and which do not work in virtual nodes because they cause the kubelet to examine its local system usage, rather than utilizng the usage metrics flowing from containerD via the CRI as the more modern APIs do.

For virtual nodes, we created a new endpoint which provides the types of data that Prometheus would not be able to retrieve from that legacy API. To utilize this new endpoint with Prometheus in AKS, first you will need your cluster to have managed Prometheus enabled. Please follow these steps to enable Prometheus: 
[Setting up AKS Monitoring](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable?tabs=cli)

Once those are installed as a prerequisite, you can configure it to use the new endpoint by registering a pod monitor. The below is assuming you are using the default `vn2` namespace for your virtual node installation. 

```json
{
    "apiVersion": "azmonitoring.coreos.com/v1",
    "kind": "PodMonitor",
    "metadata": {
        "name": "vn2-metrics",
        "namespace": "vn2"
    },
    "spec": {
        "namespaceSelector": {
            "matchNames": [
                "vn2"
            ]
        },
        "podMetricsEndpoints": [
            {
                "interval": "30s",
                "metricRelabelings": [
                    {
                        "action": "labeldrop",
                        "regex": "^(pod|namespace|container)$"
                    },
                    {
                        "action": "labelmap",
                        "regex": "^exported_(.*)",
                        "replacement": "$1"
                    },
                    {
                        "action": "replace",
                        "replacement": "cadvisor",
                        "targetLabel": "job"
                    },
                    {
                        "action": "replace",
                        "replacement": "vn2",
                        "targetLabel": "image"
                    }
                ],
                "path": "/metrics",
                "port": "http",
                "scheme": "http",
                "targetPort": 50052
            }
        ],
        "selector": {
            "matchLabels": {
                "app.kubernetes.io/name": "virtualnode"
            }
        }
    }
}
```


With that applied, you should shortly start seeing metrics flowing to Prometheus for your pods running on the virtual nodes!

