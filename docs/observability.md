# Observability and runtime security

OpenChoreo's **observability plane** stores logs, traces and metrics for everything OpenChoreo deploys. Backstage (Runtime
Logs / Metrics / Traces tabs, RuntimeHealthCard), openchoreo-api and the MCP servers read it through the **observer**
API. Data planes ship telemetry to it; an OpenTelemetry Collector on every workload cluster is the fan-out point, so
Datadog (or any other OTLP backend) is a values overlay. Falco watches syscalls on every cluster; Falco Talon responds
in app namespaces. Planes and trust in general: [openchoreo.md](openchoreo.md).

## What runs where

| Where | Addon (catalog) | Namespace | What |
|---|---|---|---|
| mgmt | `openchoreo-observability-plane` | openchoreo-observability-plane | OpenChoreo 1.3.3 observability plane (observer, controller-manager, cluster-agent, Gateway `gateway-default` on 11080/11085) + community modules: logs `observability-logs-opensearch` 0.7.0 (OpenSearch 3.3 single node, logs-adapter), traces `observability-tracing-opensearch` 0.8.0 (OTLP receiver collector, tracing-adapter), metrics `observability-metrics-prometheus` 0.8.0 (Prometheus + operator + Alertmanager, metrics-adapter); `ClusterObservabilityPlane default` |
| workload | `telemetry` | telemetry | Fluent Bit (container logs), Prometheus agent + kube-state-metrics (pod metrics), events collector (k8s events), OpenTelemetry Collector DaemonSet (OTLP fan-out) |
| workload (opt-in) | `obi` | obi | OpenTelemetry eBPF Instrumentation v1.0.0: zero-code L7 RED metrics + traces for app namespaces |
| workload (opt-in) | `keda`, `strimzi`, `cloudnative-pg` | keda, strimzi, cnpg-system | data-service operators; their ServiceMonitors/PodMonitors are scraped by the telemetry Prometheus agent (it selects every monitor in every namespace) - [data-services.md](data-services.md) |
| mgmt + workload | `falco` | falco | Falco 0.45 (modern eBPF) + falcosidekick; Falco Talon on workload clusters |
| mgmt | `argo-events` | argo-events | Argo Events 1.9: Falco escalation receiver -> WorkflowTemplate `falco-response`; rollout events -> promotion gate ([promotion.md](promotion.md)) |
| mgmt | `charts/cluster` | – | `ClusterDataPlane.spec.observabilityPlaneRef` -> `ClusterObservabilityPlane default` |

Switch: `openchoreo.observability.enabled` in `installations/<inst>/installation.yaml` (local: true). It drives the
`observabilityPlaneRef` on every ClusterDataPlane and must match `backstage.features.observability.enabled` in the
control-plane addon (validated). With it false, also disable the `openchoreo-observability-plane` and `telemetry`
addons (their validate templates fail otherwise, on purpose).

## Topology and trust

```
workload cluster <name>                                      mgmt (k3d platform-mgmt)
 ns telemetry                                                 ns openchoreo-observability-plane
  Fluent Bit ──── https (TLS passthrough, basic auth) ──┐      Gateway gateway-default (kgateway, LoadBalancer -> klipper)
  events collector ─────────────────────────────────────┤ :11085  └ TLSRoute opensearch ─────────► OpenSearch :9200
  Prometheus agent ── remote write (HTTP) ──────────────┤ :11080  ├ HTTPRoute prometheus-remote-write ► Prometheus :9091
  OTel Collector ──── OTLP/HTTP ────────────────────────┘ :11080  ├ HTTPRoute opentelemetry-collector-otlp ► receiver -> OpenSearch
   ▲ OTLP  ▲ CloudEvents                                          └ HTTPRoute observer ─► observer ◄─ Backstage, openchoreo-api, MCP
  apps/OBI  falcosidekick                                      cluster-agent ── wss in-cluster ──► cluster-gateway (ns openchoreo-control-plane)
```

- **Co-located with the control plane.** The plane's cluster-agent dials the cluster-gateway in-cluster
  (`wss://cluster-gateway.openchoreo-control-plane.svc.cluster.local:8443/ws`; the gateway's server cert carries that
  SAN). Its identity is the chart's self-signed client cert (Secret `cluster-agent-tls`, CN `default`);
  `ClusterObservabilityPlane default` trusts exactly that certificate through a `secretKeyRef` (same cluster, nothing
  copied). The agent verifies the gateway with ConfigMap `cluster-gateway-ca` (public cert only), written by ESO from
  `openchoreo-control-plane/cluster-gateway-ca` key `ca.crt` via ClusterSecretStore `mgmt-openchoreo`. No CA private key
  is copied anywhere.
- **Ingestion from data planes** uses what 1.3.3 ships: OpenSearch's own TLS + basic auth for logs/events; plain HTTP
  through the Gateway for OTLP and remote write (upstream has no collector mTLS yet). Acceptable on one docker network;
  a cloud installation needs TLS and authenticated ingest first ([#46](https://github.com/koorikla/platform/issues/46)).
- **One OpenSearch** (single node) holds container logs (`container-logs-*`), k8s events (`k8s-events-*`) and traces
  (`otel-traces-*`); index setup Jobs and retention (7d locally) come from the modules. Prometheus keeps 7d.
- Metric and log alerts: `ClusterTrait observability-alert-rule` (allowed on `service`, `web-application`, `worker`;
  [Component alert rules](#component-alert-rules)) -> `ObservabilityAlertRule` on the observability plane ->
  PrometheusRule -> Alertmanager -> metrics-adapter -> observer (`source.type: metric`), or OpenSearch alerting ->
  observer (`source.type: log`).

## Endpoints, ports, DNS (local)

k3d publishes, in addition to 8080/8443 (control plane):

```
k3d cluster create platform-mgmt ... -p "11080:11080@loadbalancer" -p "11085:11085@loadbalancer"
```

Nothing else on mgmt may bind hostPort 11080/11085.

| URL | Served by | Used by |
|---|---|---|
| http://observer.openchoreo.localhost:11080 (+ `/mcp`) | observer | Backstage (browser + backend), openchoreo-api, MCP clients; `ClusterObservabilityPlane.spec.observerURL` |
| http://opentelemetry.observability.openchoreo.localhost:11080 | trace receiver (OTLP/HTTP, gRPC by content-type) | data-plane OTel collectors |
| http://prometheus.observability.openchoreo.localhost:11080/api/v1/write | Prometheus remote-write receiver | data-plane Prometheus agents (and the collector's OTLP metrics) |
| opensearch.observability.openchoreo.localhost:11085 | OpenSearch (TLS passthrough, SNI) | Fluent Bit, events collector |

Name resolution (`coredns-local`): on workload clusters the existing rule already sends every `*.openchoreo.localhost`
name to `k3d-platform-mgmt-serverlb` (which now also forwards 11080/11085). On mgmt a second rule, placed first, sends
`observer.openchoreo.localhost` and `*.observability.openchoreo.localhost` to
`gateway-default.openchoreo-observability-plane.svc.cluster.local` (Service port == listener == published port), so pod
and browser URLs are identical. Browsers resolve `*.localhost` to loopback.

The literals in the addon values are checked against `openchoreo.controlPlane.host` and
`openchoreo.observability.{httpPort,tlsPort}` at render time; the data-plane collector derives its endpoints from them
(ConfigMap `telemetry-env`).

## Signals

| Signal | Source on the data plane | Path | Backstage / observer |
|---|---|---|---|
| Container logs | Fluent Bit tail `/var/log/containers` (+ kubernetes filter, `openchoreo_cluster_instance=<cluster>`) | OpenSearch `container-logs-*` | Runtime Logs |
| k8s events | events collector (OpenChoreo build, enriched with owner labels) | OpenSearch `k8s-events-*` | events |
| Pod CPU/memory | Prometheus agent: kubelet/cAdvisor + kube-state-metrics with `openchoreo.dev/*` pod labels | remote write -> Prometheus | Metrics, RuntimeHealthCard |
| Traces | apps (OTLP SDK) / OBI -> OTel Collector (k8s_attributes: all pod labels, cluster name) | OTLP/HTTP -> receiver -> OpenSearch `otel-traces-*` | Traces |
| OTLP metrics | apps / OBI / falcosidekick -> OTel Collector | remote write -> Prometheus | (PromQL) |
| App metrics (opt-in) | the app's own `/metrics` -> Prometheus agent (PodMonitor of ClusterTrait `metrics`, [openchoreo.md](openchoreo.md#application-metrics), #252) | remote write -> Prometheus | (PromQL) |
| Gateway HTTP response codes | kgateway Envoy `gateway-default` in `openchoreo-data-plane` (`envoy_cluster_upstream_rq`) -> Prometheus agent (PodMonitor `kgateway-http`) | remote write -> Prometheus | promotion gate 5xx rate (PromQL) |
| HTTP request metrics | Cilium Hubble L7 (`hubble_http_*`, Cilium data planes only; none today) -> Prometheus agent (ServiceMonitor `hubble-http`) | remote write -> Prometheus | Metrics (HTTP) |
| Falco alerts | Falco JSON on stdout -> Fluent Bit; falcosidekick -> collector (CloudEvents) | OpenSearch `container-logs-*` (ns falco); Datadog overlay | logs |

Apps send OTLP to the node-local collector: `OTEL_EXPORTER_OTLP_ENDPOINT=http://telemetry-collector.telemetry.svc.cluster.local:4318`
(Service with `internalTrafficPolicy: Local`), or `http://$(HOST_IP):4318` (hostPort).

**Prometheus agent load.** The metrics module hardcodes the agent's resources (requests 50m/128Mi, limits 200m/256Mi;
no value in observability-metrics-prometheus 0.8.0-0.9.0), so the telemetry addon keeps the scrape set to what
OpenChoreo reads. Its metrics adapter queries `container_cpu_usage_seconds_total` and
`container_memory_working_set_bytes` (kubelet `/metrics/cadvisor`), `kube_pod_*` (kube-state-metrics),
`hubble_http_*` and OpenCost's `node_*_hourly_cost`. The kubelet `/metrics` endpoint is not scraped
(`kube-prometheus-stack.kubelet.serviceMonitor.kubelet: false`): on k3s it also serves the embedded control plane,
~100k samples (15 MB) per scrape on dev1. Dropping those families with `metricRelabelings` cut the stored series but
not the cost of fetching, parsing and caching every sample, which held the agent at 230-250 MiB
([#83](https://github.com/koorikla/platform/issues/83)). The kubelet ServiceMonitor scrapes `/metrics/cadvisor` and
`/metrics/probes` (contract `hack/tests/test_telemetry_series.sh`); `kubelet_*` series (volume stats, pod start
latency) are not collected. Check: `prometheus_agent_active_series` on the agent's `:9090/metrics`,
`kubectl top pod -n telemetry --containers`.

## Component alert rules

`ClusterTrait observability-alert-rule` (`addons/openchoreo-platform/files/cluster-traits/observability-alert-rule.yaml`)
is allowed on `service`, `web-application` and `worker` `ClusterComponentType`s. A `Component` attaches one trait entry
per rule (with a unique `instanceName`); when the component's `ClusterDataPlane` sets `observabilityPlaneRef`, each
`ReleaseBinding` renders an `ObservabilityAlertRule` (`targetPlane: observabilityplane`) that the observability-plane
controller reconciles through `observer`:

- `source.type: metric` (`metric: cpu_usage` or `memory_usage`): `metrics-adapter` writes a `PrometheusRule` in
  `openchoreo-observability-plane`; firing alerts go Prometheus -> Alertmanager -> `observer` (`/api/v1alpha1/alerts/webhook`)
  -> notification channel and the observer alert store (queried by Backstage and by the promotion gate via
  `POST /api/v1/alerts/query`).
- `source.type: log` (`query`: substring matched against `container-logs-*`): `logs-adapter` writes an OpenSearch
  alerting monitor that posts firing alerts to `observer`.

OpenChoreo's trait validation requires a notification channel for every rule: either set
`traitEnvironmentConfigs.<instanceName>.actions.notifications.channels` on the `ReleaseBinding` (naming an
`ObservabilityAlertsNotificationChannel` in the org namespace for that environment) or set
`spec.defaultNotificationChannel` on the `Environment`.

```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: Component
metadata:
  name: hello-world
  namespace: default
spec:
  owner:
    projectName: demo
  componentType:
    kind: ClusterComponentType
    name: deployment/service
  traits:
    - kind: ClusterTrait
      name: observability-alert-rule
      instanceName: high-cpu
      parameters:
        description: "Pod CPU usage above 80% for 5 minutes"
        severity: critical
        source:
          type: metric
          metric: cpu_usage
        condition:
          window: 5m
          interval: 1m
          operator: gt
          threshold: 80
---
apiVersion: openchoreo.dev/v1alpha1
kind: ReleaseBinding
metadata:
  name: hello-world-staging
  namespace: default
spec:
  owner:
    projectName: demo
    componentName: hello-world
  environment: staging
  releaseName: hello-world-20261116-1
  traitEnvironmentConfigs:
    high-cpu:
      enabled: true
      actions:
        notifications:
          channels:
            - ops-webhook-staging
```

## Secrets

| Store / key | Properties | Used by |
|---|---|---|
| `platform` / `openchoreo-observability` (mgmt) | `opensearch-username` (must be `admin`), `opensearch-password` (OpenSearch 3 policy: >= 8 chars, upper, lower, digit, special), `observer-client-secret` (== Thunder client `openchoreo-observer-resource-reader-client`) | OpenSearch admin + setup Jobs + adapters + trace receiver; observer UID resolver |
| `default` / `openchoreo-observability` (workload) | `opensearch-username`, `opensearch-password` | Fluent Bit, events collector |
| `default` / `datadog` (workload, optional) | `api-key` | collector datadog exporter (Secret `telemetry-datadog`, env `DD_API_KEY`) |
| `platform` / `falco-webhook` (mgmt only) | `url` (base, e.g. `http://events.<host>:8080/falco`), `token` | Falco escalation: per-cluster tokens `sha256("<cluster>:<token>")` derived from it on mgmt for addon argo-events (receiver), addon falco on mgmt and the workload clusters' CRS payloads ([Falco response](#falco-response)); never copied to a workload cluster |
| `default` or `platform` / `falco-slack` (optional) | `webhook-url` | falcosidekick Slack output |

Data planes use the OpenSearch admin credentials (upstream recipe); a dedicated ingest-only user is part of
[#46](https://github.com/koorikla/platform/issues/46).

## Backstage and MCP

- `openchoreo-control-plane` sets `backstage.features.observability.enabled: true`. Backstage gets the observer URL from
  openchoreo-api (the environment's ClusterDataPlane -> `observabilityPlaneRef` -> `observerURL`); nothing else to wire.
  The observer authorizes calls with the user's Thunder JWT (`security.oidc.*` = control plane's issuer/JWKS) and resolves
  UIDs against openchoreo-api with the client-credentials client `openchoreo-observer-resource-reader-client`
  (role binding `observer-resource-reader-binding` ships in the control-plane chart; the Thunder app, upstream script
  59, is in addon `thunder` with the secret from `observer-client-secret`).
- Cost views (#207): the console's Cost Insights (sidebar page, Overview card on projects and components) and the
  project's Cost Analysis tab need the FinOps module (`installation.yaml` `mgmt.addons.finops-opencost: "true"`; the
  tab also needs the FinOps agent, docs/ai-agents.md). Without it the observer has no `finops-adapter` and answers 500
  "Failed to retrieve data from the FinOps adapter". openchoreo-ui 1.3.3 has no flag for them, so the catalog passes the
  mgmt label to `openchoreo-control-plane` `costViews.enabled`, which switches those three Backstage extensions off in
  ConfigMap `backstage-cost-views` (loaded last; reloader restarts Backstage on a change). The observer MCP
  `query_costs` tool still answers 500 without the module.
- MCP servers in 1.3.3 (no new exposure needed; both are behind existing routes, OAuth 2.0 protected-resource metadata
  pointing at Thunder):
  - **openchoreo-api MCP** `http://api.openchoreo.localhost:8080/mcp` — toolsets namespace, project, component,
    deployment, build, pe, resource (`openchoreoApi.config.mcp`, default on).
  - **observer MCP** `http://observer.openchoreo.localhost:11080/mcp` — logs, metrics, traces, alerts queries.
  - Agent-side MCP consumers (RCA/SRE agent, FinOps agent, portal assistant) are off: they need an LLM endpoint and
    their own Thunder clients (upstream scripts 53, 56, 57, 60). Interactive MCP clients (Claude Code, Cursor) need the
    upstream "user MCP" Thunder app (script 56); service clients the "service MCP" app (57).

## Datadog

Enable per installation, environment or cluster by renaming `installations/local/addons/telemetry/values.yaml.disabled`
to `values.yaml` (or `env-<env>.yaml` / `cluster-<name>.yaml`) and putting the API key under key `datadog`, property
`api-key`, in the backend behind ClusterSecretStore `default` (never in git). It sets `datadog.enabled: true` (renders
ExternalSecret `telemetry-datadog`) and adds the `datadog` exporter + `datadog/connector` (APM stats) to the collector's
pipelines; OpenChoreo keeps receiving everything. Optional in the same file: `presets.logsCollection` /
`presets.kubeletMetrics` to send container logs and node/pod metrics to Datadog too.

**Recommendation:** start with the collector's Datadog exporter. It reuses the single pipeline (one place for sampling,
redaction, attributes), needs no extra privileged agent, and covers traces, OTLP/OBI metrics and Falco events. Switch to
(or add) the **Datadog Agent** DaemonSet only when Datadog-native features are required (live processes/containers,
NPM, Universal Service Monitoring, Datadog security products, log autodiscovery annotations); then point the collector
at the Agent's OTLP intake instead of the API, and turn OBI off if USM provides RED metrics.

## OBI

Opt-in (`addons: { obi: true }` in a cluster file -> label `addons.platform.koorikla.io/obi: "true"`). Privileged
DaemonSet (eBPF, hostPID, hostNetwork). Instruments processes in OpenChoreo app namespaces (`dp-*`) only, skips processes
that already export OTLP (SDK-instrumented apps) and the collectors themselves; exports traces (OTLP gRPC
`${HOST_IP}:4317`) and RED metrics (OTLP/HTTP `${HOST_IP}:4318`) to the node-local collector, which adds the
OpenChoreo pod labels so spans show up in Backstage's Traces tab.

Overlap policy: when OBI is enabled it is the **single L7 RED source** — keep Cilium Hubble L7 metrics (`hubble.metrics`
http/dns/kafka with L7 visibility) off and use Istio for mTLS, authorization and traffic management, not telemetry
(no Istio telemetry/Prometheus merging needed). Hubble flow logs (L3/L4, Backstage "wirelogs") stay useful.

## HTTP metrics

**Gateway response codes (promotion gate).** Every data plane's kgateway Envoy (`gateway-default`, namespace
`openchoreo-data-plane`) terminates north-south HTTP, independent of the CNI and of Istio ambient mTLS (it counts responses before ztunnel
encrypts the upstream hop). Addon telemetry
PodMonitor `kgateway-http` (`gatewayMetrics`) scrapes its pods on port `http-monitoring` (:9091) `/metrics` (the path
the pods advertise) and keeps only `envoy_cluster_upstream_rq`: one counter per upstream cluster x response code,
`envoy_cluster_name="kube_<namespace>_<service>_<port>"` (e.g. `kube_dp-default-demo-staging-ba410b48_hello-world_8080`),
`envoy_response_code`, plus the pod labels `openchoreo_dev_plane_id` and `gateway_networking_k8s_io_gateway_name`. Envoy
creates a code's series on its first response with that code, so the count stays at backends x codes seen. The
promotion gate queries these series directly in Prometheus, not through the observer ([promotion.md](promotion.md),
[#104](https://github.com/koorikla/platform/issues/104)). They cover gateway traffic only (external endpoints), not east-west
calls inside the mesh.

**Observer `metric: http`.** The observer's `metric: http` (Backstage HTTP charts) is served by the
observability-metrics-prometheus adapter 0.8.0, which reads only Cilium Hubble series:
`hubble_http_requests_total{reporter="server"}` (`status` 1xx-3xx ok, 4xx/5xx unsuccessful) and
`hubble_http_request_duration_seconds`, joined to kube-state-metrics' `kube_pod_labels` on
`(destination_namespace, destination_pod)`. Three pieces make them exist ([#104](https://github.com/koorikla/platform/issues/104)):

1. addon cilium: L7 visibility policy on the component pods' HTTP port (docs/networking.md; **off**, it broke traffic
   into ambient pods, so today there are no `hubble_http_*` series), and `httpV2`
   `labelsContext` with `source_pod`/`destination_pod` (without them the join matches nothing).
2. addon telemetry: ServiceMonitor `hubble-http` on `kube-system/hubble-metrics`, keeping only `hubble_http_*`.
3. The agent's remote write to the observability plane, as for every other metric.

Limits: data planes on flannel (local prod1) have no Hubble, so no HTTP metrics there. Only plaintext traffic is
parsed, and since the gateway is in the mesh and cells enforce STRICT mTLS
([networking.md](networking.md#strict-mtls-in-cell-namespaces)) there is none into app pods: the source has to move
to a waypoint or OBI, and the adapter reads neither. Enabling OBI with its overlap policy above (Hubble L7 off: cilium `l7Visibility.enabled: false`) empties
the observer's HTTP metrics for the same reason.

## Falco

Falco on every cluster, driver `modern_ebpf` (CO-RE, no kernel module, no driver-loader init container; needs kernel
>= 5.8 with BTF). Rules: upstream default `falco_rules.yaml` (installed by falcoctl) + `platform-rules.yaml`:

| Rule | Scope | Priority |
|---|---|---|
| Platform shell in app container | `dp-*` namespaces | WARNING |
| Platform write below etc | all containers except platform namespaces (list `platform_namespaces`) | ERROR |
| Platform crypto miner indicators (miner binaries, `stratum+tcp/ssl` in cmdline, mining-pool ports) | `dp-*` namespaces | CRITICAL |

Alerts are JSON on Falco's stdout (Fluent Bit ships them to OpenSearch, so they sit next to the app logs) and go to
falcosidekick, which fans out to Talon, the telemetry collector (CloudEvents -> logs pipeline; OTLP alert counters ->
metrics pipeline) and, when enabled, the escalation webhook and Slack. falcosidekick UI is off. On mgmt there is no
Talon and no collector; Falco's stdout and the optional outputs remain.

Why Falco and not Tetragon: Falco is detection-first with a large maintained ruleset, plain-YAML rules, and the
sidekick/Talon ecosystem for routing and response; it does not depend on the CNI. Tetragon's strength is in-kernel
enforcement (TracingPolicies that kill/override syscalls) and it fits a Cilium datapath; it is the later opt-in when
enforcement (not just detection + response) is needed.

**Local caveat:** k3d and CAPD nodes are containers on one host kernel, so every cluster's Falco (eBPF is kernel-wide)
sees every container's syscalls on the machine, including other clusters' pods (without k8s metadata). On real nodes
each Falco sees only its own node. Installation `local` therefore appends `not local_unattributed_container` (a container
without `k8s.ns.name`) to the three rules that fired on foreign containers - "Drop and execute new binary in container"
(Critical, the escalation trigger), "Platform write below etc" and "Contact K8S API Server From Container"
(`installations/local/addons/falco/values.yaml`). Without it, every Critical and Error alert of a dev1 Falco came from
such containers (CAPD nodes' own k3s, mount and CNI processes, other clusters' pods), and each one escalated to mgmt as
a falco-response Workflow that could not act. The cluster's own pods keep full coverage: alerts from namespaced app
pods still arrive ([#49](https://github.com/koorikla/platform/issues/49) has the measurement).

**In-cluster builds:** the build pods in `workflows-<org>` (mgmt workflow plane) run binaries they wrote themselves, which
"Drop and execute new binary in container" reports at Critical - one escalation per build step. Measured on mgmt, the
only Critical alerts from `workflows-*` pods were rootless buildkitd running its binfmt probe
(`$HOME/.local/tmp/qemu-check<n>/check`) and `go test` running its compiled test binary (`/tmp/go-build<n>/b<n>/*.test`);
BuildKit's unshare/mount/setuid activity fires no Critical rule. `platform-rules.yaml` appends one exception list to that
rule with exactly these two tuples (namespace prefix `workflows-`, image repository, parent process, binary path), so any
other dropped binary in a build pod, and the same binary in any other namespace or image, still escalates. The build
image repositories are pinned in `addons/openchoreo-workflow-plane` (`BUILDKIT_IMAGE`) and `addons/openchoreo-platform`
(`checkImage`); a different repository (mirror) is not excepted until the tuple is updated.

## Falco response

**Talon** (workload clusters, `falco-talon` 0.5.0) receives every event from falcosidekick but its rules match only the
platform rule names, which fire only in OpenChoreo app namespaces (`dp-*`), so responses never touch platform workloads.

| Falco rule | Talon actions | Default |
|---|---|---|
| Platform crypto miner indicators | `kubernetes:label` (`platform.koorikla.io/falco=suspicious`) + `kubernetes:terminate` (grace 0, DaemonSets ignored) | enabled |
| Platform shell in app container | `kubernetes:label`; `kubernetes:networkpolicy` isolation commented in the rules | enabled (label only) |

Talon's ServiceAccount is trimmed to pods (get/list/update/patch/delete), pods/eviction, events, networkpolicies, leases.
Dry run per environment: rename `installations/local/addons/falco/env-development.yaml.disabled` to
`env-<env>.yaml` (same rules with `dry_run: true`; it replaces `falco-talon.config.rulesOverride` as a whole).

**Escalation** (on): falcosidekick's webhook output POSTs Critical-and-above events to addon `argo-events` on mgmt,
each cluster to its own endpoint with its own token. Store key `falco-webhook` (`url`, `token`; locally seeded by
`task secrets` with `url=http://events.openchoreo.localhost:8080/falco`) stays on mgmt; every token is derived from it:

| Cluster | Endpoint | Bearer token | Delivered by |
|---|---|---|---|
| workload `<c>` | `<url>/<c>` | `sha256("<c>:<token>")` | charts/cluster: ExternalSecret + ClusterResourceSet `<c>-falco-escalation` -> Secret `falco/falcosidekick-escalation` |
| mgmt | `<url>/<mgmt name>` | `sha256("<mgmt name>:<token>")` | addon falco (role mgmt): ExternalSecret `falcosidekick-escalation`, store `platform` |
| receiver | one EventSource webhook `falco-<c>` per cluster, `authSecret` key `<c>` | the same | addon argo-events: ExternalSecret `falco-webhook` (one key per cluster) |

The cluster list comes from the Argo CD cluster secrets (catalog `fleetParameters`: a `flatList` cluster generator),
so a new fleet file gets its endpoint without any manual step, and deleting it removes the endpoint. A cluster holds
only its own token, which works only on its own endpoint (no preimage: it reveals neither the store token nor another
cluster's); a tenant cannot read it (it is delivered into namespace `falco`, not the tenant store `default`). Rotation:
change the store key's `token` (all tokens rotate; falcosidekick reads its env at start, so restart it on each cluster).
Contract test: `hack/tests/test_falco_tokens.sh` executes the three templates and compares their tokens.

Every event also names its cluster: falcosidekick `customfields: cluster:<name>` (catalog `clusterNameFormats`) adds
`output_fields.cluster`, so the field shows up in OpenSearch, the collector's logs pipeline and Datadog too.

```
workload falcosidekick ── POST http://events.openchoreo.localhost:8080/falco/<cluster> (Bearer <cluster token>) ──►
  k3d serverlb :8080 ─► control-plane Gateway (HTTPRoute falco-escalation, ns argo-events: exactly /falco/<cluster>)
  ─► EventSource platform (webhook falco-<cluster>, authSecret falco-webhook key <cluster>: 401 for any other token)
  ─► EventBus (JetStream, 1 node) ─► Sensor falco-escalation, dependency + trigger per cluster (priority ∈
     Emergency|Alert|Critical, uuid present; rate limit per cluster)
  ─► Workflow falco-<uuid> from WorkflowTemplate falco-response, arguments event + cluster (= the endpoint's cluster)
       enrich: skip unless output_fields.cluster (if set) == cluster; dp-* namespace + pod -> RenderedRelease (control
               plane) -> project, component, environment, workload, Environment -> data plane; skip unless the data
               plane == cluster (a cluster escalates only its own workloads). Read-only RBAC, no data-plane credentials
       record: Kubernetes Event (reason FalcoCritical) on the OpenChoreo Component, note "<rule> cluster=<c> env=..."
       rca:    POST sre-agent /api/v1alpha1/rca-agent/analyze      (only with falco.response.rca.enabled)
       notify: POST <falco-notify.url>                             (only with falco.response.notify.enabled)
```

ServiceAccount tokens follow the promotion gate's executor-only pattern: the WorkflowTemplate sets
`automountServiceAccountToken: false` and `executor.serviceAccountName: falco-response-executor` (may only report step
outputs; its token reaches Argo's init/wait containers, never the step container). Only `enrich` and `record` opt back
in, as ServiceAccount `falco-response` (read RenderedReleases/Environments, create Events in the org namespace).
`rca` and `notify` (template `call`) send the event context to endpoints outside the cluster API and run without any
token.

The Sensor can create Workflows in `argo-events`, so admission pins what it may start: ValidatingAdmissionPolicy
`argo-events-workflows-falco-response-only` (addon argo-events `templates/workflow-admission.yaml`) denies every
Workflow created there unless its spec is exactly `workflowTemplateRef: {name: falco-response}` plus the `event` and
`cluster` parameters. No inline templates, no other (Cluster)WorkflowTemplate, no `serviceAccountName`, `executor`,
`podSpecPatch` or other override, no `valueFrom` parameters, whoever the creator is. Updates keep the spec as created
(only `shutdown`/`suspend` may change: `argo stop`, `terminate`, `suspend`, `resume`); the workflow controller writes
only metadata and status. A VAP rather than Argo Workflows' `templateReferencing: Strict`: that controller setting is
global, and the same controller runs OpenChoreo's rendered Workflows with inline templates.

The `event` text is untrusted: it is the Falco alert, and its output fields (process command lines, file names) are
controlled by whoever runs code in a tenant pod. The pin fixes the shape of the arguments, not their content, so
`{{`/`{{=` inside the value is possible. The WorkflowTemplate passes it only as an environment variable (JSON-escaped,
read by the Python steps as data). Never move `event` (or any field of it) into a step's `source`, `args`, `command`
or another field Argo evaluates as a template or expression.

Name resolution needs no new rule: `events.openchoreo.localhost` matches the existing `*.openchoreo.localhost` rewrite
of `coredns-local` (workload: to the serverlb; mgmt: to the control-plane Gateway Service). Containment stays with Talon
on the data plane (label/terminate; NetworkPolicy isolation commented); the mgmt workflow holds no data-plane write
credentials by design. Footprint and knobs: `addons/argo-events/values.yaml` (requests ~184Mi). Contract:

- `POST <url>/<cluster>` (e.g. `https://events.openchoreo.<domain>/falco/dev1`), `Content-Type: application/json`,
  header `Authorization: Bearer <cluster token>` (the EventSource validates it on that endpoint only).
- Sent only for `priority >= Critical` (`WEBHOOK_MINIMUMPRIORITY=critical`): Critical, Alert, Emergency.
- Transport: locally the route sits on the Gateway's plain-HTTP listener (`falco.route.sectionName: http`, docker
  network on one machine), so the bearer token travels in cleartext there. Every other installation must use an HTTPS
  listener (`falco.route.sectionName`) and an `https://` `url` in `falco-webhook`.
- argo-events renders WorkflowTemplate `falco-response` and Sensor `falco-escalation` only once the Argo Workflows
  CRDs exist (`workflowPlane: auto`, addon openchoreo-workflow-plane); until then escalations reach the EventBus and
  expire there (24h).
- Body = the falcosidekick/Falco event, fields consumers may rely on:

  | Field | Example |
  |---|---|
  | `uuid` | `"4e1a...` (dedupe key) |
  | `time` | `"2026-11-14T10:00:00.123456789Z"` |
  | `priority` | `"Critical"` |
  | `rule` | `"Platform crypto miner indicators"` |
  | `output` | human-readable line |
  | `source` | `"syscall"` |
  | `hostname` | node name |
  | `tags` | `["platform","cryptomining","mitre_impact","T1496"]` |
  | `output_fields` | map: `cluster` (sender's cluster name), `k8s.ns.name`, `k8s.pod.name`, `container.name`, `container.image.repository`, `proc.name`, `proc.cmdline`, `fd.name` |

- Delivery is best effort (sidekick retries are limited); the event also stays in OpenSearch (Falco stdout) and Talon has
  already acted. The receiver must be idempotent on `uuid`. Cluster identity: the endpoint (authenticated);
  `output_fields.cluster` is informational and cross-checked.
- Open hardening of the response workflow: [#12](https://github.com/koorikla/platform/issues/12),
  [#13](https://github.com/koorikla/platform/issues/13).

## Argo CD requirements (catalog)

- `ServerSideApply=true` on `openchoreo-observability-plane` and `telemetry` (prometheus-operator CRDs up to ~860 KB).
- The PVC health override from [openchoreo.md](openchoreo.md) (local-path binds on first consumer: OpenSearch,
  Prometheus, observer alert store).
- ESO on mgmt with generic targets for ConfigMaps (`genericTargets.enabled: true` in addon external-secrets, role mgmt)
  for the agent's `cluster-gateway-ca` ConfigMap.
- Helm hooks: the module setup Jobs run on every sync under Argo (idempotent index/template setup); prometheus-operator
  admission webhooks use cert-manager (no hook Jobs). The logs module's setup Job is no hook upstream (a failed one is
  terminal, the app stays Degraded): the wrapper turns it off and runs the same container as an Argo CD PostSync hook
  (`templates/opensearch-setup-logs.yaml`), recreated on every retry.
- Local installation: OpenSearch's volume is a directory on the host's disk, so its percentage disk watermarks would
  block index creation once the developer's disk is 90 % full; `installations/local/addons/openchoreo-observability-plane`
  sets absolute free-space watermarks (5/3/2 GB).
- OpenSearch's JVM runs with `-XX:ActiveProcessorCount` = its CPU limit (`templates/validate.yaml` enforces it). In k3d
  the JVM finds no cgroup controllers ("System not containerized") and sizes GC threads and thread pools for every host
  CPU; the pools grow lazily until the pod is OOMKilled (~45 min at 1536Mi), dropping the traces in flight.

## Resource budget (requests, local)

| Where | Components | Memory |
|---|---|---|
| mgmt, obs plane | OpenSearch 1 GiB (heap 512 MiB), Prometheus 384 MiB, observer 128, trace receiver 128, controller 96, agent 64, 3 adapters 144, operator 30, Alertmanager 48, + reloader sidecars and the obs Gateway proxy (~150) | **~2.2 GiB** (limits ~5 GiB) |
| per workload node (DaemonSets) | Fluent Bit 64, OTel Collector 64 | **~130 MiB** |
| per workload cluster (singletons) | Prometheus agent 128 (+ reloader), kube-state-metrics 32, operator 30, events collector 48 | **~290 MiB** (≈ 420 MiB total on a single-node cluster) |
| Falco, per node | Falco 192; per cluster sidekick 32 + Talon 32 | ~190 MiB/node + 64 MiB/cluster |
| OBI, per node (opt-in) | 128 MiB | |

Disk: OpenSearch 8 GiB, Prometheus 8 GiB, observer 128 MiB (local-path). OpenSearch needs `vm.max_map_count >= 262144`
on the host kernel (k3d shares it; Arch/systemd default 1048576).

Values inferred but not yet confirmed live: `grep -rn VERIFY addons/openchoreo-observability-plane addons/telemetry
addons/obi addons/falco` (the AI agent routes' TLS, [ai-agents.md](ai-agents.md)); the rest was confirmed live in
[#49](https://github.com/koorikla/platform/issues/49).
