{{- with secret "pki_int/issue/users-service-role" "common_name=users-service" "ttl=24h" -}}
{{ .Data | toJSON }}
{{- end -}}
