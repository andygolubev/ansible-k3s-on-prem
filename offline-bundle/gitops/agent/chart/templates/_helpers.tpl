{{- define "agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "agent.fullname" -}}
{{- printf "%s" (include "agent.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

