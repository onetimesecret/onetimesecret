{{/*
Expand the name of the chart.
*/}}
{{- define "chart.name" -}}
{{- default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}


{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "chart.labels" -}}
helm.sh/chart: {{ include "chart.chart" . }}
{{ include "chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "chart.serviceAccountName" -}}
{{- include "chart.name" . }}
{{- end }}

{{/*
Define the ots.secret value

Logic:
If the values define a secret value, use that.
Otherwise, if there's already a k8s secret, use the existing value from the secret
Finally, if none of those are true, create a random secret (that will be injected into the secret and reused when the chart is upgraded)

*/}}
{{- define "ots.secret" -}}
{{- $secretValue := "" -}}
{{- if .Values.ots.site.secret }}
{{- $secretValue = .Values.ots.site.secret | trunc 63 | b64enc }}
{{- else }}
  {{- $existingSecret := (lookup "v1" "Secret" .Release.Namespace (cat (include "chart.name" .) "-secret")) -}}
  {{- if $existingSecret -}}
    {{- $secretValue = get $existingSecret.data "ots-secret" -}}
  {{- else }}
    {{- $secretValue = cat .Release.Name (randAlphaNum 40) | nospace | b64enc | trunc 63 | b64enc }}
  {{- end -}}
{{- end}}
{{- $secretValue }}
{{- end }}