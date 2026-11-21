{{- /* Helpers of templates/auto-build.yaml. */ -}}

{{- /* An installation token of the platform GitHub App for the reconcile pass: ESO GithubAccessToken generator <name>
(scoped to `permissions`) + ExternalSecret <token> that re-mints it every autoBuild.github.tokenRefreshInterval. */ -}}
{{- define "autoBuild.githubToken" -}}
{{- $a := .root.Values.autoBuild }}
{{- $ns := printf "workflows-%s" .root.Values.openchoreo.orgNamespace }}
{{- $app := printf "%s-github-app" $a.workflowTemplate -}}
apiVersion: generators.external-secrets.io/v1alpha1
kind: GithubAccessToken
metadata:
  name: {{ .name }}
  namespace: {{ $ns }}
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  appIDRef: { name: {{ $app }}, key: app-id }
  installIDRef: { name: {{ $app }}, key: installation-id }
  permissions: {{- toYaml .permissions | nindent 4 }}
  auth:
    privateKey:
      secretRef: { name: {{ $app }}, key: private-key }
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ .token }}
  namespace: {{ $ns }}
spec:
  refreshInterval: {{ $a.github.tokenRefreshInterval }}
  target:
    name: {{ .token }}
    creationPolicy: Owner
    deletionPolicy: Delete
  dataFrom:
    - sourceRef:
        generatorRef:
          apiVersion: generators.external-secrets.io/v1alpha1
          kind: GithubAccessToken
          name: {{ .name }}
{{- end }}

{{- /* CronWorkflow <name>-<suffix> starting one reconcile pass per tick; Forbid: a slow pass is never overlapped. */ -}}
{{- define "autoBuild.cronWorkflow" -}}
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: {{ .name }}-{{ .suffix }}
  namespace: {{ .ns }}
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  schedules: [{{ .schedule | quote }}]
  timezone: UTC
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 30
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 3
  workflowMetadata:
    labels:
      platform.koorikla.io/trigger: {{ .trigger }}
  workflowSpec:
    workflowTemplateRef:
      name: {{ .name }}
{{- end }}
