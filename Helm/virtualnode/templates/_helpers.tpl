{{/*
Expand the name of the chart.
*/}}
{{- define "virtualnode2.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "virtualnode2.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "virtualnode2.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "virtualnode2.labels" -}}
helm.sh/chart: {{ include "virtualnode2.chart" . }}
{{ include "virtualnode2.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "virtualnode2.selectorLabels" -}}
app.kubernetes.io/name: {{ include "virtualnode2.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "virtualnode2.admissionSelectorLabels" -}}
app.kubernetes.io/name: "admissioncontroller"
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "virtualnode2.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "virtualnode2.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Kube-proxy enabled value. It is backward compatible with old "kubeProxyEnabled" setting.
Priority: kubeProxyEnabled (old) > kubeProxy.enabled (new) > "true" (default)
*/}}
{{- define "virtualnode2.kubeProxyEnabled" -}}
{{- if hasKey .Values "kubeProxyEnabled" -}}
{{- .Values.kubeProxyEnabled | quote }}
{{- else if hasKey .Values.kubeProxy "enabled" -}}
{{- .Values.kubeProxy.enabled | quote }}
{{- else -}}
"true"
{{- end }}
{{- end }}

{{/*
Resolve the target namespace.
If the user provided --namespace on helm install (i.e. Release.Namespace is not "default"),
use that. Otherwise fall back to .Values.namespace (default "vn2") for backward compatibility.
*/}}
{{- define "virtualnode2.namespace" -}}
{{- if eq .Release.Namespace "default" -}}
{{- .Values.namespace | default "vn2" -}}
{{- else -}}
{{- .Release.Namespace -}}
{{- end -}}
{{- end }}

{{/*
AKS required affinity rules.
These ensure pods are not scheduled on virtual-kubelet nodes,
run on Linux, and only on AKS clusters.
*/}}
{{- define "virtualnode2.aksRequiredAffinity" -}}
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
      - matchExpressions:
          - key: type
            operator: NotIn
            values:
              - virtual-kubelet
          - key: kubernetes.io/os
            operator: In
            values:
              - linux
          - key: kubernetes.azure.com/cluster
            operator: Exists
{{- end }}

{{/*
Merged affinity: AKS required rules merged on top of user-configured .Values.affinity.
AKS rules take precedence over any conflicting user-configured values.
*/}}
{{- define "virtualnode2.affinity" -}}
{{- $aksAffinity := include "virtualnode2.aksRequiredAffinity" . | fromYaml }}
{{- $userAffinity := .Values.affinity | default dict }}
{{- $merged := mustMergeOverwrite (deepCopy $userAffinity) $aksAffinity }}
{{- toYaml $merged }}
{{- end }}
