# OpenChoreo on this platform

OpenChoreo 1.3.3 is the developer platform: Projects, Components, Environments, promotion. Its **control plane** runs on
mgmt; every workload cluster with `openchoreo.dataPlane.enabled: true` is a **data plane**. Argo CD installs both and
syncs OpenChoreo resources into the control plane; app workloads reach data planes only through OpenChoreo's
cluster-agent (never through Argo CD). Design background: [architecture.md](architecture.md).

Every platform `ClusterComponentType`, `ClusterTrait`, `ClusterResourceType` and `ClusterWorkflow` with its parameters
(generated from the chart): [reference/](reference/README.md).

## What runs where

| Where | Addon / chart | Namespace | What |
|---|---|---|---|
| mgmt | `gateway-api-crds` | kube-system | Gateway API v1.5.1 standard CRDs (incl. TLSRoute v1) |
| mgmt + workload | `kgateway` | catalog ns | kgateway v2.3.1 controller + `gateway.kgateway.dev` CRDs, GatewayClass `kgateway` |
| mgmt | `thunder` | thunder | ThunderID 1.0.1: OIDC IdP for console, API, CLI |
| mgmt | `openchoreo-control-plane` | openchoreo-control-plane | controller-manager, openchoreo-api, Backstage console, cluster-gateway, event-forwarder, Gateway `gateway-default`; Secret `backstage-secrets`; CRS payload `fleet/openchoreo-gateway-ca` |
| mgmt | `openchoreo-platform` | default | org namespace label, `DeploymentPipeline default`, upstream ClusterComponentTypes / ClusterTraits / ClusterProjectType, build ClusterWorkflows |
| mgmt | `openchoreo-workflow-plane` | openchoreo-workflow-plane | Argo Workflows + cluster-agent, `ClusterWorkflowPlane default`, build ClusterWorkflowTemplates ([build-plane.md](build-plane.md)) |
| mgmt | `charts/cluster` (per cluster) | fleet (+ cluster-scoped, org ns) | agent CA + client cert, CRS, `ClusterDataPlane <name>`, `Environment`s |
| mgmt | `charts/tenant` (per tenant) | argocd, org ns | AppProject `tenant-<project>`, `Project`, `ProjectReleaseBinding`s, app Applications |
| workload | `openchoreo-data-plane` | openchoreo-data-plane | cluster-agent + Gateway `gateway-default` (app ingress) |
| workload | `reloader` | reloader | Stakater Reloader (cluster-wide watch, writes fenced to cells + `openchoreo-data-plane` by VAP `reloader-rollout-only`): rolls `cluster-agent` on cert / gateway CA renewal and app Deployments when their OpenBao-backed Secret rotates (#268) |
| mgmt | `reloader` | reloader | the same addon with `values/role-mgmt.yaml`: scoped to `openchoreo-control-plane`, restarts Backstage when one of its ConfigMaps (`backstage-extra-config` etc.) changes ([project-templates.md](project-templates.md#backstage-wiring)) |
| mgmt + workload (docker) | `coredns-local` | kube-system | resolves `*.openchoreo.localhost` (mgmt: to the control-plane Gateway; workload: to mgmt) |

The workload clusters also need `cert-manager`, `external-secrets` and ClusterSecretStore `default` (secret-stores
addon): the ClusterDataPlane's `secretStoreRef` and every app ExternalSecret OpenChoreo renders use it.

The observability plane (logs/metrics/traces, alerts) runs on mgmt: see [observability.md](observability.md). The
workflow plane (in-cluster builds, the primary build path) and Harbor run on mgmt too: see [build-plane.md](build-plane.md).

### Ordering

There is no hard ordering between Applications; Argo CD retries cover it:

1. `gateway-api-crds`, `cert-manager`, `external-secrets` + stores, `kgateway`, `thunder` converge independently.
   Thunder's setup Job waits for Secret `thunder-bootstrap` (`platform` store), its HTTPRoute for the Gateway.
2. `openchoreo-control-plane` installs the OpenChoreo CRDs (chart `crds/`) with the controllers. Its Gateway needs the
   GatewayClass, its Certificates cert-manager.
3. `openchoreo-platform`, `tenant-*`, and the OpenChoreo objects of `cluster-*` fail with `no matches for kind ...`
   until step 2 is done; they carry `SkipDryRunOnMissingResource=true` (and sync wave 10 in `charts/cluster`), so the
   rest of each Application (namespace label, CAPI cluster, PKI) still applies and the Application retries.
4. On a new workload cluster: the CRS applies the agent Secret/ConfigMap as soon as CAPI sees the cluster; the
   data-plane agent waits in ContainerCreating until they exist, then connects.

References between OpenChoreo objects (Project -> DeploymentPipeline, Environment -> ClusterDataPlane, Component ->
ComponentType) are not validated by the API server; the controllers reconcile once the target exists. One exception
needs an order: the ReleaseBinding controller (v1.3.3) does not watch Environments, so a binding reconciled before its
Environment exists stays `EnvironmentNotFound`. It re-queues the bindings of a ClusterDataPlane's Environments when
that ClusterDataPlane is created, so `charts/cluster` applies the Environments in wave 9, one before the
ClusterDataPlane (wave 10). On a clean bootstrap the tenant's bindings exist long before the CAPD cluster is up.

### Argo CD requirements

- `ServerSideApply=true` on the `gateway-api-crds` and `kgateway` Applications (CRDs of 244-520 KB exceed the
  client-side last-applied annotation).
- PVC health override in `argocd-cm` so a `Pending` PVC counts as Healthy: Thunder's PVCs are PreSync hooks and
  local-path binds only when the setup Job (a later hook) mounts them; without it the PreSync phase never ends.

  ```yaml
  resource.customizations.health.PersistentVolumeClaim: |
    hs = {}
    if obj.status ~= nil and (obj.status.phase == "Bound" or obj.status.phase == "Pending") then
      hs.status = "Healthy"; hs.message = obj.status.phase; return hs
    end
    hs.status = "Progressing"; hs.message = "Waiting for PVC"; return hs
  ```
- Retries with backoff on every generated Application (CRDs from other Applications), without a limit and on the
  latest revision: a sync that gives up stays failed until the next commit (#192).
- Helm hooks run on every sync under Argo (Helm: install only). Thunder's setup Job is idempotent and replaced on
  every sync (`setup.preserveJob`: Argo's default BeforeHookCreation, so a failed run never blocks the next one and
  `kubectl -n thunder logs job/thunder-setup` shows the last run); the control plane's authz bootstrap Job (PostSync)
  re-applies its roles.
- Argo CD never diffs hooks, but it runs them only when a sync happens: a change to a hook alone (ExternalSecret
  `thunder-bootstrap` after #218) left the app Synced and the live object old (#221). Real config is therefore a
  normal resource ordered by sync waves, and only the Job is a hook. Where a Job's input must itself be a hook (Thunder:
  upstream hardcodes the setup Job as `pre-install` = PreSync, which runs before any sync wave, so its ExternalSecret
  and ConfigMaps stay PreSync hooks; control plane: upstream's PostSync authz ConfigMap), a normal ConfigMap labelled
  `platform.koorikla.io/hook-inputs` (`thunder-setup-inputs`, `openchoreo-authz-bootstrap-inputs`) carries one
  checksum per hook input, so a change makes the app OutOfSync and the sync re-applies the hooks. Self-heal still does
  not repair hand edits of a hook object. `hack/tests/test_hook_kinds.sh` allows a non-Job hook only via
  `hack/tests/hook_allowlist.yaml` (with a reason) and requires the checksum key for hook ConfigMaps/Secrets/ExternalSecrets.
- Thunder's PVCs are hooks Argo CD can delete: the upstream chart hardcodes them as `pre-install` hooks (they must
  exist before the PreSync setup Job mounts them), and an Argo hook always has a delete policy (none =
  BeforeHookCreation, i.e. every sync). They keep `hook-failed`, so a successful sync never touches them, but a failed
  PreSync phase makes Argo delete them (claims Terminating, kept only by the running pod).
  So the PVCs carry `platform.koorikla.io/delete-protection: enabled` and the PreSync hook VAP
  `thunder-pvc-delete-protection` (weight -30, before-hook-creation only, so it outlives a failed sync) denies their
  DELETE for everyone, Argo CD included. Break-glass, to really drop Thunder's data:
  `kubectl -n thunder annotate pvc <name> platform.koorikla.io/delete-protection-`, then delete. Verify the policy:
  `kubectl -n thunder delete pvc thunder-database-pvc --dry-run=server` must answer Forbidden.
  `hack/tests/test_pvc_hooks.sh` holds every addon to this: a hook PVC is `hook-failed` only, annotated, and covered
  by such a policy in its render. PVC rebind and recovery: [runbooks/backup-restore.md](runbooks/backup-restore.md#4-thunder-pvc-recovery-live-verified);
  intentional delete: [runbooks/break-glass.md](runbooks/break-glass.md#intentional-deletion-of-a-delete-protected-pvc).

## Trust model

Upstream's multi-cluster recipe copies the agent's self-signed CA back to the control plane by hand, or copies the
control plane's CA **private key** into every plane. Neither happens here.

```
mgmt, ns fleet (charts/cluster)                             workload cluster <name>, ns openchoreo-data-plane
  Issuer <name>-agent-selfsigned
   └ Certificate <name>-agent-ca (isCA, 10y) ── trusted by ClusterDataPlane <name> (clientCA secretKeyRef)
      └ Issuer <name>-agent-ca
         └ Certificate <name>-agent-tls (CN=<name>, client auth, 1y)
              └ ExternalSecret (store mgmt-fleet) ─► Secret <name>-openchoreo-agent ─┐
mgmt, ns openchoreo-control-plane (chart)                                             │ ClusterResourceSet
  Secret cluster-gateway-ca (gateway CA, 10y)                                         │ <name>-openchoreo-agent
   └ ca.crt only ─► ExternalSecret (store mgmt-openchoreo) ─► Secret fleet/openchoreo-gateway-ca ─┤ (Reconcile)
                                                                                      ▼
                                              Secret cluster-agent-tls (tls.crt, tls.key, ca.crt) ─┐
                                              ConfigMap cluster-gateway-ca (ca.crt) ───────────────┴─► Reloader rolls cluster-agent
```

- **Per-cluster CA.** Each cluster's agent cert is signed by its own CA on mgmt; `ClusterDataPlane <name>` trusts only
  that CA, so a compromised cluster cannot impersonate another plane. Deleting the cluster file deletes the CA:
  revocation. CA private keys never leave mgmt.
- **Server trust.** Agents verify the cluster-gateway against the control plane's gateway CA (public cert only). The
  gateway's server cert (`cluster-gateway-tls`) carries the SAN agents dial (`cluster-gateway.openchoreo.localhost`).
- **Delivery.** CAPI's ClusterResourceSet is the only mgmt -> workload write path (it already exists for CAPI). ESO
  templates the payloads from cert-manager's Secrets via read-only in-cluster stores; no scripts.
- The data-plane chart still renders its own self-signed Certificate (no knob): it goes to the unused Secret
  `cluster-agent-selfsigned-unused`. `caSecretName` is empty: no CA Secret is ever needed on a data plane.
- **Rotation.** cert-manager renews the client cert 30 days before expiry; ESO (≤1h) and the CRS (`Reconcile`) update
  `cluster-agent-tls`. Because the 1.3.3 agent reads its client cert and gateway CA once at start, addon `reloader`
  (may roll workloads only in `openchoreo-data-plane` and tenant cells, `reloadStrategy: annotations` so Argo CD sees no drift) watches both objects and
  rolls `deploy/cluster-agent-dataplane` automatically on change; the same applies to the gateway CA (10y).
- The upstream cluster-gateway has cluster-wide `get/list secrets` (to read every plane's client CA): it can read
  `fleet/<name>-agent-ca` including the CA key. It runs on mgmt, so this does not widen the workload-cluster boundary.

## Local networking

mgmt is k3d `platform-mgmt` (traefik disabled, klipper servicelb on, docker network `kind`). The control-plane Gateway
`gateway-default` gets a LoadBalancer Service with ports **8080** (HTTP: console, API, Thunder) and **8443** (TLS
passthrough: cluster-gateway); klipper binds them as hostPorts on the mgmt nodes; k3d publishes them on the host:

```
k3d cluster create platform-mgmt ... -p "8080:8080@loadbalancer" -p "8443:8443@loadbalancer"
```

Nothing else on mgmt may bind hostPort 8080/8443 (e.g. Argo CD server must stay ClusterIP or use other ports).

| URL | Served by |
|---|---|
| http://openchoreo.localhost:8080 | console (Backstage) |
| http://api.openchoreo.localhost:8080 | openchoreo-api |
| http://thunder.openchoreo.localhost:8080 | ThunderID (console at /console) |
| wss://cluster-gateway.openchoreo.localhost:8443/ws | cluster-gateway (agents only, mTLS) |

`*.localhost` resolves to loopback in browsers. Pods use the same URLs through `coredns-local`:

- mgmt pods (Backstage -> Thunder token endpoint, openchoreo-api -> JWKS): rewrite to
  `gateway-default.openchoreo-control-plane.svc.cluster.local` (Service port 8080 == listener == published port).
- workload pods (the agent): rewrite to `k3d-platform-mgmt-serverlb`, the k3d load balancer container on network
  `kind`, resolved by Docker's embedded DNS (kindest/node's CoreDNS forwards to it). Its 8443 forwards to the mgmt
  nodes -> Gateway TLS passthrough (SNI `cluster-gateway.openchoreo.localhost`) -> TLSRoute -> `cluster-gateway-external`.

The installation key `openchoreo.controlPlane.clusterGatewayURL` is the source of truth; the control-plane and
data-plane addons fail to render if their literal values drift from it or from `openchoreo.controlPlane.host`.

### App traffic

Each data plane's Gateway listens on HTTP **19080** (LoadBalancer -> klipper hostPort on every CAPD
node container). `ClusterDataPlane <name>` advertises `gatewayHost:19080` (cluster file `openchoreo.dataPlane`), and
the component types route `http://<env>-<org namespace>.<gatewayHost>:19080/<component>-<endpoint>/...`. CAPD nodes
publish no host ports, but the Linux host reaches container IPs directly:

```bash
NODE_IP=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' $(docker ps -qf name=dev1-) | head -1)
curl --resolve development-default.dev1.apps.localhost:19080:$NODE_IP \
  http://development-default.dev1.apps.localhost:19080/hello-world-http/
```

## Secrets

| Store (ClusterSecretStore) | Used for |
|---|---|
| `platform`, key `openchoreo` | properties `thunder-admin-password`, `admin-user-password`, `developer-user-password`, `backstage-client-secret`, `backstage-backend-secret`, `service-mcp-client-secret` (alphanumeric; seeded by `task secrets` locally, created by the operator in aws/vault) |
| `mgmt-fleet` (ns fleet, read-only) | `<name>-agent-tls` -> CRS payload `<name>-openchoreo-agent` (ExternalSecret in ns fleet) |
| `mgmt-openchoreo` (ns openchoreo-control-plane, read-only) | `cluster-gateway-ca` (`ca.crt` only) -> CRS payload `openchoreo-gateway-ca` (ExternalSecret in ns **fleet**) |
| `default` (workload clusters) | `ClusterDataPlane.spec.secretStoreRef`; platform secrets on the data plane. Refuses tenant (cell) namespaces when `secrets.tenantStores.enabled` |
| `SecretStore openbao-tenant` (each cell namespace) | app secrets: OpenChoreo `SecretReference`s, read from the project's own OpenBao mount `kv-tenant-<project>` ([below](#application-secrets-developer-view)) |

Thunder users: `admin@openchoreo.dev` (group `admins` -> OpenChoreo role admin) and `developer@openchoreo.dev`
(groups `developers` and `demo-developers`), passwords from the `openchoreo` key. Thunder console: user `admin`,
`thunder-admin-password`.

### Developer access is per project

- Group `developers` (every developer) gets org-wide READ-ONLY roles `cluster-reader` + `namespace-reader` (addon
  openchoreo-control-plane `developer-binding`; upstream gives it role `developer`, i.e. write access to every project).
- Each tenant's `developerGroups` (tenant file, default `<project>-developers`) get role `developer` scoped to that
  project only (`charts/tenant` `AuthzRoleBinding <project>-developer-<group>`), with binding writes in gated
  environments excluded by a condition. A developer of project A gets OpenChoreo's default deny in project B, so the
  `spec.owner.projectName` of anything they create through console, `occ` or MCP is their own project.
- The deny bindings (`promotion.restrictedGroups`) cover only grants of the same group value: OpenChoreo resolves deny
  per entitlement value, so project groups carry their production exclusion in their own binding.
- Onboarding a developer = add them to `developers` and to the project's group in the IdP. `developerGroups` may not
  list `developers` (chart validation: that would reopen the project to everyone).
- `SecretReference` is namespace-level in OpenChoreo, so developers do not create them through the API: app repos
  sync them from git ([App repo contract](#app-repo-contract)).

### Application secrets (developer view)
A value lives in OpenBao, git holds only a pointer to it (`SecretReference`), and the Workload names the pointer.
Worked example: hello-world `GREETING_SECRET` (`deploy/openchoreo/greeting-secret.yaml` + `workload.yaml`).

1. **Write the value** to your project's mount `kv-tenant-<project>` with the project's writer identity
   (`openbao-tenants/<project>-writer`, never root): command in
   [multicluster.md](multicluster.md#tenant-secrets-openbao) "Writing a secret". One mount per project, shared by its
   environments: use different keys (`hello-world` vs `hello-world-prod`) when values differ per environment.
2. **Point at it** from the app repo: `SecretReference` with `data[].secretKey` (the key in the Kubernetes Secret)
   and `remoteRef.key` / `.property` (path and field *inside your own mount*; never a mount name or a store; there is
   no store field). Synced by the app's Argo CD Application like the Workload.
3. **Consume it** in `workload.yaml`: `env[].valueFrom.secretKeyRef: {name: <SecretReference>, key: <secretKey>}`
   (or `files[].valueFrom.secretKeyRef` for a file). OpenChoreo checks the key exists in the SecretReference.
4. **What the platform renders**: in each cell namespace an `ExternalSecret` (`refreshInterval: 15s`, set by the
   component type, which ignores `SecretReference.spec.refreshInterval`) on that namespace's `SecretStore
   openbao-tenant`, and the Deployment takes the Secret via `envFrom`. `task demo:check` row `app-secret` asserts it.
5. **Rotate**: write a new version (step 1). The Kubernetes Secret follows within ~15 s and Reloader rolls the pods of
   every Deployment that references it (env vars and `subPath` files are read at container start), in every
   environment and preview cell: the component types annotate the Deployment `secret.reloader.stakater.com/auto:
   "true"` (#268, [runbook](runbooks/certificates-and-secrets.md#7-tenant-application-secrets-openbao)).

Isolation: the store is fixed by the platform, a tenant `ExternalSecret`/`SecretStore` is rejected on the data plane
(VAP, addon secret-stores) and cannot be synced from an app repo (tenant AppProject), and OpenBao answers a cell
namespace only from `kv-tenant-<its project>`. A `remoteRef.key` naming another project's path still resolves inside
your own mount (ESO prefixes the store's mount), and OpenBao would deny it anyway. Tests: `hack/tests/test_tenant_app_secrets.sh`, `task test:openbao`.

## Adding a data plane

In `installations/<inst>/clusters/<name>.yaml`:

```yaml
openchoreo:
  dataPlane:
    enabled: true
    gatewayHost: dev1.apps.localhost   # base host of app URLs on this cluster
    gatewayPort: 19080                 # the data plane Gateway's HTTP listener
    environments: [development, staging]
```

Every environment must be listed in exactly one enabled cluster file (two clusters claiming one Environment = Argo
conflict), and every environment of `DeploymentPipeline default` (addon `openchoreo-platform`) and of `promotion`
needs a cluster (`hack/tests/test_local_profiles.sh`, also for each installation's `*.yaml.disabled` switch). One
cluster may host every environment: OpenChoreo puts each in its own namespaces, and per-environment policy follows
the namespace's `openchoreo.dev/environment` label (docs/dev-environment.md "Local profiles"). An Environment's
`dataPlaneRef` is immutable: to move it, remove it from one file and from `DeploymentPipeline default` (OpenChoreo
will not delete a referenced Environment), sync, then add it back to the pipeline; a gated environment also needs the
controller as a temporary binding deleter (docs/dev-environment.md "Local profiles" has the two-merge procedure).

## Tenants

`installations/<inst>/tenants/<project>.yaml`:

```yaml
project: demo                       # OpenChoreo Project (DNS-1123)
description: Demo project
apps:
  - name: hello-world               # unique in the tenant -> Application demo-hello-world
    repoURL: https://github.com/koorikla/hello-world.git
    path: deploy/openchoreo         # default
    revision: main                  # default
```

ApplicationSet `tenants` (charts/platform) -> Application `tenant-<project>` (AppProject `platform`) -> charts/tenant:

- AppProject `tenant-<project>`: `sourceRepos` = exactly the tenant's app repos; destination = mgmt
  (`https://kubernetes.default.svc`), org namespace only; no cluster-scoped kinds; namespaced kinds limited to
  `openchoreo.dev` `Component`, `Workload`, `ReleaseBinding`, `ComponentRelease`, `SecretReference`, `Resource`,
  `ResourceReleaseBinding` (databases and other managed infrastructure:
  [data-services.md](data-services.md#postgresql-from-openchoreo)).
- OpenChoreo `Project <project>` (type `ClusterProjectType/default`, pipeline `default`) and one
  `ProjectReleaseBinding <project>-<env>` per pipeline environment (provisions the project's namespace on each data
  plane). Platform-owned: app repos cannot create or edit Projects.
- One Application `<project>-<app>` per app (project `tenant-<project>`, automated sync, prune, self-heal, recursive
  directory so `release-bindings/` is included), plus one Application `<project>-<app>-<env>` per gated environment
  (`promotion.gatedEnvironments`, default production) that syncs only `release-bindings/<env>.yaml`; the main
  Application excludes that file. The AppProject's freeze windows (`promotion.freezeWindows`) are Argo CD deny sync
  windows on those Applications. Production promotion is a reviewed PR; details: [promotion.md](promotion.md).

Removing an app from the file deletes its Application and its OpenChoreo resources (finalizer); removing the file
offboards the whole project. Limitation: Argo cannot restrict field values, so a tenant repo could set
`spec.owner.projectName` of a Component to another project; OpenChoreo's authz is the guard there.

## App repo contract

An app repo owns its OpenChoreo manifests as plain YAML in `deploy/openchoreo/` (no Helm/Kustomize needed; Argo CD
applies the directory). All objects go to the org namespace (`default`) and name the tenant's project in
`spec.owner.projectName`. One Component per app repo, named like the app in the tenant file: the admission policy on
gated environments accepts a component's production binding only from Application `<project>-<component>-production`
([promotion.md](promotion.md#2-git-is-the-only-path-to-gated-bindings-native)), so a binding of a differently named
component is denied there. For `hello-world` (project `demo`, image `ghcr.io/koorikla/hello-world:<tag>`, HTTP 8080):

`deploy/openchoreo/component.yaml`
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
    name: deployment/service      # <workloadType>/<ClusterComponentType>: service | web-application | worker | scheduled-task (cronjob/)
  autoDeploy: true                # each Workload change -> new ComponentRelease, bound to the first environment
```

`deploy/openchoreo/workload.yaml` (builds change only `image` and `source.commit`)
```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: Workload
metadata:
  name: hello-world-workload
  namespace: default
spec:
  owner:
    projectName: demo
    componentName: hello-world
  container:
    image: ghcr.io/koorikla/hello-world:sha-0123abc
  endpoints:
    http:                         # endpoint name -> URL path /hello-world-http
      type: HTTP
      port: 8080
      visibility: [external]      # routed on the data plane Gateway (ClusterDataPlane gateway.ingress.external)
```

`deploy/openchoreo/release-bindings/staging.yaml` and `release-bindings/production.yaml` (file name = environment;
`promotion.bindingFile`)
```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: ReleaseBinding
metadata:
  name: hello-world-staging       # <component>-<environment>
  namespace: default
spec:
  owner:
    projectName: demo
    componentName: hello-world
  environment: staging
  releaseName: hello-world-5d8f9c7b6   # a ComponentRelease name; promotion = changing this line
  # componentTypeEnvironmentConfigs: { replicas: 2 }   # per-environment parameters of the component type
```

### How GitOps promotion works

1. A build - the Component's OpenChoreo ClusterWorkflow (default, [build-plane.md](build-plane.md)) or the optional
   GitHub Actions path - pushes a signed image and commits the new image ref into `workload.yaml`.
2. Argo CD syncs the Workload. With `autoDeploy: true` the Component controller creates an immutable
   `ComponentRelease hello-world-<hash>` (snapshot of Component + ComponentType + Workload; the hash is deterministic)
   and creates/updates `ReleaseBinding hello-world-development` (first environment of the pipeline) to it. The
   development binding is controller-owned: do not commit it (or commit it **without** `releaseName`, only for
   `componentTypeEnvironmentConfigs`).
3. Promote by commit: set `releaseName` in `release-bindings/staging.yaml` to the release now running in development
   (`kubectl -n default get component hello-world -o jsonpath='{.status.latestRelease.name}'`, or the console), then the
   same for production after staging; production changes go through the gates in [promotion.md](promotion.md).
   Rollback = revert the commit. Git is the source of truth for staging/production:
   a promotion clicked in the console on a git-owned binding is reverted by Argo's self-heal.
4. OpenChoreo renders each binding against its Environment's ClusterDataPlane and the cluster-agent applies the
   Deployment/Service/HTTPRoute in the project namespace on that data plane.

Fully declarative alternative (`autoDeploy: false`): commit the `ComponentRelease` objects too and bind them by name,
as [openchoreo/sample-gitops](https://github.com/openchoreo/sample-gitops) does (its workflows generate Workload,
ComponentRelease and ReleaseBinding manifests and open a PR). A ComponentRelease embeds the full component type spec,
so it is meant to be generated (workflow plane or `occ`), not hand-written. `ComponentRelease` is in the tenant
whitelist for that reason.

Secrets: declare an OpenChoreo `SecretReference` (key inside the project's OpenBao mount) and reference it from
`workload.yaml` (`env[].valueFrom.secretKeyRef`); never commit values. Step by step:
[Application secrets](#application-secrets-developer-view).

## Resilience defaults

Developers set nothing: every Deployment component type (`deployment/service`, `deployment/web-application`,
`deployment/worker`) embeds the platform ClusterTrait `resilience` (addon openchoreo-platform,
`files/platform/cluster-traits/resilience.yaml`, #251). It reads the environment name and the component's `replicas`.

| Default | development / previews | staging | production |
|---|---|---|---|
| topologySpreadConstraints, nodes + zones, maxSkew 1, `matchLabelKeys: [pod-template-hash]` | ScheduleAnyway | ScheduleAnyway | ScheduleAnyway (zones: knob) |
| PodDisruptionBudget `maxUnavailable: 1`, `unhealthyPodEvictionPolicy: AlwaysAllow` | - | when replicas >= 2 | when replicas >= 2 |
| `preStop: sleep 5s`, `terminationGracePeriodSeconds: 30` | yes | yes | yes |
| PriorityClass (addon priority-classes, `preemptionPolicy: Never` — orders the scheduling queue without evicting platform or app pods) | `app-standard` (1000) | `app-standard` (1000) | `app-production` (100000) |
| Kyverno `openchoreo-workload-resilience-*` | Audit | Audit | **Deny** |

What developers still choose:

| Need | Where |
|---|---|
| readiness / liveness / startup probes | ClusterTrait `health-probes` on the Component (required in production) |
| replicas, cpu/memory requests | ReleaseBinding `componentTypeEnvironmentConfigs` (production: replicas >= 2, requests set) |
| autoscaling | ClusterTrait `keda-scaler` or `horizontal-pod-autoscaler`; production minReplicas >= 2 |
| hard zone spread (multi-zone data planes only) | `componentTypeEnvironmentConfigs.resilience.zoneSpread: DoNotSchedule` |
| dedicated node pool | `componentTypeEnvironmentConfigs.resilience.nodePool: <pool>` (nodes labelled `platform.koorikla.io/node-pool`) |
| slower shutdown | `resilience.terminationGracePeriodSeconds`, `resilience.preStopSleepSeconds` |

Why spread and not podAntiAffinity: required anti-affinity caps a component at one pod per node and blocks rollouts
on small clusters; preferred anti-affinity is all-or-nothing scoring. A skew of 1 spreads any replica count evenly and
`matchLabelKeys` keeps the old ReplicaSet out of the new one's maths. Zones stay ScheduleAnyway by default because
nodes without `topology.kubernetes.io/zone` (k3d, single-zone clouds) are not eligible at all under DoNotSchedule.
The preStop sleep keeps a terminating pod serving while the endpoints and the gateway drop it (native sleep action,
no shell in the image needed).

Production enforcement (addon kyverno-policies `templates/workload-resilience.yaml`): Deployments need >= 2 replicas
(autoscaled ones state their floor in label `resilience.platform.koorikla.io/min-replicas`, set by the trait),
a readinessProbe and cpu + memory requests on every container; HorizontalPodAutoscalers (also KEDA's) minReplicas >= 2.
A denial shows up as an apply failure on the RenderedRelease. The PDB itself is not an admission check (OpenChoreo
applies it together with the Deployment, in no fixed order): it exists by construction and `task demo:check`
(row "hello-world PDB/spread/priority in production") asserts it.

## Config files and env (developer view)

Nothing platform-specific to attach (#252). OpenChoreo 1.3.3 itself turns a Workload's plain `env` values into a
ConfigMap read through `envFrom`, and each `files` entry into a ConfigMap mounted at `<mountPath>/<key>` (secret values
and files use `secretKeyRef`, [Application secrets](#application-secrets-developer-view)):

```yaml
# deploy/openchoreo/workload.yaml (app repo)
spec:
  container:
    env:
      - { key: GREETING, value: hello }
    files:
      - key: config.yaml
        mountPath: /etc/app            # -> /etc/app/config.yaml
        value: |
          greeting: hello
          features: { dark-mode: true }
```

A change rolls the pods: OpenChoreo hashes every non-workload data-plane resource of a Deployment (the ConfigMaps above,
but also PodMonitors, PDBs, ...) into the pod template annotation `openchoreo.dev/dp-resource-hash`. Without it nothing
would pick the change up (the ConfigMap names do not depend on the content, `envFrom` is read at start, subPath mounts
never refresh). Per environment: `workloadOverrides` on the ReleaseBinding. Guarded by
`addons/openchoreo-platform/tests/app_config_metrics_test.yaml`.

## Application metrics

Opt-in ClusterTrait `metrics` (addon openchoreo-platform `files/platform/cluster-traits/metrics.yaml`, #252), allowed on
every Deployment component type. The developer names the port that serves Prometheus metrics (often the HTTP endpoint's):

```yaml
# deploy/openchoreo/component.yaml (app repo)
spec:
  traits:
    - { kind: ClusterTrait, name: metrics, instanceName: metrics, parameters: { port: 8080 } }   # path: /metrics
```

The trait declares the port on the main container as `metrics` (OpenChoreo declares no container ports and a PodMonitor
selects only declared ones) and renders a PodMonitor in the cell, labelled `component`, `project`, `environment`. The
data plane's Prometheus agent (addon telemetry) selects every PodMonitor and remote-writes to the observability plane's
Prometheus. STRICT mTLS cells need nothing extra: the agent is in the ambient mesh and a `platformPeers` principal of
the cell AuthorizationPolicy ([networking](networking.md), #209, #323, #324). Per environment (trait
`environmentConfigs` on the ReleaseBinding): `enabled`, `interval` (30s), `sampleLimit` (5000: a scrape with more
samples is dropped whole so one app's label explosion cannot exhaust the shared agent). A changed interval restarts the
pods (dp-resource-hash, above).

Platform side: the data-plane agent may apply PodMonitors (addon openchoreo-data-plane `clusterAgentDataServices`), and
its capability gate waits for the PodMonitor CRD (`capabilityGate.addons.telemetry`, on unless the cluster opts out of
telemetry). Where a fleet file sets `addons.telemetry: false` there is no scraper: the PodMonitor is skipped and the app
deploys as without the trait. `hack/tests/test_openchoreo_types.sh` checks grant, gate and skip
(`platform.koorikla.io/uses-addons`). Query: `sum by (component, environment) (rate(http_requests_total[5m]))` in the
observability plane's Prometheus.

## Known issue: re-created data plane clusters

When a workload cluster is re-created under the same name (new CAPD/cloud cluster, new agent connection), OpenChoreo's
RenderedRelease controller can stay on a failed apply (`proxy request failed with status 502`, from while the agent was
not connected yet) for a long backoff ([#51](https://github.com/koorikla/platform/issues/51)). Triage and the
annotation kick command: [runbooks/incidents.md](runbooks/incidents.md#data-plane-agent-disconnected).

The mechanism (confirmed in v1.3.3 source and live in [#246](https://github.com/koorikla/platform/issues/246)): the
RenderedRelease controller returns an apply error to controller-runtime and watches only RenderedReleases, so the next
attempt follows the default rate limiter (5 ms doubling, max 1000 s) and nothing re-queues it when the data plane
recovers. On a fresh bootstrap the same backoff kept development down ~17 min after addon keda was Healthy: the data
plane's agent therefore starts only once the CRDs of its opt-in addons exist (`capabilityGate` in addon
openchoreo-data-plane, [data services](data-services.md#only-on-data-planes-that-run-the-operator)).

Values inferred but not yet confirmed live (`grep -rn VERIFY addons/openchoreo-* addons/thunder addons/coredns-local charts/cluster/templates/common/openchoreo-*`):
[#52](https://github.com/koorikla/platform/issues/52).
