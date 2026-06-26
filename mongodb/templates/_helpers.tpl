{{/*
MongoDB resource name.
Defaults to .Chart.Name (which equals the dependency alias, e.g. "configdb").
Override with .Values.fullnameOverride to run multiple instances in one release
(e.g. configdb, rundb, metricsdb).
*/}}
{{- define "mongodb.fullname" -}}
{{- .Values.fullnameOverride | default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
