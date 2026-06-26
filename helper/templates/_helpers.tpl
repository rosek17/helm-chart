{{/*
Expand the name of the chart.
*/}}
{{- define "helper.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a fully qualified app name.
Uses release name + chart name, truncated to 63 chars (K8s label limit).
*/}}
{{- define "helper.fullname" -}}
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
Common labels applied to every resource.
*/}}
{{- define "helper.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cloud-rift
{{ include "helper.selectorLabels" . }}
{{- end }}

{{/*
Selector labels — used in both metadata.labels and spec.selector.matchLabels.
*/}}
{{- define "helper.selectorLabels" -}}
app.kubernetes.io/name: {{ include "helper.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Resource block: omits both requests and limits when global.skipResourceConstraints is true.
Emitting only limits is not safe — Kubernetes defaults requests to equal limits when
requests are unset, which is worse than the configured requests for dev environments.
So when the flag is set, we emit an empty block so no resource constraints are applied.
Usage: include "helper.resources" (dict "resources" .Values.resources "global" .Values.global)
*/}}
{{- define "helper.resources" -}}
{{- $global := .global | default dict -}}
{{- $resources := .resources | default dict -}}
{{- if $global.skipResourceConstraints -}}
{}
{{- else -}}
{{ toYaml $resources }}
{{- end }}
{{- end }}

{{/*
Image pull policy: uses global.imagePullPolicy, defaults to IfNotPresent.
*/}}
{{- define "helper.imagePullPolicy" -}}
{{- $global := .Values.global | default dict -}}
{{- $global.imagePullPolicy | default "IfNotPresent" -}}
{{- end }}

{{/*
Container image reference: registry/name:tag
*/}}
{{- define "helper.image" -}}
{{- $global := .Values.global | default dict -}}
{{- $registry := $global.imageRegistry | default "ghcr.io/cloud-rift" -}}
{{- $repo := required "image.repository is required" .Values.image.repository -}}
{{- $tag := .Values.image.tag | default $global.releaseTag | default "latest" -}}
{{- printf "%s/%s:%s" $registry $repo $tag -}}
{{- end }}

