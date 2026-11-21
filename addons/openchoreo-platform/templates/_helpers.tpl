{{- /* Argo CD may apply an OpenChoreo object before its CRD exists (addon openchoreo-control-plane installs them):
add SkipDryRunOnMissingResource to an object loaded from files/. Call: include "platform.skipDryRun" $obj */ -}}
{{- define "platform.skipDryRun" -}}
{{- $_ := set .metadata "annotations" (merge (default dict .metadata.annotations) (dict "argocd.argoproj.io/sync-options" "SkipDryRunOnMissingResource=true")) -}}
{{- end }}

{{- /* ExternalSecret <name> with a GitHub App's credentials (store key with githubAppID, githubAppInstallationID,
githubAppPrivateKey), read only by ESO's GithubAccessToken generators. Call: dict "name" "namespace" "store" "key" */ -}}
{{- define "platform.githubAppSecret" -}}
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ .name }}
  namespace: {{ .namespace }}
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: {{ .store }}
  target:
    name: {{ .name }}
    creationPolicy: Owner
    deletionPolicy: Delete
  data:
    - secretKey: app-id
      remoteRef: { key: {{ .key }}, property: githubAppID }
    - secretKey: installation-id
      remoteRef: { key: {{ .key }}, property: githubAppInstallationID }
    - secretKey: private-key
      remoteRef: { key: {{ .key }}, property: githubAppPrivateKey }
{{- end }}
