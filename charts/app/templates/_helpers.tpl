{{- define "app.labels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}-{{ .Release.Namespace }}
app.kubernetes.io/managed-by: argocd
{{- end }}

{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}-{{ .Release.Namespace }}
{{- end }}
