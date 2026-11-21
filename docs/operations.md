# Day-2 operations

How to run, upgrade, back up and recover the platform after `task up`. Design reasons live in
[architecture.md](architecture.md), naming rules in [conventions.md](conventions.md).

## Rules

- Name the cluster on every command: `--context k3d-platform-mgmt` for mgmt, `--kubeconfig <cluster>.kubeconfig` for a
  workload cluster. Never use the homelab context `koorikla` and never rely on `current-context`.
- Change things through a PR to `main`; Argo CD applies it ([invariants](conventions.md#invariants)). By hand you only
  read, seed local secrets (`task secrets`), or follow a [break-glass](runbooks/break-glass.md) step.
- Never print a secret. Check `ExternalSecret` readiness, key names or byte lengths instead.
- A step marked `(not yet verified live)` matches upstream and the rendered manifests but has not run on a live cluster.

## Cluster access

```bash
task status                     # CAPI clusters, Argo CD apps, ClusterDataPlanes
task demo:check                 # read-only PASS/FAIL table of the live stack
task ui                         # Argo CD UI on http://localhost:8081
task kubeconfig CLUSTER=dev1    # writes dev1.kubeconfig (mode 0600, gitignored)
kubectl --kubeconfig dev1.kubeconfig get nodes
```

## Something is broken

Start with [observability-first-look.md](runbooks/observability-first-look.md) if you do not know where to look.

| Symptom | Go to |
|---|---|
| Argo CD app `OutOfSync`, `Degraded` or `ComparisonError` | [Argo app stuck](runbooks/incidents.md#argo-app-stuck-or-outofsync) |
| `kubectl` times out, `Cluster` or `Machine` not Ready | [Cluster unreachable](runbooks/incidents.md#cluster-unreachable) |
| No production promotion PR, or a `gate-*` run fails | [Promotion gate failing closed](runbooks/incidents.md#promotion-gate-failing-closed) |
| Production rollout denied by a Kyverno image policy | [Kyverno denying an image](runbooks/incidents.md#kyverno-denying-an-image) |
| `FalcoCritical` event, or Talon killed a `dp-*` pod | [Falco critical alert](runbooks/incidents.md#falco-critical-alert) |
| Argo Workflows controller crash-loops, builds stuck | [Workflows controller crash loop](runbooks/incidents.md#workflows-controller-crash-loop) |
| `openbao-0` not Ready, mesh certificates fail | [OpenBao sealed](runbooks/incidents.md#openbao-sealed) |
| `ClusterDataPlane` disconnected, `RenderedRelease` reports `status 502` | [Data plane agent disconnected](runbooks/incidents.md#data-plane-agent-disconnected) |
| You must stop Argo CD reverting a fix, or override a gate | [Break-glass](runbooks/break-glass.md) |

## Planned work

| Task | Runbook |
|---|---|
| Upgrade k3s, CAPI providers, ClusterClasses, addon charts, OpenChoreo, Istio, Kyverno | [upgrades.md](runbooks/upgrades.md) |
| Back up or restore etcd, OpenBao, Thunder, Harbor, CloudNativePG; restore drills | [backup-restore.md](runbooks/backup-restore.md) |
| Inspect or rotate CAs, the OpenBao mesh CA, agent certificates, GitHub App keys, the Cosign key, ESO secrets | [certificates-and-secrets.md](runbooks/certificates-and-secrets.md) |
| Add or remove a cluster, scale workers, 1 vs 3 control-plane servers, local RAM | [scaling-and-capacity.md](runbooks/scaling-and-capacity.md) |

Diagrams: [cluster lifecycle](diagrams/cluster-lifecycle.svg), [trust and certificates](diagrams/trust.svg),
[backup and restore](diagrams/backup.svg), [upgrade flow](diagrams/upgrade.svg) (step-by-step:
[diagrams/](diagrams/README.md)).
