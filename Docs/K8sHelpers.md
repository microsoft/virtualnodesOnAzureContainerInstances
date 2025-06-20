# Kubernetes Helpers

## Table of Contents
- [Cycling pods at a user-configured rhythm](#cycling-pods-at-a-user-configured-rhythm)
  - [Configuring a CronJob to do the deletes](#configuring-a-cronjob-to-do-the-deletes)
  - [Configuring the Pods to request the cleanup](#configuring-the-pods-to-request-the-cleanup)
  - [Additional considerations](#additional-considerations)

## Cycling pods at a user-configured rhythm
Users may want to have pods recycled at a configurable cadence to ensure they are always running on the latest and greatest host updates. This can be achieved with normal K8s techniques, below is an illustration of one implementation.

This technique will only work with templated deployments, as the deletions will cause the Deployment / StatefulSet / ReplicaSet / etc. to put in another replica to replace the deleted pod, "cycling" it to a new host.

### Configuring a CronJob to do the deletes
Below is an example CronJob, which is scheduled to run every 1 minute. It is looking for pods annotated with the label `pod-max-age-minutes`. If the pod is annotated with it, there is a comparison to see if the pod was started longer ago than the maximum allowed lifetime. If it was, a delete command is run (without --force)... which will gracefully trigger the removal of the pod, respecting settings like termination grace period, pre-stop hooks, etc.

``` yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pod-cleanup-by-label
spec:
  schedule: "*/1 * * * *"  # Every 1 minute... feel free to replace with whatever polling frequency is appropriate for your usage
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: pod-cleaner
              image: bitnami/kubectl:latest
              command:
                - /bin/sh
                - -c
                - |
                  NOW=$(date +%s)

                  kubectl get pods --all-namespaces -o json | jq -r --argjson NOW "$NOW" '
                    .items[] |
                    select(.status.phase == "Running") |
                    select(.metadata.labels["pod-max-age-minutes"] != null) |
                    . as $pod |
                    ($NOW - (
                      .status.startTime
                      | sub("\\..*";"")
                      | sub("Z$";"+0000")
                      | strptime("%Y-%m-%dT%H:%M:%S%z")
                      | mktime
                    )) as $age_seconds |
                    ($pod.metadata.labels["pod-max-age-minutes"] | tonumber * 60) as $max_age_seconds |
                    select($age_seconds > $max_age_seconds) |
                    "\($pod.metadata.namespace) \($pod.metadata.name)"' |
                  while read namespace name; do
                    echo "Deleting pod $name in namespace $namespace"
                    kubectl delete pod "$name" -n "$namespace"
                  done
          restartPolicy: OnFailure
          serviceAccountName: <Your Service Account>  # Ensure it has permissions to list/delete pods
```

### Configuring the Pods to request the cleanup
In order to be cleaned up by the CronJob above, the workloads will need to opt-in via a pod label. The label is `pod-max-age-minutes`, and it specifies the cutoff above which the deletion is requested.

An example deployment configured to use this: 
``` yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vn2-maxage
spec:
  replicas: 2
  selector:
    matchLabels:
      app: vn2-maxage
  template:
    metadata:
      labels:
        app: vn2-maxage
        pod-max-age-minutes: "5"
    spec:
      terminationGracePeriodSeconds: 75
      containers:
        - name: sillybox
          image: bitnami/kubectl:latest
          imagePullPolicy: Always
          command:
            - sh
            - -c
            - |
              while true; do
                echo "$MY_ENV";
                sleep 5;
              done
          env:
            - name: MY_ENV
              value: Container 1 Running
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
      nodeSelector:
        virtualization: virtualnode2
      tolerations:
        - effect: NoSchedule
          key: virtual-kubelet.io/provider
          operator: Exists 
```

### Additional considerations
> NOTE: The CronJob as written above is not limited to impacting pods running on virtual nodes... any pod with the `pod-max-age-minutes` label will be impacted.

Merely setting up the automation to cycle pods is often not the full extent of the work. The customer's pods that are being cycled this way should be set up so that they are able to gracefully exit when requested. This can include:
- Configuring a Termination Grace Period that is appropriate to the workload
- Configuring Pre-Stop hooks if actions need to be taken upon the container being prepared to be stopped
- Updating the container business logic to respect the container STOP signaling that the process will be stopped after the configured Termination Grace Period

A good source of relevant information here is the [public K8s documentation for Pod Lifecycle and the Termination of Pods](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination)