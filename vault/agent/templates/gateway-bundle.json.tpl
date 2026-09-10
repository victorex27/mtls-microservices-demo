{{- with secret "pki_int/issue/gateway-role" "common_name=api-gateway" "ttl=24h" -}}
{{ .Data | toJSON }}
{{- end -}}
