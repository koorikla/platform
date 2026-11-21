# Cluster API providers

How workload clusters are built: Cluster API (CAPI) with the **k3s** bootstrap + control plane provider on one of three
infrastructure providers, or a managed control plane (GKE via CAPG), or not built at all: `provider: byo` registers an
existing cluster ([below](#bring-your-own-cluster-byo)). This repo is a local lab: Docker (CAPD) and byo (a plain k3d
cluster) are the booted paths. AWS (CAPA), Hetzner (CAPH) and GKE (CAPG) are **untested examples**, rendered and
schema-checked only ([#26](https://github.com/koorikla/platform/issues/26),
[#87](https://github.com/koorikla/platform/issues/87)). What differs per provider and what never does:
[portability.md](portability.md). Design: [architecture.md](architecture.md); names and labels:
[conventions.md](conventions.md).

## What runs where

| Piece | Path | Installs |
|---|---|---|
| Operator | `addons/capi-operator` | cluster-api-operator chart 0.30.0 (needs cert-manager, its own addon) |
| Providers | `charts/cluster` scope fleet (`templates/common/capi-core.yaml`, `templates/<provider>/provider.yaml`, `credentials.yaml`) | operator CRs: core, k3s bootstrap + control plane, `docker` \| `aws` \| `hetzner` \| `gcp` per `installation.yaml` `capi.providers` |
| Classes | `charts/cluster` scope fleet (`templates/<provider>/clusterclass.yaml`) | namespace `fleet`, ClusterClasses `k3s-docker` (if CAPD), `k3s-aws`, `k3s-hetzner`, `gke-managed` (if enabled) + their templates |
| Clusters | `charts/cluster` scope cluster (`templates/common/`, `templates/byo/`) | one topology `Cluster` per fleet file + its node registry config secret, Argo CD registration, OpenChoreo, mesh, CRS |
| Cloud CCMs | `addons/aws-ccm`, `addons/hcloud-ccm` | AWS / Hetzner cloud-controller-manager on workload clusters of that provider |

### Versions

| Component | Version | Built on CAPI | Contract | API versions used |
|---|---|---|---|---|
| CAPI core | v1.13.8 | - | v1beta2 | `cluster.x-k8s.io/v1beta2` (Cluster, ClusterClass) |
| cluster-api-k3s | v0.5.0 | 1.13.8 | v1beta1 (metadata.yaml) | `bootstrap.cluster.x-k8s.io/v1beta2` KThreesConfigTemplate, `controlplane.cluster.x-k8s.io/v1beta2` KThreesControlPlaneTemplate |
| CAPD | v1.13.8 | - | v1beta2 | `infrastructure.cluster.x-k8s.io/v1beta2` DockerClusterTemplate, DockerMachineTemplate |
| CAPA | v2.13.1 | 1.13.4 | v1beta2 | `infrastructure.cluster.x-k8s.io/v1beta2` AWSClusterTemplate, AWSMachineTemplate |
| CAPH | v1.1.12 | 1.13.4 | v1beta1 | `infrastructure.cluster.x-k8s.io/v1beta1` HetznerClusterTemplate, HCloudMachineTemplate |
| CAPG | v1.13.1 | 1.13.8 | v1beta1 | `infrastructure.cluster.x-k8s.io/v1beta1` GCPManagedClusterTemplate, GCPManagedControlPlaneTemplate, GCPManagedMachinePoolTemplate; `bootstrap.cluster.x-k8s.io/v1beta1` GKEConfigTemplate |
| k3s (workload) | v1.35.10+k3s1 | | | Kubernetes 1.35: CAPI 1.13 supports workload 1.30-1.37, OpenChoreo 1.3.3 needs >= 1.32 |
| kindest/node (CAPD node OS) | v1.35.8 | | | only the OS; k3s is installed at boot |

Core 1.13 accepts v1beta1-contract providers (`GetCompatibleVersions`: v1beta2 is "temporarily compatible" with v1beta1).
k3s is not in clusterctl's built-in provider list, so its operator CRs carry
`fetchConfig.url: https://github.com/k3s-io/cluster-api-k3s/releases/<version>/{bootstrap,control-plane}-components.yaml`.
cluster-api-k3s v0.5.0's own e2e runs k3s 1.33/1.34; 1.35 is the newest line every other piece supports, and this
combination (k3s v1.35.10+k3s1 on kindest/node v1.35.8, cluster-api-k3s v0.5.0, CAPI/CAPD v1.13.8) runs on CAPD
([#56](https://github.com/koorikla/platform/issues/56)).

### Feature gates
- `ClusterTopology` is alpha and **off by default** in core 1.13 -> set to `true` on the CoreProvider (and on CAPD,
  which shares core's gate set, as the upstream quickstart does). ClusterClasses do nothing without it.
- `ClusterResourceSet` (used for the OpenChoreo agent identity) is **GA in 1.13**: the controller always runs and the
  gate no longer exists. Do not list it: an unknown gate in `--feature-gates` makes the manager exit at startup.
- CAPA has its own gates (EKS, MachinePool, ...) and CAPH has no `--feature-gates` flag; neither gets ClusterTopology.
- CAPG: `GKE` (the GCPManaged* controllers, default off) and `MachinePool` (GKE node pools) on its own manager; while
  `gcp` is enabled core's `MachinePool` gate (default on in 1.13) is listed explicitly too.

### Leader election
The provider managers (core, CAPD, CAPA, CAPG) and the operator run with 60s/40s/10s leases (lease/renew/retry) instead
of upstream's 15s/10s/2s: during a clean local bootstrap the mgmt API server stalls long enough that
capi-controller-manager lost its lease, exited, and took the CAPI webhook with it while Argo CD applied the Cluster
(#192). Same headroom as mgmt's own k3s controllers (#94). The operator turns `spec.manager.leaderElection` into
`--leader-elect-*` flags; cluster-api-k3s v0.5.0 and CAPH v1.1.12 lack them, so they keep their defaults
(`leaseFlags` in `charts/cluster/values.yaml`). Check: `kubectl -n capi-system get lease
controller-leader-election-capi -o jsonpath='{.spec.leaseDurationSeconds}'` prints `60`.

## Adding a cluster

One file: `installations/<inst>/clusters/<name>.yaml` (schema and defaults: `charts/cluster/values.yaml`). The `fleet`
ApplicationSet renders `charts/cluster` with `installation.yaml` + this file. The chart fails rendering (so Argo CD
shows the error) on: missing/invalid `name`, missing or non-k3s `kubernetesVersion`, unknown `provider` (`docker` |
`aws` | `hetzner` | `gcp-gke` | `byo`), a provider
that the installation does not enable, a cloud provider without `region`, unknown `environment` (`development` | `staging` | `production`), non-boolean `addons.*`, workers without
`name`, an even, zero or non-integer `controlPlane.replicas`, and a single-server `environment: production` cluster on
aws/hetzner (see "Control plane size and rollouts"). Types, enums, patterns and per-provider required keys are in
`charts/cluster/values.schema.json` (Helm reports `values don't meet the specifications of the schema(s)` with the
failing path, e.g. `at '/kubernetesVersion'`); cross-field rules (provider enabled, byo/GKE exclusions, mesh group,
production size) are in `charts/cluster/templates/validate.yaml`.

| Fleet file | Becomes |
|---|---|
| `name` | `Cluster/<name>` in `fleet` (DNS label, max 32 chars - it prefixes machine/LB names) |
| `provider` | `topology.classRef.name: k3s-<provider>` |
| `kubernetesVersion` | `topology.version` (k3s release, `vX.Y.Z+k3sN`) |
| `cni` | ClusterClass variable `cni` + labels ([networking.md](networking.md#cni-is-fixed-when-the-cluster-is-created)) |
| `controlPlane.replicas` | k3s servers = embedded etcd voters: odd (1, 3, 5); >= 3 for production on aws/hetzner |
| `controlPlane.machineType` | variable `controlPlaneMachineType` (aws, hetzner; ignored on docker) |
| `workers[]` `{name, replicas, machineType, failureDomain}` | machineDeployments of class `default-worker`; `machineType` -> per-MD override of `workerMachineType` |
| `region` | label; variable `region` (aws, hetzner, gcp-gke) |
| `providerSpec.*` | ClusterClass variables as-is, last (can override generated ones) |
| `secrets.nodeRegistryAuth.enabled` (installation) | variable `registryAuth` + `ExternalSecret/<name>-registries` |
| `openchoreo.dataPlane` | ClusterDataPlane + Environments ([openchoreo.md](openchoreo.md#adding-a-data-plane)) |
| `environment`, `addons`, `addonsRevision` | labels / annotation ([conventions.md](conventions.md#labels-and-annotations)) |

Removing the file (or renaming it to `*.yaml.disabled`) deletes `Application cluster-<name>` with a **background**
cascade (finalizer `resources-finalizer.argocd.argoproj.io/background`), so CAPI deletes the control plane and machines
before the infrastructure, as `kubectl delete cluster` would. A foreground cascade lets the garbage collector delete
the `DockerCluster` first, after which CAPD never finalizes the `DockerMachine` and the Cluster stays `Deleting`. Move the cluster's OpenChoreo environments away first
([dev-environment.md](dev-environment.md#local-profiles)).

ClusterClass variables:

| Class | Variable | Default | Notes |
|---|---|---|---|
| all | `registryAuth` | false | write `/etc/rancher/k3s/registries.yaml` from `Secret/<name>-registries` |
| k3s-docker | `kindImage` | `docker.io/kindest/node:v1.35.8@sha256:…` | node container image (multi-arch index digest) |
| k3s-aws | `region` | (required) | |
| | `ami` | (required) | Ubuntu 24.04 (or any cloud-init AMI) in `region` |
| | `sshKeyName` | `""` | EC2 key pair; `""` = none (omitting it would make CAPA use key `default`) |
| | `controlPlaneMachineType`, `workerMachineType` | t3.large | |
| k3s-hetzner | `region` | (required) | fsn1, nbg1, hel1, ash, hil, sin |
| | `networkZone` | eu-central | must contain `region` |
| | `sshKey` | `""` | name of an SSH key in the Hetzner project |
| | `image` | ubuntu-24.04 | |
| | `controlPlaneMachineType`, `workerMachineType` | cpx31 | |
| gke-managed | `project` | (required) | GCP project id (`providerSpec.project`) |
| | `region` | (required) | regional GKE cluster |
| | `network` | `""` | VPC name; `""` = the cluster name (CAPG creates it) |
| | `releaseChannel` | regular | rapid, regular, stable, extended |
| | `workerMachineType` | e2-standard-4 | per pool from `workers[].machineType` |
| | `workerNodeLocations` | `[]` | per pool from `workers[].failureDomain` (one zone); `[]` = GKE's default zones |

The `all` row above means every k3s class: `gke-managed` has none of `registryAuth`, `registryCA`, `cni`.

Removing the file deletes the cluster (Argo CD prune -> CAPI deletes machines and cloud resources).

### Template changes roll clusters
Machine templates are immutable, and CAPI changes a ClusterClass template by "new template + new reference". The
charts/cluster chart suffixes every template name with a hash of its spec, so a spec change in git renders a new name,
the ClusterClass follows, the topology controller rolls every cluster of that class (control plane first), and Argo CD
prunes the old template. Expect a rolling replacement of nodes after any edit to a template spec; a change to a
ClusterClass variable value in a fleet file rolls only that cluster.

### Control plane size and rollouts
k3s servers are the cluster's etcd: cluster-api-k3s v0.5.0 always starts the first server with `cluster-init: true`
(`pkg/k3s/config.go`), `IsEtcdEmbedded()` is hard-wired to `true` ("TODO ... other k3s database options",
`cluster-api-k3s/bootstrap/api/v1beta2/kthreesconfig_types.go`) and the control plane controller requires an
`EtcdMemberHealthy` machine condition before every scale step. A control plane rollout (any change to the control plane
templates or variables, a k3s upgrade, `KThreesControlPlane.spec.rolloutAfter`) replaces servers one at a time,
scale-up first: there is no `rolloutStrategy`/`maxSurge` field on `KThreesControlPlane` v1beta2 and no in-place update
support.

What a rollout does to etcd (cluster-api-k3s `controlplane/controllers/scale.go`, `machine_controller.go`,
`pkg/k3s/workload_cluster_etcd.go`):
1. A new server joins (k3s adds it as a learner and promotes it once caught up).
2. KCP picks the outdated machine, forwards etcd leadership away from it, puts the `pre-terminate.delete.hook` on it
   and deletes the Machine. Preflight excludes that machine, and `EtcdMemberHealthy` on the others does not look at
   learner status.
3. After drain, KCP's Machine controller annotates the node `etcd.k3s.cattle.io/remove=true` and waits; k3s' etcd member
   controller (`pkg/etcd/member_controller.go`) calls `RemovePeer` and then sets `etcd.k3s.cattle.io/removed-node-name`.
   As soon as that annotation is there (or the node is no longer listed as a control-plane node), KCP removes the hook
   and CAPI deletes the infrastructure immediately. KCP does not check etcd's member list or that the remaining
   members have a leader. `RemovePeer` also returns success when no member matches the node's name and address.

With **1 server** step 3 is always a 2 -> 1 member removal. etcd: "It is unsafe to remove a member from a two member
cluster" (runtime reconfiguration guide), and k3s has open reports of exactly this ending with the last member
pre-voting forever for a member that is gone (k3s#12908, k3s#13498). Rancher works around it by delaying the removal in
the 2-node case (rancher#51780). CAPI documents the same single-replica edge case for kubeadm KCP as won't-fix
(cluster-api#11772). It happened on dev1: KCP reported the member removal as successful, the new server kept
pre-voting for the removed member, the API was gone, and the cluster had to be recreated.

With **3 servers** a rollout goes 3 -> 4 -> 3 voters and never shrinks below 3, so a removal never starts from 2 voters
and a slow or failed step leaves quorum intact (KCP's preflight ignores learner state, so the removal may start while
the newest server is still a learner: 3 voters -> 2 + learner, still a removal from 3; upstream report:
[#23](https://github.com/koorikla/platform/issues/23)). KCP also remediates an unhealthy server only from 3 up
(`remediation.go`: "the number of current replicas is less or equal to 1. Skipping remediation").

| Option | Rollout safety | Cost / limits | Verdict |
|---|---|---|---|
| 3 (or 5) servers, embedded etcd | 3 -> 4 -> 3, quorum kept | 3 server machines | **production and anything that must survive rollouts** (enforced: `environment: production` on aws/hetzner needs >= 3) |
| 1 server, embedded etcd | every rollout ends with a 2 -> 1 removal; can lose quorum | cheapest | disposable clusters only: local CAPD (`dev1`, multicluster `prod1`), cloud dev clusters |
| 2 / 4 servers | as fragile as 1 / 3, no extra tolerance | | rejected by charts/cluster (odd only) |
| 1 server, SQLite (kine) | none: cluster-api-k3s v0.5.0 cannot run it - `cluster-init` is forced and KCP waits for an etcd member that never exists, so no rollout ever starts; a joining server would need etcd anyway | | not possible |
| external datastore (`datastore-endpoint`, kine on Postgres) | k3s side fine (it ignores `cluster-init` then), but KCP still generates the etcd CA and requires `EtcdMemberHealthy`, so the control plane never passes preflight | an extra HA database per cluster | not possible with v0.5.0 |
| CAPI in-place updates (1.12+, `InPlaceUpdates` gate) | no new member at all | needs an update runtime extension and control plane provider support; cluster-api-k3s v0.5.0 has neither | not available |
| KCP rollout/remediation knobs | - | v0.5.0 has only `rolloutAfter` and `remediationStrategy`; remediation never acts on 1 replica. CAPI 1.13's topology `controlPlane.rollout.after` writes `spec.rollout.after` (v1beta2 contract), which KThreesControlPlane v0.5.0 does not have: the topology reconcile fails (`.spec.rollout: field not declared in schema`) | no help for 1 server; do not set `controlPlane.rollout.after` |

charts/cluster enforces the table: `controlPlane.replicas` must be odd and >= 1, and a non-docker cluster with
`environment: production` needs >= 3. Local clusters stay at 1 server for host RAM (each extra CAPD server costs
roughly 1-2 GiB with its etcd and addons); HA mode is `controlPlane.replicas: 3` in the fleet file
(`installations/local/clusters/dev1.yaml` shows it) to test rollouts that must not break.

**Single-server rollout lost quorum (break-glass, local/dev only).** The promoted server holds a full copy of the data;
reset etcd membership to it (`--cluster-reset`, [#56](https://github.com/koorikla/platform/issues/56)) following
[runbooks/break-glass.md](runbooks/break-glass.md#single-server-etcd-quorum-loss).

### Node registry config
`charts/cluster/templates/common/capi-registries.yaml` renders `ExternalSecret/<name>-registries` (ns `fleet`) into a k3s
`registries.yaml`: GHCR auth from `platform` store key `platform-ghcr` (`username`, `token`) and, with Harbor, the
Harbor mirrors, robot auth and `registry-ca.crt` ([build-plane.md](build-plane.md#node-pulls-mirrors-with-fallback)).
Each class adds `files[].contentFrom.secret` on control plane and workers.

cluster-api-k3s v0.5.0 resolves that Secret once, when it renders the Machine's bootstrap data, and its controller
watches only `KThreesConfig`s (`cluster-api-k3s/bootstrap/controllers/kthreesconfig_controller.go`
`SetupWithManager`): a KThreesConfig reconciled before the Secret exists fails with
`failed to resolve file source: secret not found` and is retried only on controller-runtime backoff (up to ~16 min) or
the 10 min resync, so a new server can sit unbootstrapped for a long time. The ExternalSecret is therefore sync wave -1
and the Cluster wave 0: Argo CD creates or changes the Cluster only once the Secret is Ready (Argo CD's built-in
ExternalSecret health check); until then the cluster app's sync fails and is retried without limit on the latest
revision (fleet ApplicationSet `retry.limit: -1`).

`hack/tests/test_bootstrap_file_sources.sh` checks, for every installation and cluster, that each contentFrom Secret a
class enables is rendered as such an ExternalSecret with the referenced key, in an earlier wave. Bootstrap data is
rendered once per Machine, so a rotated token reaches only new nodes: the KThreesConfig controller returns early once a
config is Ready (`kthreesconfig_controller.go`: "the config is already generated and need not be generated again"), and
on CAPD the bootstrap data Secret keeps its creation-time content while `<name>-registries` refreshes hourly. Prefer a
long-lived read-only token. To push a rotated one: workers roll with the topology's
`workers.machineDeployments[].rollout.after`; the control plane does not (CAPI writes `spec.rollout.after`, which
KThreesControlPlane v0.5.0 lacks, see the KCP knobs above), so it picks up the new Secret only on its next rollout (a
change to its template or variables, a k3s upgrade).

#### Break-glass when `<name>-registries` is `Ready=False`
Because `ExternalSecret/<name>-registries` refreshes every `1h` in sync wave `-1`, an ESO refresh error (`Ready=False`)
blocks wave `0` (`Cluster/<name>`) under `retry.limit: -1` even when an older `Secret/<name>-registries` exists.
Diagnosis and declarative unblock steps: [runbooks/break-glass.md](runbooks/break-glass.md#blocked-cluster-sync-on-node-registry-secret).

### Sync waves of a cluster app
Argo CD applies one sync wave, then waits while any resource of that wave is still Progressing, and only then fails the
operation for resources that did not apply (gitops-engine `sync_context.go`). A resource that stays Progressing until
another object exists therefore hangs the operation for good when that object's apply fails in the same wave: no
failure, so no retry. Live (#192): `Cluster/dev1` failed on the CAPI webhook (capi-controller-manager had lost its
leader lease under bootstrap load) while `Certificate/dev1-mesh-reader` waited for its Issuer, which needs CAPI's
`dev1-cca` for that Cluster. So in `charts/cluster` every consumer syncs in a later wave than what it consumes:

| Wave | Resources |
|------|-----------|
| -1 | `ExternalSecret/<name>-registries` (bootstrap data, above); byo: kubeconfig access (`byo-access.yaml`) |
| 0 | `Cluster`, payload ExternalSecrets from the `platform`/`mgmt-openbao` stores, `ConfigMap/<name>-mesh-oidc`, `Issuer/<name>-agent-selfsigned` |
| 1 | consumers of CAPI's `<name>-kubeconfig` / `<name>-cca`: `ExternalSecret/<name>-argocd-cluster`, `<name>-mesh-openbao`, `Issuer/<name>-client-ca`; the ClusterResourceSets of the wave-0 payloads; `Certificate/<name>-agent-ca` |
| 2 | `Certificate/<name>-mesh-reader`, `Issuer/<name>-agent-ca` |
| 3 | `ExternalSecret/<name>-mesh-remote-secret`, `Certificate/<name>-agent-tls` |
| 4 | `ExternalSecret/<name>-openchoreo-agent` |
| 5 | `ClusterResourceSet/<name>-openchoreo-agent` |
| 9, 10 | OpenChoreo Environments, ClusterDataPlane ([openchoreo.md](openchoreo.md)); `ClusterResourceSet/<name>-mesh-remote-secret` (final wave) |

A failed apply then leaves nothing waiting in its wave: the operation fails and the fleet ApplicationSet retries it
without limit. Wave 1 starts once the Cluster is Healthy (phase `Provisioned`). A ClusterResourceSet comes after its
payload and its Cluster: it is Healthy only once CAPI applied it (`ResourcesApplied`), Degraded while the payload is
missing. `<name>-mesh-remote-secret` applies to the other mesh members, so its health is theirs: final wave, where Argo
CD does not wait for health. Matching no cluster at all (the only member, lean local profile), CAPI sets no
`ResourcesApplied`; Argo CD's built-in check calls that Progressing forever, addons/argo-cd's override calls it Healthy
(`hack/tests/test_argocd_health.sh`). `hack/tests/test_cluster_sync_order.sh` checks the rule (Certificate -> Issuer,
Issuer -> CA Secret, ExternalSecret -> Secret, ClusterResourceSet -> payload + Cluster, CAPI outputs -> Cluster; peers'
CRS in the final wave) for every installation and cluster file. Argo CD's `controller.sync.timeout.seconds` is no substitute: a timed-out operation is
terminated without retry, and auto-sync does not retry a failed revision (`appcontroller.go` `alreadyAttemptedSync`).

## Docker (CAPD) - local

- Prerequisites: mgmt is the k3d cluster `platform-mgmt` on Docker network `kind`, docker.sock mounted (`bootstrap/`).
  `installation.yaml`: `capi.providers.docker: true`. No secrets beyond `platform-ghcr` (only with node registry auth).
- Nodes are `kindest/node` containers; the bootstrap runs `curl get.k3s.io | sh` with the topology version.
  `preK3sCommands` wait until get.k3s.io answers (kindest DNS is not ready when CAPD starts the bootstrap, and a failed
  download "succeeds"), and workers get a `k3s-agent` `Type=exec` drop-in (with `Type=notify` the agent waits for CAPD
  to clear the uninitialized taint, which CAPD only does after the bootstrap returns: ~5 min deadlock). traefik is
  disabled on every class (kgateway is the ingress).
- Node identity: kubelet `--cloud-provider=external` + k3s CCM disabled (provider defaults); CAPD acts as the cloud
  provider: sets the Node's `providerID` and removes `node.cloudprovider.kubernetes.io/uninitialized`.
  klipper servicelb stays on, so `Service type=LoadBalancer` gets the node IP on the `kind` network.

### Which API server address lands in `<name>-kubeconfig`
CAPD runs an haproxy load balancer container `<name>-lb` on network `kind` and sets
`DockerCluster.spec.controlPlaneEndpoint.host` to **that container's IP on `kind`**, port 6443
(`dockercluster_backend.go`: host = LB container IPv4, only if empty). The k3s control plane provider writes the
kubeconfig for `https://<lb-ip>:6443` and adds the same address to the k3s TLS SANs. The LB also publishes 6443 on a
random host port on `0.0.0.0`, which `task kubeconfig` uses on hosts that cannot route to container IPs.

- mgmt pods (CAPI controllers, Argo CD, ESO) run on the k3d node container, which is attached to `kind`: they reach the
  LB IP directly. This is what makes the Argo CD cluster secret built from `<name>-kubeconfig` work unmodified.
- The Linux host reaches container IPs on `kind` directly. On macOS / Docker Desktop it does not: use
  `task kubeconfig CLUSTER=<name>` ([dev-environment.md](dev-environment.md#host-differences-docker-desktop-and-friends)).
- The endpoint is recorded once (CAPD sets `DockerCluster.spec.controlPlaneEndpoint.host` only while it is empty) and
  baked into `<name>-kubeconfig` and every server's k3s `tls-san`. The LB container has no static address (`docker
  inspect`: no `IPAMConfig`), and Docker releases a dynamic address when a container stops: if the LB comes back on
  another IP after a Docker or host restart, the stored endpoint is stale; recreate the cluster.

## AWS (CAPA) - untested example

> **Untested example.** Never booted in this lab (Docker + k3s/CAPD only); rendered and schema-checked in `task test`.
> Kept as a reference for real infrastructure; the developer-facing platform does not depend on it
> ([portability.md](portability.md)).

Prerequisites (once per account):
1. `clusterawsadm bootstrap iam create-cloudformation-stack` (creates the instance profiles
   `control-plane.cluster-api-provider-aws.sigs.k8s.io` / `nodes.cluster-api-provider-aws.sigs.k8s.io`; the control
   plane policy covers the AWS cloud-controller-manager).
2. Secret key `capi-aws` in the installation's `platform` store with property `AWS_B64ENCODED_CREDENTIALS`
   (`clusterawsadm bootstrap credentials encode-as-profile`). charts/cluster (scope fleet) turns it into
   `capa-system/capa-variables`, the InfrastructureProvider's `configSecret`. On an EKS mgmt with IRSA/Pod Identity set
   `aws.credentialsFromStore: false` (empty credentials, CAPA uses its pod identity).
3. `installation.yaml`: `capi.providers.aws: true`; catalog entry `aws-ccm` (below).

Class `k3s-aws`: plain Ubuntu AMI (variable `ami`, no CAPA image lookup - those are kubeadm images), k3s installed at
boot, `cloudInit.insecureSkipSecretsManager: true` (plain AMIs lack CAPA's secrets-manager boot helper, so user data
incl. the k3s join token is readable via IMDS on the instance), classic ELB with a TCP health check (k3s' ECDSA cert
breaks the ELB SSL check), node-to-node CNI ingress rules instead of CAPA's Calico defaults (cni: cilium = VXLAN
udp/8472, WireGuard udp/51871, health tcp/4240 + ICMP, Hubble tcp/4244; cni: flannel = udp/8472 only), servicelb and
traefik disabled.

Node identity / providerID: kubelet `--cloud-provider=external`, k3s CCM disabled, node name =
`{{ ds.meta_data.local_hostname }}` (cloud-init jinja; k3s bootstrap user data carries `## template: jinja`), i.e. the
EC2 private DNS name the AWS CCM expects. `addons/aws-ccm` (Argo CD, as soon as the cluster secret exists) sets
`providerID aws:///<az>/<instance-id>`, node addresses, clears the uninitialized taint, and serves
`Service type=LoadBalancer`. Its nodeSelector is overridden to `node-role.kubernetes.io/control-plane: "true"` (k3s'
label value; the chart default `""` never matches on k3s).

CSI is not included (aws-ebs-csi-driver would be another workload addon with `providers: [aws]`; the node instance
profile needs the EBS policy).

## Hetzner Cloud (CAPH) - untested example

> **Untested example.** Never booted in this lab (Docker + k3s/CAPD only); rendered and schema-checked in `task test`.
> Kept as a reference for real infrastructure; the developer-facing platform does not depend on it
> ([portability.md](portability.md)).

Prerequisites:
1. Hetzner Cloud project + API token (read/write) as key `capi-hetzner`, property `hcloud`, in the `platform` store
   (Vault/OpenBao in `hetzner-example`). `charts/cluster` (scope fleet) renders `fleet/hetzner` from it; every HetznerCluster
   references it (`hetznerSecretRef: {name: hetzner, key: {hcloudToken: hcloud}}`).
2. Optional SSH key uploaded to the project (variable `sshKey`).
3. `installation.yaml`: `capi.providers.hetzner: true`; catalog entry `hcloud-ccm` (below).

Class `k3s-hetzner`: control plane behind a CAPH load balancer (`lb11`), private hcloud network (`networkZone`),
spread placement groups for control plane and workers, Ubuntu 24.04 image, k3s installed at boot, servicelb and traefik
disabled. Pod network per fleet file `cni` ([networking.md](networking.md#cni-is-fixed-when-the-cluster-is-created)):
cilium (default) = Cilium VXLAN overlay with Cilium WireGuard; flannel = k3s flannel backend `wireguard-native`. Either
way pod traffic between nodes is encrypted and does not depend on hcloud routes (a Hetzner firewall would need
udp/8472 + udp/51871 + tcp/4240 + tcp/4244, resp. udp/51820, between nodes).

Node identity / providerID: kubelet `--cloud-provider=external`, k3s CCM disabled. CAPH names servers after the
Machine, the node name is the hostname, and the hcloud CCM matches them by name and sets `providerID hcloud://<id>`
(CAPH's upstream ClusterClass relies on the same; no kubelet `provider-id`). Credentials need no plumbing: CAPH writes
`kube-system/hcloud` (keys `token`, `hcloud`, `network`, `apiserver-host/port`) into each workload cluster once its API
answers (`reconcileWorkloadClusterSecrets`), and that is the hcloud CCM chart's default secret. `addons/hcloud-ccm`
runs with `networking.enabled: false` (no route controller; the overlay CNI does pod networking).

CSI is not included (hcloud-csi would be another workload addon with `providers: [hetzner]`, reading the same
`kube-system/hcloud` secret).

## GKE (CAPG) - untested example

> **Untested example.** Never booted in this lab (Docker + k3s/CAPD only); rendered and schema-checked in `task test`.
> Kept as a reference for real infrastructure; the developer-facing platform does not depend on it
> ([portability.md](portability.md)).

Managed control plane: `provider: gcp-gke` -> ClusterClass `gke-managed` (`charts/cluster` (scope fleet), CAPG v1.13.1).
GCPManagedControlPlane is the GKE cluster (regional, version = `topology.version`, release channel, VPC-native,
GKE Workload Identity pool `<project>.svc.id.goog`), GCPManagedCluster its VPC, and every fleet file worker a GKE node
pool (MachinePool with GCPManagedMachinePool + an empty GKEConfig; autoscaler off, size = `replicas` per zone,
auto-repair/upgrade, Shielded VM). No k3s and no cloud-controller-manager addon: Google runs both. Example:
`installations/gcp-example`.

Fleet file differences (render-time guards in `charts/cluster`, `tests/gke_test.yaml`):
- `kubernetesVersion` is a GKE version `vX.Y.Z` (CAPG drops any `-gke.N` suffix; GKE picks the build in the channel).
- `controlPlane` must be absent (`replicas` / `machineType` fail the render); `workers` needs >= 1 entry.
- `cni: gke` is the only value. CAPG v1.13.1's API has no `datapathProvider` / network-policy field, so Dataplane V2
  (GKE's Cilium) cannot be requested and the cilium addon stays off (`addons.platform.koorikla.io/cilium: "false"`).
  `mesh` layers `values/provider-gcp-gke.yaml` (Istio's `gke` platform profile).
- `providerSpec.project` is required; `network`, `releaseChannel` optional.
- No node registry config: CAPG v1.13.1 exposes no node containerd config, so `<name>-registries` is not rendered and
  nodes pull directly (private images: `imagePullSecrets` or Artifact Registry with the node service account).

Credentials, Workload Identity Federation only (no JSON key anywhere):
1. A GCP service account for CAPG (roles: Kubernetes Engine Admin, Compute Network Admin, Service Account User on the
   node service account) that may also mint tokens for itself (`roles/iam.serviceAccountTokenCreator` on itself):
   CAPG v1.13.1 writes `<name>-kubeconfig` with a 1 h access token from IAM `generateAccessToken` for `client_email`.
2. A Workload Identity pool + OIDC provider trusting the mgmt cluster's ServiceAccount issuer (upload the issuer's
   JWKS when it is not publicly reachable), with `roles/iam.workloadIdentityUser` for
   `principal://iam.googleapis.com/projects/<n>/locations/global/workloadIdentityPools/<pool>/subject/system:serviceaccount:capg-system:capg-manager`.
3. `installation.yaml`: `capi.providers.gcp: true`, `capi.gcp.workloadIdentityProvider`, `capi.gcp.serviceAccount`.
   `charts/cluster` renders `capg-system/capg-variables` (`GCP_B64ENCODED_CREDENTIALS` = an `external_account`
   credential config: identifiers + token path, no key material) and patches a projected ServiceAccount token
   (audience = the provider) into `capg-controller-manager`.

Argo CD reaches GKE clusters with `execProviderConfig` `argocd-k8s-auth gcp` (server + CA from `<name>-kubeconfig`, no
token or client cert copied). The Argo CD application controller and server then need Google ADC: GKE Workload
Identity when mgmt is GKE, otherwise a WIF credential config like CAPG's; that identity needs a GKE role (e.g.
Kubernetes Engine Developer) in the workload project.

Validated offline: CAPG CRD schemas (kubeconform -strict on the rendered class, templates, provider CRs and the
example), a ClusterClass patch simulation of `gke-managed` for the example cluster, helm-unittest. Needs a live
account ([#87](https://github.com/koorikla/platform/issues/87)): the operator's handling of the CAPG image/feature
gates/patch, WIF token exchange incl. the `client_email` self-impersonation, node pool sizing per zone, Argo CD
`argocd-k8s-auth gcp`, ClusterResourceSet delivery through the token kubeconfig, Istio's GKE profile.

## Bring your own cluster (byo)

`provider: byo` registers a cluster that already exists - any conformant Kubernetes - with **no CAPI object**. It gets
the same names, labels and identities as a CAPI cluster ([conventions.md](conventions.md#invariants): name == Argo CD
cluster secret == `ClusterDataPlane` == `planeID` == agent cert CN), the same addons and the same developer experience.
Its owner runs the infrastructure layer ([portability.md](portability.md)): nodes, version, CNI, storage, load
balancer, and node trust for the installation's registry (Harbor-built images: the nodes must trust the registry CA and
authenticate, e.g. k3s `registries.yaml`).

Fleet file (example: byo1 in `installations/local/clusters/`, opt-in: `byo1.yaml.disabled` by default):

```yaml
name: byo1
provider: byo
environment: development
cni: flannel          # what the cluster runs: label platform.koorikla.io/cni only; the cilium addon never runs on byo
openchoreo:
  dataPlane: { enabled: true, gatewayHost: byo1.apps.localhost, environments: [byo] }
```

`kubernetesVersion`, `controlPlane`, `workers`, `providerSpec`, `addons.cilium: true` and (for now) `mesh.group`
([#174](https://github.com/koorikla/platform/issues/174)) fail the render.

Credential: a kubeconfig in the installation's `platform` store, key `byo-<name>`, property `kubeconfig`: client
certificate or bearer token (no exec plugins), with a server address mgmt's pods can reach. Locally `task secrets`
seeds it from `BYO_KUBECONFIG_<NAME>` (a file) or, for a k3d cluster of that name on network `kind`, from
`k3d kubeconfig get` with the API server rewritten to the node's IP on `kind` (as CAPD's kubeconfigs). It grants what
the Argo CD cluster secret needs anyway; nothing more is added.

What `charts/cluster` renders for byo (`templates/byo/access.yaml`):

| Object (mgmt) | Purpose |
|---|---|
| `ExternalSecret/<name>-kubeconfig` (ns `fleet`) | the store key as `Secret/<name>-kubeconfig`, key `value`: what CAPI writes for its clusters, so the Argo CD cluster secret, labels and addon ApplicationSets work unchanged |
| `ClusterSecretStore/byo-<name>` | ESO kubernetes provider on that kubeconfig (`authRef`), usable from `fleet` only |
| `PushSecret/<name>-push-*` (ns `fleet`) | the ClusterResourceSet replacement, below |

**Why PushSecret.** On CAPI clusters, ClusterResourceSets apply ESO-templated payloads (agent client cert, public CAs,
derived Falco token, seeded keys) - and a CRS needs a CAPI `Cluster`. A byo cluster gets the same objects pushed by
ESO on mgmt (push mode, like Argo CD): each payload Secret is templated as a plain Secret in `fleet` and copied whole to
its namespace on the cluster. CA private keys stay on mgmt (invariant 4): only the objects a CRS would deliver are
pushed, which `hack/tests/test_byo_delivery.sh` checks for every fleet file against its CAPI twin. PushSecret writes
only Secrets, so the two CRS ConfigMaps (gateway CA, image verification; public material) are pushed as Secrets into
namespace `platform-delivery` and rebuilt as ConfigMaps on the cluster by ESO there: addon `secret-stores` adds the
name-scoped `ClusterSecretStore/delivery`, addons `openchoreo-data-plane` and `kyverno` the ExternalSecrets
(`values/provider-byo.yaml` each). The target namespaces come from their addons; a PushSecret retries until they exist.
`deletionPolicy: Delete` removes a pushed Secret when its PushSecret goes while the cluster stays registered (e.g.
`addons.falco: false`). Deregistering (deleting the fleet file) does **not** reliably clean up, as with a CRS: Argo CD
deletes the PushSecrets together with `<name>-kubeconfig` they authenticate with, and on byo1 the pushed Secrets
stayed on the cluster. When handing a cluster back, delete namespaces `openchoreo-data-plane`, `platform-delivery`,
`openchoreo-secrets` and the platform addons' namespaces on it, then the store key `byo-<name>`.

Locally (RAM: about 2.5 GiB for a k3d server with the workload addons):

```sh
k3d cluster create byo1 --agents 0 --no-lb --network kind \
  --image docker.io/rancher/k3s:v1.35.10-k3s1@sha256:8262ca99a558dca0c0437443421986480b2359f9118f2371359f88a41514522f \
  --k3s-arg '--disable=traefik@server:*'
task secrets                     # seeds byo-byo1
# enable installations/local/clusters/byo1.yaml(.disabled), merge: Argo CD registers it and syncs its addons
```

A project deploys to the byo cluster's environments like to any other: the environment needs a `ProjectReleaseBinding`
(charts/tenant creates one per `deploymentPipeline.environments` entry) and a `ReleaseBinding` per component. The live
test used a temporary pair for environment `byo` (evidence on [#173](https://github.com/koorikla/platform/issues/173)).
Harbor-built images additionally need the node's registry config (`--registry-config` with the Harbor CA and the
`nodes` robot, `--host-alias` for the registry name), which CAPD clusters get from their ClusterClass.

## Catalog entries (charts/platform/values.yaml)

```yaml
aws-ccm:    { namespace: kube-system, roles: [workload], default: true, providers: [aws] }
hcloud-ccm: { namespace: kube-system, roles: [workload], default: true, providers: [hetzner] }
```

## Argo CD notes
- Provider CRs, ClusterClasses, templates and ExternalSecrets carry `SkipDryRunOnMissingResource=true`: their CRDs are
  installed by the operator/ESO in the same sync wave cascade; Argo CD retries until they exist.
- The cluster-api-operator CRDs are ~228 KB each, close to the 256 KB client-side-apply annotation limit: sync
  `capi-operator` with `ServerSideApply=true`. CAPI webhooks default many Cluster/ClusterClass fields: use server-side
  diff (or ignoreDifferences) for the `cluster-*` and `cluster-fleet-mgmt` Applications.

Open checks: AWS and Hetzner [#26](https://github.com/koorikla/platform/issues/26); GKE
[#87](https://github.com/koorikla/platform/issues/87) (`grep -rn -e VERIFY -e '#26' -e '#87' addons/capi-*
charts/cluster addons/*-ccm addons/mesh installations/*-example`).
