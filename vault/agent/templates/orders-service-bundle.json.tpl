{{- with secret "pki_int/issue/orders-service-role" "common_name=orders-service" "ttl=24h" -}}
{{ .Data | toJSON }}
{{- end -}}
