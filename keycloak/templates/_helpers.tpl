{{/*
Keycloak resource name.
Uses Chart.Name directly — single instance, no release name prefix.
*/}}
{{- define "keycloak.fullname" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
