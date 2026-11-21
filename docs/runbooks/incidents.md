# Runbook: Incidents

## When to use

Use it while something is broken. Find the symptom in the table and follow that section's Steps, Verify and
Rollback. If you do not know where to look yet, start with [observability-first-look.md](observability-first-look.md).

## Symptoms

| Symptom | Jump to |
|---|---|
| `Application` stuck `OutOfSync`, `Progressing`, or `ComparisonError` | [Argo app stuck or OutOfSync](#argo-app-stuck-or-outofsync) |
| `kubectl` times out or `Cluster` / `Machine` is not Ready | [Cluster unreachable](#cluster-unreachable) |
| Staging rolled out, but no production promotion PR opens or `gate-*` fails | [Promotion gate failing closed](#promotion-gate-failing-closed) |
| Production `RenderedRelease` fails admission on signature or registry policy | [Kyverno denying an image](#kyverno-denying-an-image) |
| `FalcoCritical` event on a `Component`, or Talon terminated a `dp-*` pod | [Falco critical alert](#falco-critical-alert) |
| `argo-workflow-controller` in `CrashLoopBackOff` or builds stuck in `Init` | [Workflows controller crash loop](#workflows-controller-crash-loop) |
| `openbao-0` `0/1 Ready`, `Issuer/openbao-mesh` False, new mesh pods fail mTLS | [OpenBao sealed](#openbao-sealed) |
| `ClusterDataPlane` disconnected or `RenderedRelease` reports `status 502` | [Data plane agent disconnected](#data-plane-agent-disconnected) |

## Steps

Each failure mode below has its own Steps, Verify and Rollback.

---

## Argo app stuck or OutOfSync

- **Symptoms**: `kubectl --context k3d-platform-mgmt -n argocd get applications` shows an `Application` stuck `OutOfSync`, `Degraded`, `ComparisonError`, or holding a `Running` retry operation.
- **Steps**:
  ```bash
  K="kubectl --context k3d-platform-mgmt"
  $K -n argocd get applications | grep -v 'Synced.*Healthy' || true
  $K -n argocd get application <app> -o yaml | yq '.status.conditions, .status.operationState'

  # 1. Hard-refresh repo-server cache
  $K -n argocd annotate application <app> argocd.argoproj.io/refresh=hard --overwrite

  # 2. Check repository credentials if ComparisonError mentions auth / repository not found
  $K -n argocd get externalsecret platform-repo-creds
  ```
  - **Missing CRDs on fresh boot**: `kyverno-policies-*`, `argo-events-mgmt`, and OpenChoreo apps retry automatically until their engine CRDs finish syncing.
  - **`cluster-<name>` stuck in `OperationState: Running` at wave `-1`**: `ExternalSecret/<name>-registries` is `Ready=False` under `retry.limit: -1`; follow [break-glass.md](break-glass.md#blocked-cluster-sync-on-node-registry-secret).
  - **`spec is immutable` on a PVC**: the PVC was created with `kubectl apply` and migrated to SSA manager `argocd-controller`; recreate with `kubectl create` per [backup-restore.md](backup-restore.md#4-thunder-pvc-recovery-live-verified).
  - **`<project>-<app>-production` waiting during a freeze**: `promotion.freezeWindows` in `installations/<inst>/installation.yaml` blocks gated syncs until the window ends.
- **Verify**: `$K -n argocd get application <app>` reports `Synced` and `Healthy`.
- **Rollback**: `git revert <bad-commit>` on `main` if the latest chart/value change cannot sync cleanly.

---

## Cluster unreachable

- **Symptoms**: `kubectl --context k3d-platform-mgmt` or `kubectl --kubeconfig <cluster>.kubeconfig` fails with connection refused / timeout, or Argo CD cluster health turns `Unknown`.
- **Steps**:
  ```bash
  # 1. Check local mgmt container health and leader-election restarts
  docker ps -a --filter name=k3d-platform-mgmt
  docker inspect k3d-platform-mgmt-server-0 --format 'status={{.State.Status}} restarts={{.RestartCount}}'
  docker logs --tail=80 k3d-platform-mgmt-server-0

  # 2. If mgmt is up, inspect CAPI Cluster, control plane, and CAPD containers
  kubectl --context k3d-platform-mgmt -n fleet get clusters,kthreescontrolplanes,machines
  docker ps -a --filter label=io.x-k8s.kind.cluster=dev1

  # 3. Regenerate kubeconfig (use published 127.0.0.1 LB port on Docker Desktop / macOS / Windows / WSL2)
  KUBECONFIG_MODE=published task kubeconfig CLUSTER=dev1
  kubectl --kubeconfig dev1.kubeconfig get nodes
  ```
  - **Host I/O or swap thrash (`leaderelection lost`)**: check `free -g`; reduce local footprint per [scaling-and-capacity.md](scaling-and-capacity.md).
  - **Single-server CAPD rollout lost `etcd` quorum**: recover the surviving server with `--cluster-reset` ([break-glass.md](break-glass.md#single-server-etcd-quorum-loss)).
  - **Workload cluster recreated under the same name**: kick stalled `RenderedRelease` controllers ([#51](https://github.com/koorikla/platform/issues/51)):
    ```bash
    kubectl --context k3d-platform-mgmt -n default annotate renderedrelease --all \
      platform.koorikla.io/kick="$(date +%s)" --overwrite
    ```
- **Verify**: `kubectl --kubeconfig dev1.kubeconfig get nodes` shows `Ready` and `kubectl --context k3d-platform-mgmt get clusterdataplane dev1` is healthy.
- **Rollback**: if a cluster template or version bump broke new nodes, `git revert` the change on `main` before CAPI rolls remaining replicas.

---

## Promotion gate failing closed

- **Symptoms**: `staging` `ReleaseBinding` rolled out, but no `promote(<component>): ...` PR opens on the app repo, or `WorkflowRun/gate-<component>-*` fails ([promotion.md](../promotion.md#3-automated-gate-clusterworkflow-promotion-gate)).
- **Steps**:
  ```bash
  K="kubectl --context k3d-platform-mgmt"
  # 1. Check the Sensor in argo-events and WorkflowRuns in default
  $K -n argo-events logs -l sensor-name=promotion-gate --tail=50
  $K -n default get releasebindings,workflowruns

  # 2. Read the gate pod logs and per-run ExternalSecret in workflows-default
  $K -n workflows-default get workflows,externalsecrets,pods
  WF=$($K -n workflows-default get workflows --sort-by=.metadata.creationTimestamp -o name | tail -n1)
  $K -n workflows-default logs "$WF" --all-containers
  ```
  Check which of the 6 ordered gate steps failed in the logs:
  1. `pipeline`: missing `staging -> production` edge in `DeploymentPipeline`.
  2. `readiness`: `staging` binding `Ready` timestamp is older than `status.lastSpecUpdateTime` (rollout still progressing or failed).
  3. `smoke`: external endpoint (`status.endpoints[].externalURLs`) did not return HTTP `2xx`/`3xx`.
  4. `observability`: active alert or HTTP error rate > `5%` in the last `15m` from `observer`.
  5. `freeze`: active `promotion.freezeWindows` entry for `production`.
  6. `promote`: `promotion-gate-github` App credentials missing/not installed on the app repo, or `Workload.spec.source.repository` outside `installation.githubOrg`.
- **Verify**: after fixing the cause and cutting or re-running the gate, `WorkflowRun` succeeds and opens/updates branch `promote/<component>-production` with commit status `openchoreo/promotion-gate = success`.
- **Rollback**: if a bad release already merged to `production`, revert the promotion PR in the app repository.

---

## Kyverno denying an image

- **Symptoms**: `production` `RenderedRelease` fails to apply a `Deployment`/`Pod` with an admission error from `openchoreo-verify-images-enforce`, `openchoreo-attest-*-enforce` or `openchoreo-trusted-registries-enforce` ([supply-chain.md](../supply-chain.md#image-signatures-and-attestations-at-admission)).
- **Steps**:
  ```bash
  # 1. Read the admission denial message on mgmt
  kubectl --context k3d-platform-mgmt -n default get renderedreleases
  kubectl --context k3d-platform-mgmt -n default describe renderedrelease <renderedrelease-name>

  # 2. Check Kyverno engine health and Audit PolicyReports on the cluster hosting production (dev1 locally)
  task kubeconfig CLUSTER=dev1
  kubectl --kubeconfig dev1.kubeconfig -n kyverno get pods
  kubectl --kubeconfig dev1.kubeconfig -n kyverno logs deploy/kyverno-admission-controller --tail=80
  kubectl --kubeconfig dev1.kubeconfig get policyreport -A
  ```
  Fix the underlying cause (never weaken `production` to `Audit`):
  - **Tag-only image (`requireDigest`)**: update the app `Workload` image to `<repo>:<tag>@sha256:<digest>` (the app-* workflows output `image_digest_ref`) and cut a new `ComponentRelease`.
  - **Repository or `workflowRef` mismatch**: add `owner/repo` to `imageVerification.github.repositories` in `installations/<inst>/addons/kyverno-policies/values.yaml` or align `workflowRef` with koorikla/platform tag `ci-v1`.
  - **Harbor `apps/` image fails the platform-key check**: with no inline `publicKey`, the key comes from mgmt in ConfigMap `kyverno/platform-image-verification`. Check it exists on the cluster and that `ClusterResourceSet/<cluster>-image-verification` in `fleet` on mgmt is applied ([supply-chain.md](../supply-chain.md#wiring-the-key)).
  - **Webhook timeout (`context deadline exceeded`)**: a check of a digest not yet in Kyverno's verification cache takes ~5-10 s ([supply-chain.md "Admission latency"](../supply-chain.md#admission-latency)); much slower means the cluster's egress to `ghcr.io` / `tuf-repo-cdn.sigstore.dev` is degraded. The rollout retries; successful checks are cached per digest.
  - **Kyverno webhook down (`failurePolicy: Fail`)**: running production pods stay up and platform namespaces are excluded; restore `deploy/kyverno-admission-controller` in `kyverno`.
- **Verify**: `bash hack/tests/test_kyverno_policies.sh` passes offline and `RenderedRelease` transitions to `Ready` on the production data plane.
- **Rollback**: revert `release-bindings/production.yaml` in the app repo to the previous signed `@sha256:...` release.

---

## Falco critical alert

- **Symptoms**: `Component` in `default` emits a `FalcoCritical` Event, `Workflow/falco-<uuid>` runs in `argo-events`, or `falco-talon` labels (`platform.koorikla.io/falco=suspicious`) and terminates a pod in `dp-*` ([observability.md](../observability.md#falco-response)).
- **Steps**:
  ```bash
  K="kubectl --context k3d-platform-mgmt"
  # 1. Inspect the escalated event and Workflow on mgmt
  $K -n default get events --field-selector reason=FalcoCritical
  $K -n argo-events get workflows
  WF=$($K -n argo-events get workflows --sort-by=.metadata.creationTimestamp -o name | tail -n1)
  $K -n argo-events logs "$WF" --all-containers

  # 2. Inspect Falco and Talon logs + suspicious pods on the reporting workload cluster
  task kubeconfig CLUSTER=dev1
  kubectl --kubeconfig dev1.kubeconfig get pods -A -l platform.koorikla.io/falco=suspicious
  kubectl --kubeconfig dev1.kubeconfig -n falco logs ds/falco --tail=100
  kubectl --kubeconfig dev1.kubeconfig -n falco logs deploy/falco-talon --tail=50
  ```
  - **True positive in `dp-*`**: revert the component's `ReleaseBinding` to a clean release (or scale down via Git), preserve OpenSearch `container-logs-*` evidence, and rotate any `SecretReference` keys the workload could read ([certificates-and-secrets.md](certificates-and-secrets.md)).
  - **False positive / local shared-kernel noise**: on `k3d` + CAPD, verify `installations/local/addons/falco/values.yaml` still excludes unattributed foreign-cluster containers (`not local_unattributed_container`); to test rule tuning without pod termination, enable Talon `dry_run: true` via an environment overlay in Git.
- **Verify**: no new `Critical` alerts fire in `ds/falco` logs and the workload runs a verified clean image digest.
- **Rollback**: revert any temporary Talon `dry_run` or rule exception PR once the noisy workload or rule is fixed.

---

## Workflows controller crash loop

- **Symptoms**: `deploy/argo-workflow-controller` in `openchoreo-workflow-plane` on `k3d-platform-mgmt` is in `CrashLoopBackOff`, or workflow pods in `workflows-default` hang indefinitely in `Init`.
- **Steps**:
  ```bash
  K="kubectl --context k3d-platform-mgmt"
  $K -n openchoreo-workflow-plane get pods
  $K -n openchoreo-workflow-plane logs deploy/argo-workflow-controller --previous --tail=100

  # Check active Workflows and the executor token Secret (pods mount it because automountServiceAccountToken=false)
  $K get workflows -A
  $K -n workflows-default get secret workflow-sa.service-account-token
  ```
  - **Malformed `Workflow` spec crash-looping the informer/controller** (for example non-string env vars rendered by a `ClusterWorkflow`): delete the offending `Workflow` (`$K -n workflows-default delete workflow <name>`) to unblock the controller, then fix `addons/openchoreo-platform` or `addons/openchoreo-workflow-plane` in Git.
  - **Pods stuck in `Init`**: ensure `openchoreo-workflow-plane-mgmt` is `Synced` so `Secret/workflow-sa.service-account-token` exists in `workflows-default`.
- **Verify**: `$K -n openchoreo-workflow-plane rollout status deploy/argo-workflow-controller --timeout=120s` succeeds.
- **Rollback**: `git revert` the `ClusterWorkflow` or `openchoreo-workflow-plane` commit that introduced the invalid spec.

---

## OpenBao sealed

- **Symptoms**: `pod/openbao-0` in `openbao` is `0/1 Ready`, `bao status` reports `Sealed: true`, `Issuer/openbao-mesh` on mesh members turns `Ready=False`, and newly started mesh pods or restarted `ztunnel`s fail mTLS. Existing workloads keep working for `>= 12h` (`istiod` `>= 24h`; [multicluster.md](../multicluster.md#when-openbao-is-down)).
- **Steps**:
  ```bash
  K="kubectl --context k3d-platform-mgmt"
  $K -n openbao get pods,pvc,externalsecret,secret
  $K -n openbao exec openbao-0 -- bao status || true
  $K -n openbao logs openbao-0 --tail=80

  # Local static auto-unseal: ensure platform-secrets/openbao-unseal exists, refresh ESO, and restart openbao-0
  task secrets
  $K -n openbao annotate externalsecret openbao-unseal force-sync="$(date +%s)" --overwrite
  $K -n openbao delete pod openbao-0
  $K -n openbao wait --for=condition=Ready pod/openbao-0 --timeout=120s
  ```
  - **Cloud KMS auto-unseal (`awskms` / `transit`, [#31](https://github.com/koorikla/platform/issues/31))** `(not yet verified live)`: check `openbao-0` logs for KMS IAM/Pod Identity or key-policy errors, restore KMS access, and restart `openbao-0`.
  - **Static key lost / corrupted locally** (`decryption failed` on startup): `data-openbao-0` cannot be unsealed without its original key; re-initialize OpenBao via [break-glass.md](break-glass.md#openbao-local-re-initialization).
- **Verify**: `$K -n openbao exec openbao-0 -- bao status` shows `Sealed: false`, `CronJob/mesh-reconcile` succeeds, and `kubectl --kubeconfig dev1.kubeconfig -n istio-system get issuer openbao-mesh` is `Ready=True`.
- **Rollback**: if a seal stanza edit in `addons/openbao` caused the failure, `git revert` it before deleting any PVC.

---

## Data plane agent disconnected

- **Symptoms**: `kubectl --context k3d-platform-mgmt get clusterdataplanes` shows `<cluster>` disconnected/unready, or `RenderedRelease`s fail with `proxy request failed with status 502`.
- **Steps**:
  ```bash
  K="kubectl --context k3d-platform-mgmt"
  # 1. Check control-plane cluster-gateway and Gateway on mgmt
  $K get clusterdataplanes
  $K -n openchoreo-control-plane get pods
  $K -n openchoreo-control-plane logs deploy/cluster-gateway --tail=80

  # 2. Check the agent pod, mTLS secrets, and DNS on the workload cluster
  task kubeconfig CLUSTER=dev1
  kubectl --kubeconfig dev1.kubeconfig -n openchoreo-data-plane get pods,secret,configmap
  kubectl --kubeconfig dev1.kubeconfig -n openchoreo-data-plane logs deploy/cluster-agent-dataplane --tail=80
  ```
  - **Renewed client or gateway CA certificate**: Reloader should have rolled the agent. Check `ClusterResourceSet/dev1-openchoreo-agent` on mgmt (`$K -n fleet get clusterresourceset dev1-openchoreo-agent`) and `kubectl --kubeconfig dev1.kubeconfig -n reloader logs deploy/reloader --tail=20`, then restart the agent by hand ([openchoreo.md](../openchoreo.md#trust-model)):
    ```bash
    kubectl --kubeconfig dev1.kubeconfig -n openchoreo-data-plane rollout restart deploy/cluster-agent-dataplane
    ```
  - **DNS / port `8443` path broken locally**: confirm `coredns-local-dev1` is `Synced` and `k3d-platform-mgmt-serverlb` is on Docker network `kind`.
  - **Cluster recreated under the same name ([#51](https://github.com/koorikla/platform/issues/51))**: once the agent reconnects, kick `RenderedRelease`s ([openchoreo.md](../openchoreo.md#known-issue-re-created-data-plane-clusters)):
    ```bash
    $K -n default annotate renderedrelease --all platform.koorikla.io/kick="$(date +%s)" --overwrite
    ```
  - **New cluster, agent pod never created**: the `capability-gate` Sync hook waits for the CRDs of the cluster's opt-in addons (KEDA; the PostgreSQL XRD from crossplane's Configuration package) before the agent starts; the pending init container `wait-for-<addon>-crds` names the addon; fix it (`keda-<cluster>` / `crossplane-<cluster>` app, `kubectl get configuration.pkg` for a failed package pull), then check `kubectl --kubeconfig dev1.kubeconfig -n openchoreo-data-plane logs job/capability-gate --all-containers`.
- **Verify**: `$K get clusterdataplane dev1` is connected and `$K -n default get renderedreleases` shows `Ready`.
- **Rollback**: if an `openchoreo.controlPlane.clusterGatewayURL` or gateway route edit broke connectivity, `git revert` the commit on `main`.

---

## Verify

```bash
task status
kubectl --context k3d-platform-mgmt -n argocd get applications | grep -v 'Synced.*Healthy' || true
```

## Rollback

If an incident mitigation required freezing Argo CD or applying a temporary Git override, reconcile all temporary changes back to `main`, restore Argo CD controllers (`task argocd`), and confirm zero out-of-band drift ([break-glass.md](break-glass.md)).

## Related links

- [Operations handbook](../operations.md)
- [Observability first look](observability-first-look.md)
- [Promotion gates](../promotion.md#3-automated-gate-clusterworkflow-promotion-gate)
- [Supply-chain admission](../supply-chain.md#image-signatures-and-attestations-at-admission)
- [Falco detection and response](../observability.md#falco-response)
- [When OpenBao is down](../multicluster.md#when-openbao-is-down)
- [OpenChoreo trust model](../openchoreo.md#trust-model)
- [Certificates and secrets](certificates-and-secrets.md)
- [Backup and restore](backup-restore.md)
- [Break-glass](break-glass.md)
