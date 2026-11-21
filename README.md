# platform

A Kubernetes developer platform that runs entirely from Git: after `task up`, Argo CD reconciles everything and nobody
runs imperative steps. This repo is a local lab. Everything is built and proven on Docker (`k3d` for the management
cluster, Cluster API's Docker provider for workload clusters). Only the infrastructure layer (CNI, storage, cloud
controller, load balancer, CA backend) changes per provider: [docs/portability.md](docs/portability.md).

| Layer | What it does |
|---|---|
| Cluster API (CAPI) | Creates and upgrades workload clusters, one file per cluster. Locally that is k3s on Docker (CAPD). The AWS, Hetzner and GKE ClusterClasses are untested examples. Existing clusters register with `provider: byo`. |
| Argo CD | Runs on the management cluster (`mgmt`) and installs platform addons on every cluster from one label-driven catalog. |
| OpenChoreo | The developer platform: Backstage golden-path templates, projects, environments, BuildKit builds into Harbor, PR previews, gated promotion. |
| External Secrets Operator (ESO) | Delivers every credential and CA bundle from a secret backend (Kubernetes Secrets and per-tenant OpenBao locally). |
| OpenBao + cert-manager | OpenBao on `mgmt` is the mesh CA; cert-manager and istio-csr use it, so CA keys never leave `mgmt`. In a cloud, point the same issuer at a managed CA. |

<img src="docs/diagrams/architecture.svg" alt="Architecture: Argo CD on the management cluster reads Git, hands app releases to OpenChoreo and clusters to Cluster API, which creates the workload clusters; Argo CD installs their addons and the cluster-agent, which dials out to OpenChoreo and deploys the apps; Kyverno admits only signed images" width="100%">

## Quick start

You need Docker and [mise](https://mise.jdx.dev) on Linux, macOS or Windows (WSL2 or Git Bash), `amd64` or `arm64`.
Host setup and RAM: [docs/dev-environment.md](docs/dev-environment.md).

```bash
mise install      # pinned toolchain; `task doctor` checks it
task up           # k3d mgmt, local secrets, Argo CD, root Application
task status       # CAPI clusters, Argo CD apps, OpenChoreo data planes
task demo:check   # read-only PASS/FAIL table for every demo step
task down         # freeze Argo CD, delete workload clusters, delete mgmt
```

- Run from your own fork: `gh repo fork koorikla/platform --clone`, then `task set-repo REPO=<your-fork-url>`
  ([docs/forking.md](docs/forking.md)).
- Before you push: `task lint` and `task test`. `task --list` shows every target.
- Templates that create repos need a GitHub org and the platform GitHub App:
  [repository creation](docs/project-templates.md#repository-creation).

## Demo

The full walkthrough with commands is [docs/demo.md](docs/demo.md) (about 30 minutes, 10 steps):

1. Clean bootstrap: `task up` reconciles the whole platform from `bootstrap/root-app.yaml`.
2. Add a cluster by committing `installations/<inst>/clusters/<name>.yaml`.
3. Scaffold a new app repo from a Backstage golden-path template.
4. Build multi-arch images with SBOM and SLSA provenance, signed with Cosign.
5. Promote [koorikla/hello-world](https://github.com/koorikla/hello-world) `development -> staging -> production`,
   gated by HTTP and 5xx SLO checks and a reviewed PR.
6. Query logs, traces, metrics and Hubble flows from `mgmt`.
7. Detect container anomalies with Falco and respond with Falco Talon and Argo Events.
8. Sidecarless mTLS with Istio ambient, admission policy with Kyverno.
9. Provision PostgreSQL through one Crossplane API (CloudNativePG locally).
10. Get a PR preview environment.

## Diagrams

Step-by-step walkthroughs: [docs/diagrams/](docs/diagrams/README.md). Animations pause when the OS prefers reduced
motion.

| | |
|---|---|
| [<img src="docs/diagrams/security.svg" alt="Security view" width="100%">](docs/diagrams/security.svg)<br>**Security**: supply chain, admission, runtime | [<img src="docs/diagrams/network.svg" alt="Network view" width="100%">](docs/diagrams/network.svg)<br>**Network**: a request in, its telemetry out |
| [<img src="docs/diagrams/observability.svg" alt="Observability view" width="100%">](docs/diagrams/observability.svg)<br>**Observability**: collectors, stores, one query API | [<img src="docs/diagrams/sdlc.svg" alt="SDLC view" width="100%">](docs/diagrams/sdlc.svg)<br>**SDLC**: build, sign, promote, admit |
| [<img src="docs/diagrams/cluster-lifecycle.svg" alt="Cluster lifecycle view" width="100%">](docs/diagrams/cluster-lifecycle.svg)<br>**Cluster lifecycle**: add, upgrade, remove = edit one file | [<img src="docs/diagrams/trust.svg" alt="Trust and certificates view" width="100%">](docs/diagrams/trust.svg)<br>**Trust & certificates**: agent CAs, OpenBao mesh CA, renewal |
| [<img src="docs/diagrams/backup.svg" alt="Backup and restore view" width="100%">](docs/diagrams/backup.svg)<br>**Backup & restore**: the restore order | [<img src="docs/diagrams/upgrade.svg" alt="Upgrade flow view" width="100%">](docs/diagrams/upgrade.svg)<br>**Upgrades**: Renovate → CI → merge → Argo CD, dev before prod |

## Repository map

```text
bootstrap/              k3d mgmt config, bootstrap.sh (task up / down), local secret seeding, root-app.yaml
charts/                 platform (root catalog + ApplicationSets), cluster (one workload cluster), tenant (one project)
addons/                 36 platform and wrapper charts, each with its own README.md
installations/          per-installation values, cluster files (clusters/*.yaml), tenant files (tenants/*.yaml)
templates/              Backstage golden-path templates and app repo skeletons
docs/                   human documentation: guides, operations.md, runbooks/, diagrams/
hack/                   portable tooling, linters, offline contract tests (hack/tests/)
mise.toml, Taskfile.yml pinned CLI versions and Task entrypoints
```

## Documentation

| Area | Docs |
|---|---|
| Operate it (start here when something breaks) | [Day-2 operations and runbooks](docs/operations.md) |
| Design and rules | [Architecture](docs/architecture.md), [Conventions and contracts](docs/conventions.md), [AGENTS.md](AGENTS.md) |
| Clusters and networking | [Portability](docs/portability.md), [Cluster API providers and BYO clusters](docs/providers.md), [Networking and Kyverno](docs/networking.md), [Multicluster mesh and OpenBao CA](docs/multicluster.md), [External DNS](docs/dns.md) |
| Developer platform and delivery | [DevOps guide](docs/devops-guide.md), [OpenChoreo](docs/openchoreo.md), [Reference (generated)](docs/reference/README.md), [Golden-path templates](docs/project-templates.md), [Build plane and Harbor](docs/build-plane.md), [Promotion gates](docs/promotion.md), [PR preview environments](docs/preview-environments.md), [Supply chain](docs/supply-chain.md), [Releases](docs/releases.md) |
| Observability, data, AI | [Observability and Falco](docs/observability.md), [Data services](docs/data-services.md), [Crossplane platform APIs](docs/crossplane.md), [AI agents](docs/ai-agents.md) |
| Contributing | [Developer environment](docs/dev-environment.md), [Running from a fork](docs/forking.md) |

`wiki/` is working memory for AI agents. It is not documentation and may be stale.
