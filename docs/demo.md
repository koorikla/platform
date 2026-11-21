# Full platform demo

The scripted demo of the whole platform on the local stack (k3d mgmt + CAPD `dev1`, the lean profile of docs/dev-environment.md "Local profiles"): about 30 minutes, for
the team and for management. It follows the storyline of the tracking issue
[#98](https://github.com/koorikla/platform/issues/98). Every step lists what to show, the commands and URLs, the expected
output, talking points, and a fallback. A step whose feature is not on `main` yet is marked **pending #NN**.

## Before the demo

Run `task demo:check` 15 minutes before and again just before you start. It is read-only and prints one row per check:

```bash
task demo:check            # or: bash hack/demo-check.sh
```

```text
STEP CHECK                                          RESULT       DETAIL
---- ---------------------------------------------- ------------ ------
1    Argo CD apps Synced/Healthy                    PASS         44/44 Synced/Healthy
2    CAPI clusters Provisioned                      PASS         dev1 Provisioned/Available
...
4    in-cluster build succeeded                     PASS         latest build <run> (<time>): succeeded
...
5    promotion-gate WorkflowRuns present            FAIL         no promotion-gate WorkflowRun in default (runs expire 1h after completion; promote to start one)
...
9    PostgreSQL claim API                           PASS         XRD postgresqls.platform.koorikla.io Established on: dev1
9    hello-world database claim Ready               PASS         development: PostgreSQL <xr> Ready on dev1, hello-world reads Secret <xr>-app (binding <rrb>)

<n> PASS, 1 FAIL, <n> PENDING
```

The shape of the output (placeholders in `<>`); counts depend on the stack and the time of day.

| Result | Meaning | Before the demo |
|---|---|---|
| PASS | the step works on the live stack | show it live |
| FAIL | it should work and does not (exit code 1) | fix it, or use the step's fallback |
| PENDING #NN | the feature is not merged yet (issue NN) | tell the story with the fallback; do not improvise it live |
| PENDING | expected on this stack right now, the detail says why (e.g. production frozen by sync window ... until ...) | show the reason; promote after the window |

What it checks, per step: Argo CD apps, CAPI clusters, OpenChoreo data-plane agents, the cluster file rendered for the
other providers (offline `helm template`), the Backstage console, component types, the latest image's signature
(`cosign verify` with the identity pinned in `addons/kyverno-policies/values.yaml`), Kyverno policies Ready, a signed
image admitted and an unsigned one denied in the production cell namespace (`kubectl apply --dry-run=server`, nothing
is stored), in-cluster builds, hello-world HTTP 200 per environment through the CAPD node IP, promotion-gate
WorkflowRuns, metrics per cluster and per app in the observability plane, Falco on every cluster and the escalation
path, OpenBao-issued mesh certificates, ClusterSecretStores, the PostgreSQL claim API and hello-world's database claim (its `postgresql` Resource bound and
Ready in the first environment, the XR Ready in the cell namespace, the Deployment reading `<xr>-app`; PENDING while
the app declares none).

How it works and what it never does:
- Reads only: `kubectl get`, `kubectl get --raw` (Prometheus through the API server's service proxy), server-side
  dry-runs, curl GETs, `cosign verify`. Workload-cluster kubeconfigs come from `hack/kubeconfig.sh` into a temp dir that
  is removed on exit; no secret value is printed. Context `koorikla` is refused.
- Known-unmerged features: a failing check listed in `pending_issue()` of `hack/demo-check.sh` shows PENDING #NN instead
  of FAIL; delete the line when the issue closes. `DEMO_STRICT=1 task demo:check` shows them as FAIL.
- Freeze windows: an Argo CD app OutOfSync only because an active deny sync window of its AppProject covers it is
  PENDING with the window and its end (`hack/lib/syncwindow.py`; `DEMO_NOW=<ISO 8601>` evaluates another time).
- Variables: `KUBE_CTX`, `DEMO_NAMESPACE` (org namespace, `default`), `DEMO_COMPONENT` (`hello-world`),
  `DEMO_UNSIGNED_IMAGE`, `DEMO_HTTP_MODE=direct|docker` (default `docker` on macOS / Windows / WSL, where container IPs
  are not routable from the host: docs/dev-environment.md "Host differences (Docker Desktop and friends)").
- Tests: `hack/tests/test_demo_check.sh` (stubbed kubectl, curl, cosign, helm; part of `task test`).

### After a clean bootstrap

`task down && task up` deletes Harbor and every ComponentRelease, while the app repo still pins what the previous stack
built: the Workload's image digest and, in `release-bindings/{staging,production}.yaml`, the release names the previous
stack's OpenChoreo cut. What happens per environment ([#200](https://github.com/koorikla/platform/issues/200)):

| Environment | After the bootstrap | Manual steps |
|---|---|---|
| development | Auto-build finds the pinned digest missing in Harbor and rebuilds the Workload's commit (WorkflowRun `hello-world-<sha[:12]>-<digest[:8]>`, docs/build-plane.md "Auto-build" step 5); the hand-off commits the new digest, `autoDeploy` rolls it out. Serves about 10 minutes after the workflow plane is up, usually before `task up` reports every app Healthy. | none |
| development, the app secret | OpenBao starts empty. CronJob `openbao-tenants/demo-demo-secrets` (every 5 minutes, `demoSecrets` in `installations/local/tenants/demo.yaml`) writes `kv-tenant-demo/hello-world` property `greeting` as `demo-writer` once the tenant mount exists: a generated `demo-only-<hex>` value, never in git, never overwritten. The ExternalSecret picks it up on its next retry (ESO backs off after failures, up to ~17 minutes; `kubectl annotate externalsecret <name> force-sync=$(date +%s)` in the cell namespace skips the wait) and the pod starts. | none |
| staging, production | The pinned release does not exist in this stack (binding `ComponentReleaseNotFound`). `task demo:check` shows them PENDING `not promoted in this stack yet`. | one promotion, the demo's step 5 |
| production, in a freeze | Between Fri 16:00 and Mon 08:00 Europe/Tallinn the weekend freeze (docs/promotion.md "Freeze window") denies syncs of `demo-hello-world-production`: OutOfSync/Missing, no production ReleaseBinding. `task demo:check` shows step 1 and the production checks of step 5 (HTTP 200, promotion-gate runs, PDB/spread/priority) PENDING `frozen by sync window "freeze weekend: ..." until <end>`; any other OutOfSync app still FAILs. | none; production syncs when the window ends |

Staging and production come back only through a promotion, on purpose: a release reaches them after its rollout,
smoke test and 5xx rate were checked in the environment before (docs/promotion.md "The gates"), and that evidence
belongs to the stack it was gathered in. Re-pinning production automatically would bypass the gate and the release
manager's merge. Promote development's release to staging (in a koorikla/hello-world checkout):

```bash
REL=$(kubectl --context k3d-platform-mgmt -n default get releasebinding hello-world-development -o jsonpath='{.spec.releaseName}')
git switch -c "promote-staging-$REL"
yq -i ".spec.releaseName = \"$REL\"" deploy/openchoreo/release-bindings/staging.yaml
git commit -am "promote(hello-world): $REL to staging" && gh pr create --fill && gh pr merge --squash
```

Once staging has rolled out, the promotion gate opens PR `promote/hello-world-production`; merge it outside the freeze
window and production serves. Do this before the demo when step 5 should start from three serving environments; it
also gives the "promotion-gate WorkflowRuns present" row its run (runs expire 1 h after completion).

Also prepare:
- Browser tabs: Argo CD (`task ui`, http://localhost:8081), the OpenChoreo console http://openchoreo.localhost:8080
  (user `admin@openchoreo.dev`, password: docs/forking.md "4. Boot"), Harbor https://harbor.openchoreo.localhost:9443, the
  promotion pull requests of koorikla/hello-world.
- Terminal with the workload cluster's kubeconfig: `task kubeconfig CLUSTER=dev1` (file `dev1.kubeconfig`, gitignored;
  in the multicluster profile also `CLUSTER=prod1`).
- Font size up, notifications off. Close the terminal that shows `task secrets` output.

## Timeline

| # | Step | Minutes | Status |
|---|---|---|---|
| 1 | Clean bootstrap | 3 | live |
| 2 | Add a cluster by adding a file | 4 | live; AWS, Hetzner and GKE are untested, render-only examples; EKS, AKS and Talos are not planned (#88-#90) |
| 3 | Developer self-service | 3 | console and the six golden-path templates live; running one needs a GitHub org (#109) |
| 4 | Build and supply chain | 5 | live: in-cluster build, signature, live deny |
| 5 | Deploy and promote | 5 | live, production through the promotion gate; the weekend freeze holds production PENDING |
| 6 | Observe | 3 | logs/metrics/traces live; alert-rule trait `observability-alert-rule` allowed on the component types |
| 7 | Runtime security | 3 | live |
| 8 | Zero trust | 2 | live (OpenBao mesh CA on mgmt, istio-csr on dev1); app secrets from each project's own OpenBao mount |
| 9 | App with a database | 2 | live on dev1 (CloudNativePG); RDS / Cloud SQL / Flexible Server render-only (#107) |
| 10 | PR preview environment | 4 | live; the build takes ~6 min, so open the PR before the demo |

## 1. Clean bootstrap

Show: one command builds the platform from zero; Argo CD converges mgmt and the fleet.

```bash
task up            # recorded beforehand: ~15 min with warm registry caches (first boot 20-30 min); show the recording or the end of the log
task status        # CAPI clusters, Argo CD apps, ClusterDataPlanes
```

Expected: `task status` lists `dev1` `Provisioned`, every Application `Synced Healthy`, ClusterDataPlane `dev1` (hosting
development, staging and production, one namespace each). Argo CD UI: the `root` app fanning out to mgmt addons, the `fleet`
ApplicationSet and per-cluster addons.

Talking points:
- Push GitOps: Git is the source of truth; nobody runs `kubectl apply` for platform resources (AGENTS.md).
- Same toolchain on Linux, macOS, Windows (mise + Task); a fork runs from its own repo (`task set-repo`).
- Two clean runs from zero, no hand-fixes.

Fallback: do not run `task up` live (too long). Show `task status` and Argo CD on the running stack.

## 2. Add a cluster by adding a file

Show: a cluster is one YAML file. Open `installations/local/clusters/dev1.yaml` next to `prod1.yaml.disabled` (the
multicluster profile: renaming it to `prod1.yaml` and moving `production` to it creates prod1).

```bash
kubectl --context k3d-platform-mgmt get clusters -n fleet
kubectl --context k3d-platform-mgmt get clusterdataplanes
kubectl --context k3d-platform-mgmt get applications -n argocd | grep dev1
helm template cluster-prod-euc1 charts/cluster --namespace fleet \
  --values installations/aws-example/installation.yaml --values installations/aws-example/clusters/prod-euc1.yaml \
  | grep -E '^kind:|classRef' -A1 | head -20
```

Expected: `dev1` `Provisioned`, `AVAILABLE True`; its ClusterDataPlane exists (the check shows `1 agent connected`);
per-cluster addon apps (`cilium-dev1`, `falco-dev1`, ...); the AWS file renders a CAPI `Cluster`
with class `k3s-aws`.

Talking points:
- File -> `fleet` ApplicationSet -> CAPI Cluster -> Argo CD cluster secret -> addons by label -> OpenChoreo data plane
  (docs/providers.md "Adding a cluster").
- CNI is fixed at birth: `dev1` runs Cilium, `prod1` (multicluster profile) flannel; the label picks the addon set
  (docs/networking.md "CNI is fixed when the cluster is created").
- The same contract renders for AWS (CAPA), Hetzner (CAPH) and GKE (CAPG) as untested examples; EKS, AKS and
  Talos/vSphere are not planned (#88, #89, #90: no cloud accounts in this lab).

Fallback: if a cluster is still provisioning, show the file, `kubectl get clusters -n fleet` and the rendered output.
Never create or delete a cluster live (a new CAPD cluster needs ~10 min and RAM the laptop may not have).

## 3. Developer self-service

Show: a developer creates a component in the console without touching Kubernetes.

- Console: http://openchoreo.localhost:8080 -> project `demo` -> component `hello-world`: Overview, Deploy tab
  (environments development / staging / production), Runtime Logs.
- Create: Create -> pick a component type (`service`, `web-application`, `worker`, `scheduled-task`).
- Logged in as `developer@openchoreo.dev` (groups `developers` + `demo-developers`): write access in project `demo`
  only, production bindings excluded ([developer access](openchoreo.md#developer-access-is-per-project)).

```bash
kubectl --context k3d-platform-mgmt get clustercomponenttypes
kubectl --context k3d-platform-mgmt get components,releasebindings -n default
```

Expected: the four component types; component `hello-world` with release bindings for the three environments.

Talking points:
- Developers get golden paths (component types, traits) and a portal; the platform team owns the templates.
- The app repo contract is small: docs/openchoreo.md "App repo contract".

- Create also lists the golden-path templates of this repo (Go, Python, Docker, Quarkus, Fastify, Rust;
  docs/project-templates.md). Show the form, do not run it: creating the repo needs a GitHub org (#109).

Fallback: show the existing `hello-world` component and its repo (koorikla/hello-world, `deploy/openchoreo/`).

## 4. Build and supply chain

Show: hello-world is built in-cluster (OpenChoreo workflow plane -> Harbor, signed with the platform key); only signed
images with an SBOM and a vulnerability scan run in production; an unsigned one is denied live.

The build starts by itself: merge any code or docs change to hello-world `main` (it sets `autoBuild: true`) and within
about a minute the auto-build poll (local installation: nothing is exposed to GitHub; docs/build-plane.md "Auto-build")
creates WorkflowRun `hello-world-<sha[:12]>`. Follow it: checkout, check, scan-fs, build (rootless BuildKit,
linux/amd64 + linux/arm64), scan-image, sbom, sign, gitops (commits the digest ref into
`deploy/openchoreo/workload.yaml`; Argo CD + autoDeploy roll it out to development). About 6 minutes.

```bash
kubectl --context k3d-platform-mgmt get workflowruns -n default -l platform.koorikla.io/trigger=auto-build -w
kubectl --context k3d-platform-mgmt -n workflows-default get workflows -l workflows.argoproj.io/cron-workflow=auto-build-poll
```

The hand-off commit and promotion merges start no build (they only touch `deploy/`), and a pass without a new commit
creates nothing. On demand instead: Backstage -> hello-world -> **Build**, or the WorkflowRun below.

```bash
kubectl --context k3d-platform-mgmt create -f - <<'EOF'
apiVersion: openchoreo.dev/v1alpha1
kind: WorkflowRun
metadata:
  generateName: hello-world-build-
  namespace: default
  labels: { openchoreo.dev/component: hello-world, openchoreo.dev/project: demo }
spec:
  workflow:
    kind: ClusterWorkflow
    name: go
    parameters:
      repository: { url: https://github.com/koorikla/hello-world.git, revision: { branch: main }, appPath: "." }
EOF
kubectl --context k3d-platform-mgmt get workflowruns -n default -w
```

A manual run of a head commit that only touches `deploy/` ends after checkout (the hand-off's own commit, loop guard).

Verify the image the Workload deploys (platform key, Harbor CA, pull-only robot; `task demo:check` row "latest image
signed" does the same):

```bash
IMAGE=$(kubectl --context k3d-platform-mgmt get workloads -n default hello-world-workload -o jsonpath='{.spec.container.image}')
kubectl --context k3d-platform-mgmt -n platform-secrets get secret cosign-platform -o jsonpath='{.data.cosign\.pub}' | base64 -d > cosign.pub
kubectl --context k3d-platform-mgmt -n harbor get secret harbor-ca-bundle -o jsonpath='{.data.ca\.crt}' | base64 -d > harbor-ca.crt
cosign verify --key cosign.pub --insecure-ignore-tlog=true --registry-cacert harbor-ca.crt "$IMAGE" >/dev/null
cosign tree --registry-cacert harbor-ca.crt "$IMAGE"
```

Harbor's `apps` project is private: `docker login harbor.openchoreo.localhost:9443` first (robot `robot$nodes`, secret
`nodes-secret` of `platform-secrets/harbor`). Expected: `The signatures were verified against the specified public key`;
the tree lists the signature, `https://spdx.dev/Document/v2.3` and `https://cosign.sigstore.dev/attestation/vuln/v1`.

The live admission, in the production cell namespace on `dev1` (production is where signatures are enforced; development
and staging, on the same cluster, only report: the policies select namespaces by their environment label):

```bash
NS=$(kubectl --kubeconfig dev1.kubeconfig get ns -l openchoreo.dev/environment=production,openchoreo.dev/managed-by=renderedrelease-controller -o name | head -1 | cut -d/ -f2)
kubectl --kubeconfig dev1.kubeconfig get imagevalidatingpolicies,validatingpolicies
kubectl --kubeconfig dev1.kubeconfig -n "$NS" run signed --image="$IMAGE" --dry-run=server
kubectl --kubeconfig dev1.kubeconfig -n "$NS" run unsigned \
  --image=ghcr.io/koorikla/hello-world@sha256:5760e176af0ec30cb8b06c80e99b3ab1746243c6c2d54997847ff850e8e38ad7 --dry-run=server
kubectl --kubeconfig dev1.kubeconfig -n "$NS" run untrusted --image=docker.io/library/busybox:1.37.0 --dry-run=server
```

Expected: policies `READY true`; `pod/signed created (server dry run)` (Kyverno on dev1 reads the platform key, the
Harbor CA and a pull-only robot that mgmt delivered: docs/supply-chain.md "Wiring the key"); the unsigned digest is
denied by an `openchoreo-verify-images-enforce` / `openchoreo-attest-*-enforce` check (`... no signatures found`); the
docker.io image is denied by `openchoreo-trusted-registries-enforce`. An image pushed to Harbor `apps/` outside the
pipeline is denied the same way (`image (harbor.openchoreo.localhost:9443/apps/) is not signed by platform-key`).

Talking points:
- One pipeline for every stack, CI-provider-agnostic: the workflow plane runs the same ci/scripts as the
  GitHub path; Git stays the source of truth (the build commits the digest ref, Argo CD deploys it).
- Push-to-deploy without inbound traffic: locally a poll (GitHub App token, read-only, one build per commit), in cloud
  installations a signed GitHub webhook into the same trigger.
- Kyverno checks signature + SBOM + vuln attestations and a digest reference at admission; the GitHub path
  (keyless, SLSA provenance too) stays available to any app repo (app-<stack>.yaml, used by the templates/ golden paths).
- The signing key never leaves mgmt; workload clusters get only `cosign.pub`.

Fallback: if the build is slow, show the last run's tasks (`kubectl get workflowrun -n default <name> -o yaml`,
`status.tasks`) and the verification above. If the live deny returns a webhook timeout, Kyverno is still starting: show
the `READY` column and retry after a minute; `task demo:check` row "unsigned image denied" is the proof from the
pre-flight.

## 5. Deploy and promote

Show: development -> staging -> production, with gates in front of production.

```bash
NODE_DEV=$(kubectl --context k3d-platform-mgmt get machines -n fleet -l cluster.x-k8s.io/cluster-name=dev1 -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
for env in development staging production; do
  curl -s --resolve "$env-default.dev1.apps.localhost:19080:$NODE_DEV" "http://$env-default.dev1.apps.localhost:19080/hello-world-http/"; echo
done
kubectl --context k3d-platform-mgmt get releasebindings,workflowruns -n default
```

On macOS / Windows run curl inside the CAPD network instead (docs/dev-environment.md "Host differences (Docker Desktop and friends)"). Expected: the
hello-world response from development and staging; WorkflowRuns `gate-hello-world-<id>` of ClusterWorkflow
`promotion-gate`; in Argo CD the AppProject `tenant-demo` sync window and the two apps `demo-hello-world` and
`demo-hello-world-production`.

Talking points:
- Promotion is a pull request; production bindings are reachable only through Git (ABAC + a ValidatingAdmissionPolicy
  deny everything else, docs/promotion.md "The gates").
- The automated gate checks pipeline order, readiness, a smoke test, the observer and the freeze window, then opens
  the production PR with a commit status; a human release manager merges it.

Fallback: production serving hello-world needs a passing gate run that promotes a digest release; in a freeze window it stays PENDING until the window ends. Show the gate WorkflowRun in the console (Workflows ->
promotion-gate), its PR if one exists, and the production ReleaseBinding condition (denied tag-only image) as proof
that production refuses what is not verified.

## 6. Observe

Show: logs, metrics and traces of hello-world in the console, collected from both workload clusters.

- Console -> `hello-world` -> Runtime Logs, Metrics, Traces (environment development).
- Raw proof (the pre-flight queries the same):

```bash
kubectl --context k3d-platform-mgmt get --raw \
  '/api/v1/namespaces/openchoreo-observability-plane/services/prometheus-operated:9090/proxy/api/v1/query?query=count%20by%20(k8s_cluster_name)(%7Bk8s_cluster_name!%3D%22%22%7D)'
```

Expected: series for `dev1` (and `prod1` in the multicluster profile); hello-world pods in the Metrics view.

Talking points:
- One observability plane on mgmt; data planes ship logs (Fluent Bit), metrics (Prometheus agent, remote write) and
  traces (OTel collector) with the cluster name (docs/observability.md "Signals").
- The same views back the RCA agent and MCP clients.

Alert rules: trait `observability-alert-rule` on a component (docs/observability.md). If the console views are empty, the
observer may still be indexing after a restart: show the Prometheus query above and the Runtime Logs of the last hour.

## 7. Runtime security

Show: Falco detects a shell in an app container; falcosidekick routes it, Talon labels the pod, Critical events
escalate to the falco-response workflow on mgmt.

```bash
POD=$(kubectl --kubeconfig dev1.kubeconfig get pods -A -l openchoreo.dev/component=hello-world -o jsonpath='{.items[0].metadata.namespace}/{.items[0].metadata.name}')
kubectl --kubeconfig dev1.kubeconfig exec -n "${POD%/*}" "${POD#*/}" -- sh -c 'id' || true
kubectl --kubeconfig dev1.kubeconfig logs -n falco ds/falco -c falco --since=2m | grep 'Platform shell'
kubectl --kubeconfig dev1.kubeconfig get pod -n "${POD%/*}" "${POD#*/}" --show-labels
kubectl --context k3d-platform-mgmt get sensors,workflows -n argo-events
```

Expected: a `Platform shell in app container` alert naming the pod; a `platform.koorikla.io/falco` label set on the
pod by Talon; Sensor `falco-escalation` deployed on mgmt. If the image has no
shell, the exec fails and Falco still reports the attempt (process spawn).

Talking points:
- Detection on every cluster (eBPF, no kernel module), response on the cluster (Talon), escalation to mgmt where the
  workflow enriches the event with project, component and environment (docs/observability.md "Falco response").
- Responses only ever touch app namespaces (`dp-*`), never platform workloads.

Every event carries `cluster:<name>` (falcosidekick custom field) and each cluster posts to its own escalation
endpoint with its own token, so one cluster cannot raise events in another's name.

Fallback: if no alert shows within a minute, show `task demo:check` rows of step 7 and the falco-response WorkflowTemplate.
Locally all clusters share one kernel (docs/observability.md "Falco"), so expect duplicate detections from other
clusters' Falcos.

## 8. Zero trust

Show: mTLS between workloads with certificates from OpenBao on mgmt (CA keys never leave mgmt), and secrets only
through External Secrets.

```bash
kubectl --kubeconfig dev1.kubeconfig get issuers,certificates -n istio-system
kubectl --kubeconfig dev1.kubeconfig get ns -L istio.io/dataplane-mode | grep dp-
kubectl --context k3d-platform-mgmt get clustersecretstores
kubectl --kubeconfig dev1.kubeconfig get clustersecretstores
# app secret: hello-world GREETING_SECRET from the project's own OpenBao mount (SecretReference in the app repo)
NS=$(kubectl --kubeconfig dev1.kubeconfig get ns -l openchoreo.dev/project=demo,openchoreo.dev/environment=development -o name | cut -d/ -f2)
kubectl --kubeconfig dev1.kubeconfig -n "$NS" get secretstore,externalsecret
```

Expected: Issuer `openbao-mesh` (Vault issuer) `READY True` and Certificate `istiod` `READY True` on each mesh member;
app namespaces in ambient mode; ClusterSecretStores `Ready True` on mgmt (`platform`, `mgmt-*`) and `default` on the
workload clusters; in the development cell namespace `SecretStore openbao-tenant` and the hello-world ExternalSecret
`READY True` (store `openbao-tenant`, refresh 15s).

Talking points:
- Istio ambient: ztunnel gives every app pod mTLS without sidecars; istio-csr on each member asks OpenBao on mgmt to
  sign, scoped to that cluster's PKI role with 10-minute tokens.
- No secret is in Git: hello-world's repo holds a `SecretReference` (a pointer), the value was written to
  `kv-tenant-demo` with the project's writer identity (locally a generated demo-only value, seeded on every bootstrap), and each cell namespace can read only its own project's mount
  (docs/openchoreo.md "Application secrets").

Fallback: if `task demo:check` does not show "OpenBao-issued mesh certificates" as PASS (e.g. right after a restart
of OpenBao or istiod), show ambient enrollment, the ClusterSecretStores and the design in docs/architecture.md; do not
debug the CA live. If row "hello-world reads GREETING_SECRET from OpenBao" fails, the demo value was not written yet: the seed CronJob
writes it within 5 minutes of the tenant mount existing (check `kubectl --context k3d-platform-mgmt -n openbao-tenants
logs job/<latest demo-demo-secrets-*>`: `seeded=[hello-world/greeting]` or `kept=[...]`). Not waiting: `kubectl
--context k3d-platform-mgmt -n openbao-tenants create job --from=cronjob/demo-demo-secrets demo-seed-now` (same
identity, same idempotent script; docs/multicluster.md "Tenant secrets (OpenBao)", "Demo values").

## 9. App with a database

Show: a developer claims a PostgreSQL database; locally CloudNativePG runs it, on AWS the same claim becomes RDS.

dev1 opts in to the addons in its cluster file (`addons: { cloudnative-pg: true, crossplane: true }`). A `PostgreSQL`
XR with an empty spec becomes a CloudNativePG cluster and a connection Secret `<name>-app`:

```bash
kubectl --kubeconfig dev1.kubeconfig create namespace pg-demo
kubectl --kubeconfig dev1.kubeconfig -n pg-demo apply -f - <<'YAML'
apiVersion: platform.koorikla.io/v1alpha1
kind: PostgreSQL
metadata: { name: orders-db }
spec: {}
YAML
kubectl --kubeconfig dev1.kubeconfig -n pg-demo get postgresql orders-db -w   # READY True after ~1.5 min
```

Expected: `BACKEND cnpg`, `SECRET orders-db-app`, `COMPOSITION postgresql`. A raw CNPG `Cluster` from a tenant
is denied by the `postgresql-only-through-the-platform-api` policy (also a native ValidatingAdmissionPolicy).

Through OpenChoreo (what developers actually do): the app repo declares a `Resource` of `ClusterResourceType
postgresql`, a `ResourceReleaseBinding` per environment (annotated `platform.koorikla.io/resource-release: latest`:
the auto-build pass pins the release, no hash in Git, docs/promotion.md "Resources") and a Workload dependency with
`envBindings` (docs/data-services.md "PostgreSQL from OpenChoreo"). Every PR preview of hello-world gets its own empty
`orders-db` (`orders-db-pr-<n>-hello-world`, deleted with the preview, docs/preview-environments.md). The cluster agent applies the XR into the cell namespace (its RBAC
grants exactly `platform.koorikla.io` `postgresqls`, addon openchoreo-data-plane) and the app gets `host`/`port`/
`database` as values and `username`/`password`/`uri` as `secretKeyRef`s to `<xr>-app`, which never leaves dev1:

```bash
kubectl --context k3d-platform-mgmt get resourcereleasebindings -n default        # READY True, RELEASE orders-db-<hash>
kubectl --kubeconfig dev1.kubeconfig get postgresqls -A                          # in the dp-default-demo-development-* cell
```

`task demo:check` row "hello-world database claim Ready" proves the whole chain (hello-world declares it in
`deploy/openchoreo/orders-db.yaml`).

Talking points: the same XR becomes RDS / Aurora, Cloud SQL or Azure Flexible Server on those providers (rendered and
tested offline, live accounts pending #107); production XRs must set HA and backups.

Fallback: show docs/data-services.md "PostgreSQL as a service". Clean up with `kubectl delete namespace pg-demo`.

## 10. PR preview environment

Show: a pull request gets its own environment with its own URL, and loses it when the PR closes.

hello-world opts in with the Component annotation `platform.koorikla.io/preview-environments: enabled`. Open a PR that
changes the code (the build takes ~6 minutes, so do this before the demo), e.g. the greeting in `main.go`:

```bash
gh pr create -R koorikla/hello-world --head <branch> --fill     # or in the GitHub UI
kubectl --context k3d-platform-mgmt -n argocd get applications -l platform.koorikla.io/preview=true
kubectl --context k3d-platform-mgmt -n default get environment,releasebinding -l platform.koorikla.io/preview=true -L platform.koorikla.io/expires-at
gh pr checks <n> -R koorikla/hello-world                          # openchoreo/preview: the URL
NODE_DEV=$(kubectl --context k3d-platform-mgmt get machines -n fleet -l cluster.x-k8s.io/cluster-name=dev1 -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
H=pr-<n>-hello-world-default.dev1.apps.localhost
curl -s --resolve "$H:19080:$NODE_DEV" "http://$H:19080/hello-world-http/version"   # the PR head's short SHA
```

Then close the PR: within ~2 minutes the Application, the Environment and the cell namespace on dev1 are gone.

Talking points: only stock OpenChoreo objects (Environment, ProjectReleaseBinding, ReleaseBinding), shaped like the
upstream ephemeral-environment proposal; same build, scan and platform signature as `main`; 48h TTL, two previews per
tenant locally, quota and NetworkPolicy isolation from staging and production (docs/preview-environments.md
"Lifecycle and limits").

Fallback: the commit status on an older PR and docs/preview-environments.md "How it works".

## Wrap-up (1 minute)

- One repo, one command, a file per cluster; every change through Git and Argo CD.
- Supply chain enforced at admission, promotion through reviewed PRs and automated gates, runtime detection and
  response, workload identity and secrets without long-lived credentials.
- What is next: the PENDING rows of `task demo:check` and the open items of [#98](https://github.com/koorikla/platform/issues/98).
