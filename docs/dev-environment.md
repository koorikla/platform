# Developer environment

One toolchain, pinned once, on **macOS, Linux and Windows, amd64 and arm64**: [mise](https://mise.jdx.dev) installs
every CLI at the version in [`mise.toml`](../mise.toml), [`Taskfile.yml`](../Taskfile.yml) is the single entrypoint
(via [Task](https://taskfile.dev), installed by mise), and the scripts behind it are portable bash.

| Host | Status | Proof |
|---|---|---|
| Linux amd64 / arm64 | supported | `portability` workflow (`ubuntu-latest`, `ubuntu-24.04-arm`): `mise install`, `task lint test` |
| macOS arm64 (Apple Silicon) / amd64 | supported (offline validation proven; `task up` not yet, [#60](https://github.com/koorikla/platform/issues/60)) | `macos-latest`, scripts forced onto the stock `/bin/bash` 3.2 |
| Windows 11 + WSL2 | **recommended on Windows**: it is Linux | as Linux |
| Windows amd64, Git Bash | `doctor`/`lint`/`test` (incl. schemas) proven; `task up` not yet ([#60](https://github.com/koorikla/platform/issues/60)) | `windows-latest`, `shell: bash` |
| Windows on Arm | as above; helm/yq/argocd ship native arm64, jq/k3d/shellcheck run x64-emulated | lock entries only |
| Dev container / Codespaces | zero-install option, amd64 + arm64 | `devcontainer` job builds it, starts its Docker engine and runs `task doctor lint` on both arches |

## Install (three lines per OS)

**macOS** (Docker Desktop, OrbStack or Colima as the engine)
```bash
brew install mise git && echo 'eval "$(mise activate zsh)"' >> ~/.zshrc && exec zsh
cd platform && mise trust && mise install      # all tools + helm-unittest plugin
task up
```

**Linux** (Docker Engine; your user in the `docker` group)
```bash
curl -fsSL https://mise.run | sh && echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc && exec bash
cd platform && mise trust && mise install
task up
```

**Windows, WSL2 (recommended)**: install Docker Desktop with *WSL integration* for your distro (or Docker Engine
inside the distro), clone the repo **inside the WSL filesystem** (`~/src`, not `/mnt/c`: 10x faster, no CRLF or
permission surprises), then follow the Linux lines in the WSL shell.

**Windows, native (Git Bash)**
```bash
winget install jdx.mise Git.Git Docker.DockerDesktop    # PowerShell, once; then open "Git Bash"
cd platform && mise trust && mise install && export PATH="$HOME/AppData/Local/mise/shims:$PATH"
task lint test                                          # for clusters prefer WSL2
```

**Zero install**: open the repo in VS Code *Dev Containers*, GitHub Codespaces or DevPod. `.devcontainer/` brings
Ubuntu 24.04 + its own Docker engine (docker-in-docker feature v4: it picks iptables-nft at start on kernels without
legacy iptables, which GitHub's amd64 runners need) and runs `mise install` on create. Codespaces needs the 8-core /
32 GB machine for the full local platform (estimated from the k3d + two CAPD clusters footprint).

Without mise activated in your shell, prefix commands with `mise exec --` (`mise exec -- task test`). `task doctor` reports missing
tools and version drift against `mise.toml`. `mise activate` sets `PATH` for the directory the shell started in and
only updates it at a prompt: a non-interactive `bash -ic 'cd <clone> && ./hack/test.sh'` started elsewhere (scripts,
agents) runs your global tool versions, so use `mise exec --` there. `hack/test.sh` prints any `DRIFT` first.

## Entrypoints

[`Taskfile.yml`](../Taskfile.yml) is the single entrypoint (via `mise`); `task --list` is the source of truth.

| Task | What |
|---|---|
| `setup` | `mise install` + helm-unittest plugin + git hooks |
| `doctor` | every tool from `mise.toml` present at the pinned version |
| `up` / `secrets` / `argocd` / `status` / `ui` / `down` | bootstrap stages (`INST=local` default; `task up INST=aws-example`) |
| `timings` | phase timings of the running stack: mgmt apps, each workload cluster provisioned and converged ([Bootstrap time](#bootstrap-time-and-registry-caches)) |
| `cache:status` / `cache:clean` | list / remove the host pull-through registry caches that `down` keeps ([Bootstrap time](#bootstrap-time-and-registry-caches)) |
| `kubeconfig CLUSTER=dev1` | host-usable kubeconfig of a CAPD workload cluster (see Docker Desktop below) |
| `set-repo REPO=https://github.com/<you>/platform.git` | point a fork at itself: `repoURL`, `githubOrg`, tenant app repos (`ORG=`, `APPS_ORG=`, `DOCS=1`; docs/forking.md) |
| `hooks:install` / `hooks:run` | install the git hooks / run every hook on every tracked file, as CI does ([Git hooks](#git-hooks)) |
| `lint` / `test` / `schemas` | offline validation (helm lint/template, kubeconform, helm-unittest, contract tests, shellcheck, actionlint) |
| `test:changed` | `test` for only what changed since `BASE` (default `origin/main`), as PR CI does ([Scoped PR CI](#scoped-pr-ci)) |
| `images:audit` | every image of the installation checked for linux/amd64 + linux/arm64 (`-- --live` adds running pods) |
| `tools:lock` | refresh `mise.lock` for all six platforms after editing `mise.toml` |
| `clean` | drop downloaded chart dependencies |

## Why mise + Task

- **mise** reads one file, installs prebuilt, checksum-verified binaries for each OS/arch, and activates them per
  directory. Every tool uses the **aqua** backend (upstream release assets; the aqua registry entry declares the
  supported platforms) except Python (mise core, python-build-standalone). `mise.lock` pins the exact URL + checksum
  for `linux-{x64,arm64}`, `macos-{x64,arm64}`, `windows-{x64,arm64}`. Renovate bumps `mise.toml` natively.
- **Task** is a single Go binary with its own POSIX shell interpreter, so `Taskfile.yml` runs unchanged as the single
  entrypoint on Linux, macOS and Windows (where Make is not installed by default).
- **Rejected**: Nix / devbox / flox (no native Windows; WSL only), asdf (plugins are shell scripts, no Windows),
  Homebrew bundles (macOS/Linux only), per-tool curl installers in scripts (amd64-Linux-only, no checksums, versions
  duplicated between CI and docs).

| Tool | Version | Backend | Why |
|---|---|---|---|
| kubectl | 1.35.10 | aqua:kubernetes/kubernetes/kubectl | matches k3s v1.35 on mgmt + workload clusters |
| helm | 4.3.2 | aqua:helm/helm | charts, lint, template; plugin `helm-unittest` 1.2.1 (postinstall hook) |
| helm-docs | 1.14.2 | aqua:norwoodj/helm-docs | generated chart `README.md` values tables (`task lint`, git hooks) |
| k3d | 5.8.3 | aqua:k3d-io/k3d | local mgmt cluster (5.9.0 exists; 5.8.3 is the version the live boot proved) |
| clusterctl | 1.13.8 | aqua:kubernetes-sigs/cluster-api | = CAPI core of `charts/cluster` |
| argocd | 3.6.1 | aqua:argoproj/argo-cd | = Argo CD server |
| yq / jq | 4.54.3 / 1.8.2 | aqua:mikefarah/yq / aqua:jqlang/jq | YAML/JSON in scripts |
| kubeconform | 0.8.0 | aqua:yannh/kubeconform | schema validation |
| crane | 0.22.1 | aqua:google/go-containerregistry | `images:audit` |
| cosign | 3.1.4 | aqua:sigstore/cosign | `demo:check` verifies the demo image's signature with the pinned identity |
| crossplane | 2.4.1 | aqua:crossplane/cli | `crossplane render` of the PostgreSQL Compositions (`hack/tests/test_crossplane_render.sh`; needs Docker, skips without) |
| shellcheck / actionlint | 0.11.0 / 1.7.12 | aqua | `task lint`, git hooks |
| gitleaks | 8.30.1 | aqua:gitleaks/gitleaks | secret scan in the git hooks / CI |
| prek | 0.5.10 | aqua:j178/prek | git hook runner (`prek.toml`) |
| kyverno | 1.20.0 | github:kyverno/kyverno | offline policy tests (`hack/tests/test_kyverno_policies.sh`) |
| python | 3.14.10 | core:python | `hack/crd2schema.py`, test helpers (stdlib only) |
| task | 3.54.0 | aqua:go-task/task | entrypoint |
| gh | 2.104.0 | aqua:cli/cli | `task secrets` falls back to `gh auth token` when no `GITHUB_APP_*` / `PLATFORM_GITHUB_TOKEN` is set |

Docker is the one prerequisite mise does not install (Docker Desktop, OrbStack, Colima, Rancher Desktop or Docker
Engine). Git Bash comes with Git for Windows.

## Git hooks

`task hooks:install` (part of `task setup` and the dev container's post-create; after a plain `mise install` run it
once, `task doctor` warns until you do) installs `pre-commit` and
`commit-msg` shims for this clone and all its worktrees. [prek](https://prek.j178.dev) runs [`prek.toml`](../prek.toml):

| Hook | Files | What |
|---|---|---|
| trailing-whitespace, end-of-file-fixer, mixed-line-ending (`--fix=lf`) | all text | fix in place; re-stage and commit again |
| check-merge-conflict, check-added-large-files (500 KB), check-case-conflict, check-illegal-windows-names | all | stray markers, big blobs, paths macOS/Windows cannot check out |
| check-yaml (`templates/` excluded: Go templates), check-toml, check-json | `*.yaml`, `*.toml`, `*.json` | syntax; check-toml also rejects duplicate keys in `mise.toml` |
| gitleaks | staged files (index content) | secrets; false positives get a `gitleaks:allow` comment on the line, not a broad ignore |
| shellcheck (`-x -P SCRIPTDIR`, as `task lint`), actionlint | `bootstrap/` `hack/` `.devcontainer/` `*.sh`, `.github/workflows/` | |
| py-compile | `*.py` | Python syntax |
| mise-tools-table | `mise.toml` | every `[tools]` entry parses for `task doctor` |
| chart-lock | `Chart.yaml` / `Chart.lock` | lock digest in sync (`hack/lib/chartlock.py`; skipped with a note until it is on `main`) |
| helm-docs | `charts/` `addons/` `Chart.yaml` / `values.yaml` / `README.md*`, `hack/helm-docs/` | `README.md` in sync with `helm-docs` (`hack/helm-docs/README.md.gotmpl` + per-chart `README.md.gotmpl`) |
| reference-docs | `packages/*/apis/` `packages/*/openchoreo/` `addons/openchoreo-platform/`, `hack/gen-reference.py`, `docs/reference/` | `docs/reference/` in sync with `hack/gen-reference.py` (regenerate: `task docs:reference`) |
| charts | `charts/` `addons/` `installations/` | `CHARTS=<changed charts> hack/test.sh`: helm lint + template per installation/cluster + kubeconform (cached schemas) + helm unittest of the changed charts only; installation/cluster files select `charts/platform` + `charts/cluster`. Everything else is `task test` / CI |
| conventional-commit | commit message | warns, never blocks: squash merges make the PR title the commit on `main` |

Nothing is downloaded at commit time: builtin hooks are compiled into prek, the rest run the `mise.toml` tools and
`hack/hooks.sh`. A typical commit takes about a second; touching an addon adds its renders (~8 s).
`hack/tests/test_hooks_config.sh` fails on a remote hook repo without a full commit SHA, a hook that would build its
own environment, or a tool not pinned in `mise.toml`.

**CI runs the same hooks** on every tracked file (`task hooks:run` in the `ci` and `portability` workflows, all four
OS/arch jobs and the dev container; only `charts` is skipped there because `task test` renders every chart). A scoped
pull request runs them on its changed files only ([Scoped PR CI](#scoped-pr-ci)). In an
emergency `git commit --no-verify` skips the hooks locally, and `SKIP=charts,gitleaks git commit` skips single hooks;
CI still fails the PR on any finding.

## Scoped PR CI

The `ci` workflow's `validate` job (the merge gate, it reports on every PR) validates only what a pull request touches.
[`hack/changed-units.sh`](../hack/changed-units.sh) maps the PR's changed files (`HEAD^1..HEAD` of the merge commit)
to units:

| Changed | Unit | PR CI runs |
|---|---|---|
| `charts/<c>/**`, `addons/<a>/**`, `installations/*/addons/<a>/**` | that chart | hooks on changed files, check-docs, helm lint + template x installations + kubeconform + helm-unittest of that chart, related contract tests |
| `packages/<p>/**` | `packages/<p>` | hooks, check-docs, related contract tests; the package's own workflow (path filter `packages/<p>/**`) renders and builds it |
| `ci/**`, `.github/workflows/app-*.yaml` / `ci-selftest.yaml` | `ci` | hooks, check-docs, related contract tests; `ci-selftest` builds the fixtures |
| `templates/**` | `templates` | hooks, check-docs, related contract tests; the `templates` workflow renders them |
| `docs/<d>`, `docs/<dir>/**`, or root `<d>.md` read by a contract test | `docs/<d>` / `<d>.md` | hooks on changed files, check-docs, related contract tests (e.g. `docs/data-services.md` -> `test_data_services`, `docs/openchoreo.md` / `README.md` -> `test_set_repo`, `docs/diagrams/**` -> `test_diagrams`) |
| only other `docs/**`, `wiki/**`, `*.md` outside charts | `docs` | hooks on changed files + check-docs |
| anything else | `full` | `task hooks:run lint test`, as before |

`full` covers the shared inputs: `hack/**`, `bootstrap/**`, `charts/platform/**` (catalog + ApplicationSets feed every
addon render), `charts/cluster/**`, `installations/*/installation.yaml` and `clusters/*`, `mise.toml`, `Taskfile.yml`,
`prek.toml`, `renovate.json`, `.github/workflows/ci.yaml` and the other workflows, and every path the script does not
know (when unsure: full). Push to `main`, `merge_group` and `workflow_dispatch` always run full. A contract test is
"related" when it names the unit's path (including after a `/` prefix like `$W/` or `$ROOT/` for docs), or, for charts
and addons, checks every chart (`addons/*`, `charts/*`, `$RENDERED_DIR`): `hack/changed-units.sh --tests addons/harbor`
lists them. A test that needs every render carries
`# scoped-ci full-if: <regex>`: the run goes full when a changed chart's files match, else the test waits for the full
run (`merge_group`, `main`). Keep that regex narrow and split the per-chart part out: `test_secret_store_scope.sh`
(stores, unused grants) goes full only for a chart that defines a store or workflow, while
`test_secret_store_scope_chart.sh` checks each rendered consumer in every scoped run, reading the store scope from
`hack/tests/fixtures/secret-store-scope.txt` when `addons/secret-stores` was not rendered. Example: an
`addons/cilium` PR renders 1 of 38 charts (plus `charts/platform` / `charts/cluster`) and runs 11 of 73 suites, about
1.5 min instead of 4.5 min locally. `task test:changed` (`BASE=<ref>`) gives you the same scope locally, uncommitted
files included; `task test` still runs everything. Fixtures: `hack/tests/test_changed_units.sh`.

## Portable bash rules

Scripts stay bash (Task calls them as `bash <script>`), written for **bash 3.2** (macOS default) and both GNU and BSD
userlands; helpers live in [`hack/lib/portable.sh`](../hack/lib/portable.sh).

| Avoid | Use |
|---|---|
| `mapfile` / `readarray`, `declare -A`, `${v,,}`, `&>>` | `while read` loops / `read_lines`, plain arrays, `tr`, `>> f 2>&1` |
| `"${arr[@]}"` on a possibly empty array under `set -u` (bash < 4.4: "unbound variable") | `${arr[@]+"${arr[@]}"}` |
| `sed -i` | `sed_inplace` (temp file; GNU and BSD disagree on `-i`) |
| `base64 -d` | `b64dec` |
| `sha1sum` | `sha1` (shasum on macOS) |
| `df -BG --output`, `readlink -f`, `date -d`, `grep -P`, `xargs -r`, `timeout` | `free_gb` (POSIX `df -Pk`), `cd && pwd`, explicit loops, `curl --connect-timeout` |
| `python3` | `pick_python` / `py` (Windows: `python3` is a Store alias; Python writes CRLF) |
| `/tmp/...` | `mktemp -d` |
| `xdg-open` | `open_url` (`open` / `start` / `wslview` / `xdg-open`) |
| MSYS paths handed to Go/Python binaries | `native_path` (`cygpath -m` on Windows) |
| `nproc` (GNU only) | `cpu_count` (`getconf` / `sysctl`) |
| a bare network call (`helm repo update`, chart downloads) | `retry_with_backoff <attempts> <delay> <command...>` |

`task lint` runs `bash -n` + shellcheck on every script; the macOS CI job runs the whole suite on `/bin/bash` 3.2.

`hack/test.sh` renders every chart once (step 5) and exports that directory as `RENDERED_DIR` to the suites in
`hack/tests/`. Suites take renders through `render_platform`, `render_cluster`, `render_standalone_addon` and
`render_layered_addon` (`hack/tests/lib.sh`): the `hack/test.sh` render of this run when present, else a fresh
`helm template` (a suite run on its own never reads an old render). The same file holds the rest a new suite needs:
`assert_eq`/`assert_match`/`assert_nonempty` + `finish` (the `N passed` line), `kc_valid` (kubeconform with the CRD
schemas, as `hack/test.sh` runs it), and a fake-tool harness: `fake_bin_yq` + `run_isolated` run a script against fakes
in `$BIN` with a scrubbed environment, `bootstrap_harness` lets a suite call single `bootstrap.sh` functions.
`hack/deps.sh` rebuilds only charts whose `charts/` differs from their `Chart.lock` (missing or extra tarballs, or a
tarball that differs from a digest pinned in the
`Chart.yaml` annotation `platform.koorikla.io/dependency-digests`) and retries downloads. It registers the https repositories
those charts use in a throwaway repository config (`HELM_REPOSITORY_CONFIG`), so a stale or retired repository in your
own helm config cannot fail it. CI caches the chart tarballs keyed on every `Chart.lock`.

## Host differences (Docker Desktop and friends)

The local topology (k3d mgmt + CAPD clusters on docker network `kind`) was designed on a Linux host. What changes
elsewhere:

| Topic | Linux host | Docker Desktop (macOS / Windows), OrbStack, Colima, WSL2 + Docker Desktop |
|---|---|---|
| Container IPs on `kind` (CAPD `<name>-kubeconfig`, node IPs) | routable from the host | **not routable** from the host. Inside Docker everything works unchanged (mgmt pods, agents, Argo CD reach the CAPD LB IP) |
| Workload cluster kubeconfig on the host | `task kubeconfig CLUSTER=dev1` keeps the LB IP | `task kubeconfig CLUSTER=dev1` rewrites the server to `127.0.0.1:<port the <name>-lb container publishes>` (a k3s cert SAN; `KUBECONFIG_MODE=published`) |
| App URLs on CAPD nodes (`*.dev1.apps.localhost:19080`, docs/openchoreo.md) | `curl --resolve ...:$NODE_IP` | run the client inside the network: `docker run --rm --network kind curlimages/curl:8.22.0 --resolve development-default.dev1.apps.localhost:19080:$NODE_IP http://development-default.dev1.apps.localhost:19080/hello-world-http/` |
| `127.0.0.1:8080/8443/9443/11080/11085/8200` (k3d LB) | published on loopback | published on the host loopback too (Docker Desktop forwards) |
| `/var/run/docker.sock` mounted into the k3d node (CAPD) | host socket | the VM's socket; Docker Desktop, OrbStack, Colima and Rancher Desktop all provide `/var/run/docker.sock` inside their VM. Native Windows k3d may reject the Unix path (use WSL2) |
| inotify limits (many k3s nodes) | `bootstrap.sh` warns below 524288 watches | limits live in the VM kernel: `docker run --rm --privileged alpine sysctl -w fs.inotify.max_user_watches=524288 fs.inotify.max_user_instances=8192` (resets when the VM restarts) |
| Resources | host RAM | give the VM >= 8 CPUs / 16 GB (Docker Desktop: Settings -> Resources) |
| `*.localhost` names (`openchoreo.localhost:8080`) | browsers and curl resolve to loopback | same in browsers and curl; other CLIs on macOS/Windows may need `/etc/hosts` / `C:\Windows\System32\drivers\etc\hosts` entries |

Not yet proven with a full `task up` on these hosts: [#60](https://github.com/koorikla/platform/issues/60).

## Local profiles

One installation (`installations/local`), two profiles. The fleet files are the switch: a file in
`installations/local/clusters/` is a cluster, and a `*.yaml.disabled` file is not (conventions invariant 7).

| Profile | Fleet files | Workload clusters | Host RAM (`docker stats`, reference host) |
|---|---|---|---|
| lean (default) | `dev1.yaml`, `prod1.yaml.disabled` | `dev1`: development, staging, production | mgmt ~8.1 GiB + dev1 ~4.3 GiB = **~12.4 GiB** |
| multicluster | `dev1.yaml`, `prod1.yaml` | `dev1`: development, staging; `prod1`: production | + prod1 ~3.4 GiB = **~15.8 GiB** |

`byo1.yaml.disabled` is a separate opt-in, not part of either profile: a plain k3d cluster registered as
`provider: byo` (~2.3 GiB; [providers.md](providers.md#bring-your-own-cluster-byo)).

Numbers are for single-server CAPD nodes (`controlPlane.replicas: 1`); mgmt varies between 7.6 and 8.4 GiB.

Switch to multicluster: rename the file and move `production` to it (an environment lives on exactly one enabled
cluster; `hack/tests/test_local_profiles.sh` checks both profiles):

```sh
git mv installations/local/clusters/prod1.yaml.disabled installations/local/clusters/prod1.yaml
yq -i '.openchoreo.dataPlane.environments -= ["production"]' installations/local/clusters/dev1.yaml
```

Back to lean is the reverse. Commit, PR, merge: the `fleet` ApplicationSet creates or deletes prod1 (the CAPI
Cluster is deleted gracefully; CAPD removes its containers).

Before the first `task up` those two lines are the whole switch. **On a running stack** `production` already exists as
an OpenChoreo `Environment`, whose `dataPlaneRef` is immutable, so it is deleted and created again on the other
cluster. OpenChoreo refuses to delete an Environment that `DeploymentPipeline default` references, its finalizer
deletes the environment's ReleaseBindings as OpenChoreo's controller (which the git-only gate denies for production,
[promotion.md](promotion.md)), and it cleans the namespaces through the old cluster's agent, so the old cluster must
still run. Two merges:
1. Move `production` between the fleet files (to dev1 for lean: `prod1.yaml` keeps `environments: []` and stays
   enabled) and add two temporary overrides to `installations/local/addons/openchoreo-platform/values.yaml`:
   `deploymentPipeline: {environments: [development, staging]}` and `promotion.gitOnly.deleters` plus
   `system:serviceaccount:openchoreo-control-plane:controller-manager` (DELETE only). Wait until the production
   ReleaseBinding is Ready on its new cluster (`kubectl -n default get releasebinding`). Argo CD recreates the binding
   while the Environment is still missing, and OpenChoreo 1.3.3 does not retry an `EnvironmentNotFound` binding: if it
   stays there after `kubectl -n default get environments` lists production again, delete the
   `openchoreo-control-plane` controller-manager pod (its restart reconciles every binding).
2. Remove both overrides and, for lean, rename `prod1.yaml` back to `prod1.yaml.disabled` with
   `environments: [production]`.

The move to lean ran live on the reference host; the move to multicluster is render-checked only (VERIFY).

What keeps working on one cluster:
- OpenChoreo isolates environments by namespace (`dp-<org>-<project>-<env>-<hash>`) and by host
  (`<env>-<org>.dev1.apps.localhost`).
- Promotion gates, freeze windows and git-only production bindings work on Environment names
  ([promotion.md](promotion.md)).
- Kyverno image verification selects cell namespaces by their `openchoreo.dev/environment` label: production is Deny
  on whichever cluster hosts it (the contract test renders the policies for every cluster and compares them).
- The mesh group `local` has one member; OpenBao's mesh reconcile configures just `dev1`.

What it gives up: the cluster boundary between production and the rest (one API server, etcd, node and kernel), the
flannel path (prod1 is the flannel cluster), and the cluster-level `environment` label (`development` on dev1, which
picks addon `env-<environment>.yaml` overlays) also covers production's namespaces.

## Local stack load and the mgmt datastore

On a busy host the local stack is limited by disk I/O, not CPU. Slow fsyncs stall etcd, and k3s exits when an embedded
controller misses a lease renewal (`leaderelection lost`). The settings below keep the clusters up on slow disks. They
work inside the containers, so Linux, macOS and Windows Docker hosts behave the same.

| Setting | Where | Why |
|---|---|---|
| Embedded etcd (`--cluster-init`) | `bootstrap/k3d-mgmt.yaml` | kine/SQLite compaction crash-looped a busy single-server mgmt ([#76](https://github.com/koorikla/platform/issues/76)). etcd compacts incrementally. |
| `--etcd-arg=unsafe-no-fsync=true` | `bootstrap/k3d-mgmt.yaml` | WAL fsyncs on the shared disk stalled etcd for over 8 s ([#344](https://github.com/koorikla/platform/issues/344)). |
| `CATTLE_ELECTION_LEASE_DURATION=120s`, `..._RENEW_DEADLINE=90s`, `..._RETRY_PERIOD=10s` | `bootstrap/k3d-mgmt.yaml` | k3s's own `k3s` and `k3s-etcd` leases. One server, so a long lease costs nothing. |
| 60 s leases, 40 s renew deadline for kube-controller-manager, scheduler, cloud-controller-manager | `bootstrap/k3d-mgmt.yaml`, ClusterClass `k3s-docker` (`k3s.dockerLeaderElectionArgs`) | Upstream 15 s / 10 s lost leader election on 5-8 s fsync stalls ([#82](https://github.com/koorikla/platform/issues/82)). |
| `--leaderElectionRetryPeriod=10s` (60 s lease, 50 s deadline) | `addons/kyverno` | Upstream 2 s restarted all Kyverno controllers on etcd stalls and rejected pods while admission was down. The build `sign` step also retries (`retryPolicy: OnError`). |

Trade-off: without fsync, a host or Docker VM crash can lose the last mgmt writes. Rebuild with `task down` and
`task up`, or restore a snapshot ([runbooks/backup-restore.md](runbooks/backup-restore.md)). k3d applies server args at
create time only, so a changed setting needs a new mgmt cluster. A CAPD cluster gets new args through a control-plane
rollout.

Check after a clean `task up` (every count stays 0, the lease shows 120):

```bash
docker inspect k3d-platform-mgmt-server-0 --format '{{.RestartCount}}'
docker logs k3d-platform-mgmt-server-0 2>&1 | grep -c 'leaderelection lost'
docker exec k3d-platform-mgmt-server-0 kubectl -n kube-system get lease k3s k3s-etcd \
  -o custom-columns=NAME:.metadata.name,LEASE:.spec.leaseDurationSeconds
kubectl --context k3d-platform-mgmt -n kyverno get lease
```

## Bootstrap time and registry caches

A clean `task up` on main @474e8af took 32.9 min to 43 Synced/Healthy apps (20-core host). Argo CD's timeline showed
where it went: ~100 images pulled from the internet each rebuild (mgmt pulls of 2-5 min each, dev1 ~90 s per wave),
apps waiting out a 5 min retry backoff after their missing CRD/webhook had appeared (cluster-fleet on mgmt retried at
5.3 then 10.3 min; keda/cloudnative-pg/crossplane on dev1 at 25.3 then 30.3 min), and dev1's addons idling ~8 min in
a comparison error because Argo CD registered dev1 before its API served and only retried on the 300 s resync.

What keeps it short now (#266: about 15 min warm, once the caches hold the images; a first boot stays at 20-30 min):
- **Host pull-through caches** (`hack/registry-cache.sh`): one `registry` container per upstream in
  `installation.yaml` `registry.hostCache.mirrors` (`platform-cache-<upstream, dots as dashes>`, network `kind`, named
  volume). They belong to no k3d cluster, so `task down` keeps them and a rebuild pulls from local disk. `task up`
  starts them and hands k3d a k3s `registries.yaml` mirroring each upstream to them; CAPD nodes get the same mirrors
  from charts/cluster (`capi-registries.yaml`, docker provider only) instead of Harbor's proxy projects for those
  upstreams. containerd falls back to the upstream when a cache is down. `REGISTRY_CACHE=0 task up` opts out (mgmt pulls
  direct, CAPD nodes keep Harbor); `task cache:clean` removes containers and volumes (several GiB: check `task
  cache:status` when disk runs low; below `REGISTRY_CACHE_MIN_FREE_GIB` (default 10) free on a native Linux Docker, `up` skips creating them).
- **Retry backoff capped at 1m** (ApplicationSets in charts/platform, tenant apps): unlimited retries stay (#199), the
  idle time after a dependency heals is at most a minute.
- **Argo CD resync 120 s** (upstream default; jitter 30 s) and upstream processor counts (status 20, operation 10).
- `task timings` prints the phases from Argo CD and CAPI timestamps (first successful sync per app), so a regression
  shows which phase grew:

```text
  mgmt apps converged           14.1 min  (26 apps, last tenant-demo)
  dev1 provisioned (API up)     13.2 min
  dev1 apps converged           32.1 min  (17 apps, last crossplane-dev1)
```

## Windows notes

- **Line endings**: `.gitattributes` forces LF for scripts, YAML, JSON, TOML and Markdown, so `core.autocrlf=true`
  (the Git for Windows default) cannot break bash or helm values. Re-normalize an old clone with
  `git add --renormalize . && git checkout -- .`.
- **Which bash**: Task resolves `bash` from `PATH`. From PowerShell/cmd that can be `C:\Windows\System32\bash.exe` (the
  WSL launcher). Run tasks from Git Bash, or set `BASH="C:\Program Files\Git\bin\bash.exe"`.
- **Python**: `python3` on a fresh Windows is a Microsoft Store alias that fails; scripts probe and use mise's
  `python`. Turn the alias off in *Settings -> Apps -> Advanced app settings -> App execution aliases* if it bothers you.
- **Paths**: Git Bash rewrites `/c/...` arguments for native programs; scripts pass `cygpath -m` paths
  (`native_path`). If you call tools by hand with Unix-looking arguments that are not paths (e.g. `kubectl exec -- /bin/sh`),
  prefix `MSYS_NO_PATHCONV=1`.
- **Symlinks**: `CLAUDE.md` and `GEMINI.md` are symlinks to `AGENTS.md`; without Developer Mode +
  `git config core.symlinks true` they check out as one-line text files (harmless).
- **Docker socket**: Docker Desktop's engine runs in WSL2 either way; the native path uses the `npipe` socket for the CLI
  and `/var/run/docker.sock` inside the engine VM for containers.

## CPU architecture: image audit

`task images:audit` renders every addon exactly as the ApplicationSets layer it for the installation (mgmt + every
cluster file), adds the k3d node/helper images, the CAPD node and load-balancer images, the CAPI provider controllers
(release components) and the k3s system images (`k3s-images.txt`), and asks the registry (crane) whether each image
publishes `linux/amd64` and `linux/arm64`.

Every image must publish both. The only accepted exceptions are listed, each with an expiry, in
`hack/image-audit.sh` `ARCH_EXCEPTIONS` (today: Harbor 2.15, [build-plane.md](build-plane.md#images-and-architectures));
the audit reports them as `EXCEPTION`. Images that are tag-only or not fully qualified:
[#45](https://github.com/koorikla/platform/issues/45).

Apps built by the ci/ workflows must publish multi-arch images too, or arm64 hosts will fail to run them on CAPD clusters.

## Updating a tool

1. Edit the version in `mise.toml` (or merge the Renovate PR).
2. `task tools:lock` (writes the six platform URLs + checksums into `mise.lock`), `mise install`, `task test`.
3. The `portability` workflow runs nightly on `main`, not on PRs; for a toolchain change trigger it on your branch
   with `gh workflow run portability --ref <branch>`.
