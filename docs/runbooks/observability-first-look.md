# Runbook: Observability first look

## When to use

Use it for the first five minutes when something looks wrong and you do not know where yet: errors, missing telemetry,
or a failing promotion gate. Once you know the failure mode, switch to [incidents.md](incidents.md).

## Symptoms

- An application endpoint returns `5xx` or times out, or Backstage's *RuntimeHealthCard* / *Runtime Logs* / *Metrics* / *Traces* tabs look unhealthy or empty.
- `promotion-gate` blocks a rollout on the `observability` or `smoke` check.
- `prom-agent-openchoreo-prometheus-agent`, `fluent-bit`, or `telemetry-collector-agent` restarts or drops samples on a workload cluster.

## Steps

### 1. First-5-minute triage order (where to look first)

| Order | Surface | Endpoint / entrypoint | What it answers |
|---|---|---|---|
| 1 | Fleet & GitOps | `task status` / `task ui` (`http://localhost:8081`) | Are CAPI clusters `Provisioned`, `ClusterDataPlane`s connected, and Argo CD `Application`s `Synced`/`Healthy`? |
| 2 | OpenChoreo Console & Observer | `http://openchoreo.localhost:8080`, `http://observer.openchoreo.localhost:11080` (+ `/mcp`) | Component rollout status, container logs, CPU/memory/HTTP metrics, distributed traces, and build/gate workflow logs ([observability.md](../observability.md#endpoints-ports-dns-local)) |
| 3 | Logs & k8s Events (`OpenSearch`) | `opensearch.observability.openchoreo.localhost:11085` (indices `container-logs-*`, `k8s-events-*`) | App stdout/stderr, Falco JSON alerts, and enriched Kubernetes Events (`7d` local retention; [observability.md](../observability.md#signals)) |
| 4 | Metrics (`Prometheus`) | `prometheus-openchoreo-observability` in `openchoreo-observability-plane` | Pod resource usage, OTLP metrics, Falco counters, and Prometheus agent ingestion (`7d` local retention) |
| 5 | Traces & L4 flows (`OTel` / `Hubble`) | OpenSearch `otel-traces-*`; `deploy/hubble-relay` on Cilium clusters | Cross-service latency/errors (`OTLP` + opt-in `obi`) and eBPF L3/L4 packet verdicts |

```bash
K="kubectl --context k3d-platform-mgmt"

# 1. Control-plane and observability-plane readiness on mgmt
task status
$K -n openchoreo-observability-plane get pods,pvc
curl -fsS -o /dev/null -w '%{http_code}\n' http://observer.openchoreo.localhost:11080/health || true

# 2. Data-plane shipper readiness on dev1 (Fluent Bit, OTel Collector, events-collector, Prometheus agent)
task kubeconfig CLUSTER=dev1
kubectl --kubeconfig dev1.kubeconfig -n telemetry get pods
kubectl --kubeconfig dev1.kubeconfig top pod -n telemetry --containers
```

### 2. Querying Prometheus, logs, and Hubble directly

When the Backstage UI or `observer` is unavailable, inspect the backing stores directly without printing credentials:

```bash
K="kubectl --context k3d-platform-mgmt"

# Check Prometheus ingestion and active series on mgmt (port-forward locally in a terminal)
$K -n openchoreo-observability-plane exec statefulset/prometheus-openchoreo-observability -c prometheus -- \
  wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=up' | head -c 400; echo

# Check the workload Prometheus agent's active series budget (~10k expected after dropping k3s control-plane histograms)
task kubeconfig CLUSTER=dev1
kubectl --kubeconfig dev1.kubeconfig -n telemetry exec statefulset/prom-agent-openchoreo-prometheus-agent -c prometheus -- \
  wget -qO- 'http://127.0.0.1:9090/metrics' | grep '^prometheus_agent_active_series '

# Inspect recent L3/L4 dropped packets on a Cilium workload cluster
kubectl --kubeconfig dev1.kubeconfig -n kube-system exec ds/cilium -c cilium-agent -- \
  hubble observe --verdict DROPPED --last 20
```

### 3. SLOs and alerts that exist today

Nothing pages a human; the repo has no on-call integration. These checks act on their own:

| Mechanism | Owner | Threshold / trigger | Action taken |
|---|---|---|---|
| Promotion gate observability check | `addons/openchoreo-platform` (`ClusterWorkflow/promotion-gate`) | Over the last `15m` (`observe.windowMinutes`): **0 fired alerts** in `observer` and **HTTP error rate `<= 5%`** (`observe.maxErrorRate: 0.05`; zero traffic is reported, not failed) | Blocks opening the `production` promotion PR ([promotion.md](../promotion.md#3-automated-gate-clusterworkflow-promotion-gate)) |
| Promotion gate smoke check | `addons/openchoreo-platform` | `GET` on every `status.endpoints[].externalURLs` returns `2xx`/`3xx` within 5 retries | Blocks opening the `production` promotion PR |
| Runtime security (`CRITICAL`) | `addons/falco` + `addons/argo-events` | `Platform crypto miner indicators` in `dp-*` namespaces | `falco-talon` labels (`platform.koorikla.io/falco=suspicious`) and terminates the pod (`grace 0`); `falcosidekick` escalates to `argo-events`, recording a `FalcoCritical` Event on the `Component` ([observability.md](../observability.md#falco-response)) |
| Runtime security (`WARNING` / `ERROR`) | `addons/falco` | `Platform shell in app container` (`dp-*`, `WARNING`: Talon label); `Platform write below etc` (`ERROR`) | Shipped to OpenSearch `container-logs-*` and OTel alert counters |
| Supply-chain & Pod Security | `addons/kyverno-policies` | Unsigned/untrusted/tag-only images (`openchoreo-verify-images-*`, `openchoreo-attest-*`, `openchoreo-trusted-registries-*`), Pod Security `baseline` | `PolicyReport` findings in `development`/`staging` (`Audit`); hard admission `Deny` (`failurePolicy: Fail`) on images in `production` |
| Component alert rules | `openchoreo-observability-plane` | `Alertmanager` + `metrics-adapter-prometheus` + OpenSearch alerting -> `observer` | Components opt in with the `observability-alert-rule` trait (allowed on the `service`, `webapp` and `worker` component types); fired alerts fail the promotion gate's observability check |

```bash
# Check Kyverno PolicyReport summaries and FalcoCritical events quickly
kubectl --kubeconfig dev1.kubeconfig get policyreport -A
kubectl --context k3d-platform-mgmt -n default get events --field-selector reason=FalcoCritical
```

## Verify

```bash
# 1. Observability plane pods Ready on mgmt (OpenSearch, Prometheus, Alertmanager, observer, adapters, collector)
kubectl --context k3d-platform-mgmt -n openchoreo-observability-plane get pods

# 2. Telemetry shippers Ready on workload clusters and Prometheus agent well below its 256Mi limit
task kubeconfig CLUSTER=dev1
kubectl --kubeconfig dev1.kubeconfig -n telemetry get pods
kubectl --kubeconfig dev1.kubeconfig top pod -n telemetry
```

## Rollback

All commands in this runbook are read-only. If a telemetry or scrape change (`addons/telemetry` or `addons/openchoreo-observability-plane`) caused high cardinality or OOMs (`hack/tests/test_telemetry_series.sh`), `git revert` the commit on `main` so Argo CD restores the previous relabeling and resource configuration.

## Related links

- [Operations handbook](../operations.md)
- [Observability and runtime security architecture](../observability.md#endpoints-ports-dns-local)
- [Telemetry signals and Prometheus series budget](../observability.md#signals)
- [Falco response pipeline](../observability.md#falco-response)
- [Automated promotion gate](../promotion.md#3-automated-gate-clusterworkflow-promotion-gate)
- [Incidents](incidents.md)
