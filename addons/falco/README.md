# falco

## Purpose

Wrapper chart for Falco (`9.2.2` / `0.45.2`, modern eBPF), `falcosidekick` (`2.35.1`), and `falco-talon` (`0.5.0` / `0.3.0`). Detects runtime threats across `mgmt` and workload clusters, ships alerts to the telemetry collector on workload clusters, escalates `critical` alerts to `argo-events`, and runs Talon pod-level response actions in `dp-*` app namespaces.

## Where it runs

- **Roles / providers:** `roles: [mgmt, workload]`, all providers (`namespace: falco`; layers `values/role-mgmt.yaml` on `mgmt`).
- **Catalog label:** `addons.platform.koorikla.io/falco` (`default: true`, opt-out with `"false"`).

## Key values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cluster.name | string | `"default"` |  |
| escalation.enabled | bool | `true` | Pulls webhook secrets (`escalation.{enabled,remoteKey}` for `falco-webhook`, `slack.{enabled,remoteKey}` for `falco-slack`) via ESO. |
| escalation.remoteKey | string | `"falco-webhook"` |  |
| escalation.store | string | `""` |  |
| falco-talon.config.defaultNotifiers[0] | string | `"k8sevents"` |  |
| falco-talon.config.rulesOverride | string | `"- action: Platform label suspicious\n  actionner: kubernetes:label\n  parameters:\n    labels:\n      platform.koorikla.io/falco: suspicious\n\n- action: Platform terminate pod\n  actionner: kubernetes:terminate\n  parameters:\n    ignore_daemonsets: true\n    ignore_statefulsets: false\n    grace_period_seconds: 0\n\n# - action: Platform isolate pod      # Egress-only NetworkPolicy on the pod's owner: no egress at all (DNS too)\n#   actionner: kubernetes:networkpolicy\n#   parameters:                     # Talon 0.3: allow_cidr (CIDRs), allow_namespaces (names); both empty = deny\n#     allow_cidr: []\n\n- rule: Crypto miner in app namespace\n  description: Label and kill the pod (its controller recreates it; repeated hits stay visible in OpenSearch).\n  match:\n    rules:\n      - Platform crypto miner indicators\n  dry_run: false\n  actions:\n    - action: Platform label suspicious\n    - action: Platform terminate pod\n\n- rule: Shell in app container\n  description: Label only (an operator may be debugging); isolate by uncommenting the action below.\n  match:\n    rules:\n      - Platform shell in app container\n  dry_run: false\n  actions:\n    - action: Platform label suspicious\n    # - action: Platform isolate pod\n"` |  |
| falco-talon.enabled | bool | `true` | Enables Falco Talon (`config.rulesOverride` labels suspicious pods on app container shells and terminates pods matching crypto-miner rules). |
| falco-talon.image.pullPolicy | string | `"IfNotPresent"` |  |
| falco-talon.image.registry | string | `"docker.io"` |  |
| falco-talon.image.tag | string | `"0.3.0"` |  |
| falco-talon.rbac.caliconetworkpolicies | list | `[]` |  |
| falco-talon.rbac.ciliumnetworkpolicies | list | `[]` |  |
| falco-talon.rbac.clusterroles | list | `[]` |  |
| falco-talon.rbac.configmaps | list | `[]` |  |
| falco-talon.rbac.daemonsets | list | `[]` |  |
| falco-talon.rbac.deployments | list | `[]` |  |
| falco-talon.rbac.events[0] | string | `"get"` |  |
| falco-talon.rbac.events[1] | string | `"create"` |  |
| falco-talon.rbac.events[2] | string | `"update"` |  |
| falco-talon.rbac.events[3] | string | `"patch"` |  |
| falco-talon.rbac.leases[0] | string | `"get"` |  |
| falco-talon.rbac.leases[1] | string | `"create"` |  |
| falco-talon.rbac.leases[2] | string | `"update"` |  |
| falco-talon.rbac.leases[3] | string | `"patch"` |  |
| falco-talon.rbac.leases[4] | string | `"watch"` |  |
| falco-talon.rbac.namespaces | list | `[]` |  |
| falco-talon.rbac.networkpolicies[0] | string | `"get"` |  |
| falco-talon.rbac.networkpolicies[1] | string | `"create"` |  |
| falco-talon.rbac.networkpolicies[2] | string | `"update"` |  |
| falco-talon.rbac.networkpolicies[3] | string | `"patch"` |  |
| falco-talon.rbac.nodes | list | `[]` |  |
| falco-talon.rbac.podsEphemeralcontainers | list | `[]` |  |
| falco-talon.rbac.podsEviction[0] | string | `"get"` |  |
| falco-talon.rbac.podsEviction[1] | string | `"create"` |  |
| falco-talon.rbac.podsExec | list | `[]` |  |
| falco-talon.rbac.podsLog | list | `[]` |  |
| falco-talon.rbac.pods[0] | string | `"get"` |  |
| falco-talon.rbac.pods[1] | string | `"list"` |  |
| falco-talon.rbac.pods[2] | string | `"update"` |  |
| falco-talon.rbac.pods[3] | string | `"patch"` |  |
| falco-talon.rbac.pods[4] | string | `"delete"` |  |
| falco-talon.rbac.replicasets[0] | string | `"get"` |  |
| falco-talon.rbac.roles | list | `[]` |  |
| falco-talon.rbac.secrets | list | `[]` |  |
| falco-talon.rbac.statefulsets[0] | string | `"get"` |  |
| falco-talon.replicaCount | int | `1` |  |
| falco-talon.resources.limits.cpu | string | `"200m"` |  |
| falco-talon.resources.limits.memory | string | `"128Mi"` |  |
| falco-talon.resources.requests.cpu | string | `"10m"` |  |
| falco-talon.resources.requests.memory | string | `"32Mi"` |  |
| falco.collectors.containerEngine.engines.docker.enabled | bool | `false` |  |
| falco.collectors.containerEngine.engines.podman.enabled | bool | `false` |  |
| falco.collectors.kubernetes.enabled | bool | `false` |  |
| falco.customRules."platform-rules.yaml" | string | `"# Platform rules (koorikla/platform addons/falco). App namespaces = OpenChoreo data-plane namespaces\n# dp-<org>-<project>-<env>-<hash>. Talon acts on these rule names (falco-talon.config.rulesOverride).\n- list: platform_namespaces\n  items: [kube-system, kube-public, kube-node-lease, local-path-storage, falco, telemetry, obi, cert-manager,\n          external-secrets, argocd, fleet, capi-system, capi-operator-system, capd-system, caaph-system,\n          capi-k3s-bootstrap-system, capi-k3s-control-plane-system, capa-system, caph-system, thunder,\n          openchoreo-system, openchoreo-control-plane, openchoreo-data-plane, openchoreo-observability-plane,\n          openchoreo-workflow-plane, cilium, istio-system, kyverno, argo-events]\n- macro: platform_app_namespace\n  condition: (k8s.ns.name startswith \"dp-\")\n\n# CAPD (provider docker): each workload-cluster node IS a container (kindest/node image), so the node's own\n# processes (CNI installers copying binaries, mount, kubelet helpers) match upstream container rules such as\n# \"Drop and execute new binary in container\" at CRITICAL - an escalation storm on every new node. Only the node\n# image itself is excepted; containers started inside the node keep their own image and stay covered.\n- macro: platform_capd_node_container\n  condition: (container.image.repository endswith \"kindest/node\")\n- rule: Drop and execute new binary in container\n  condition: and not platform_capd_node_container\n  override:\n    condition: append\n\n# In-cluster builds (addon openchoreo-workflow-plane, Argo Workflows in OpenChoreo's workflows-<org> namespaces)\n# execute binaries they wrote themselves, which this rule reports at CRITICAL (= an escalation per build step):\n# rootless buildkitd extracts and runs its binfmt/qemu probe ($HOME/.local/tmp/qemu-check<n>/check) on start, and\n# `go test` runs the test binary it just compiled (/tmp/go-build<n>/b<n>/<pkg>.test). Measured on mgmt: these two\n# were every Critical alert from workflows-* pods. Each exception is the full tuple (namespace prefix, image, parent\n# process, binary path); any other dropped binary in the same pods, and the same binary anywhere else, still fires.\n- rule: Drop and execute new binary in container\n  exceptions:\n    - name: platform_build_dropped_binaries\n      fields: [k8s.ns.name, container.image.repository, proc.pname, proc.exepath]\n      comps: [startswith, =, =, glob]\n      values:\n        - [workflows-, docker.io/moby/buildkit, buildkitd, /home/user/.local/tmp/qemu-check*/check]\n        - [workflows-, docker.io/library/golang, go, /tmp/go-build*/b*/*.test]\n  override:\n    exceptions: append\n\n- rule: Platform shell in app container\n  desc: An interactive or scripted shell started inside a container of an OpenChoreo app namespace.\n  condition: >\n    spawned_process and container and platform_app_namespace\n    and proc.name in (ash, bash, csh, ksh, sh, tcsh, zsh, dash)\n  output: >\n    Shell in app container (ns=%k8s.ns.name pod=%k8s.pod.name container=%container.name shell=%proc.name\n    parent=%proc.pname cmdline=%proc.cmdline user=%user.name image=%container.image.repository)\n  priority: WARNING\n  tags: [platform, container, shell, mitre_execution, T1059]\n\n- rule: Platform write below etc\n  desc: A file below /etc opened for writing in a container outside the platform namespaces.\n  condition: >\n    open_write and container and fd.name startswith /etc/\n    and not k8s.ns.name in (platform_namespaces)\n    and not proc.name in (update-ca-certi, ca-certificates, nginx-entrypoi)\n  output: >\n    Write below /etc in container (file=%fd.name ns=%k8s.ns.name pod=%k8s.pod.name container=%container.name\n    proc=%proc.name cmdline=%proc.cmdline image=%container.image.repository)\n  priority: ERROR\n  tags: [platform, container, filesystem, mitre_persistence, T1543]\n\n- list: platform_miner_binaries\n  items: [xmrig, xmr-stak, minerd, cpuminer, ccminer, cgminer, bfgminer, ethminer, nbminer, t-rex, lolminer,\n          nanominer, phoenixminer, teamredminer, gminer, srbminer]\n- list: platform_miner_ports\n  items: [3333, 4444, 5555, 6666, 7777, 8888, 9999, 14433, 14444, 45560, 45700]\n- rule: Platform crypto miner indicators\n  desc: Known miner binary, stratum URL on the command line, or connection to a mining-pool port, in an app namespace.\n  condition: >\n    container and platform_app_namespace and (\n      (spawned_process and (proc.name in (platform_miner_binaries)\n        or proc.cmdline contains \"stratum+tcp\" or proc.cmdline contains \"stratum+ssl\"\n        or proc.cmdline contains \"stratum2+tcp\"))\n      or (outbound and fd.sport in (platform_miner_ports))\n    )\n  output: >\n    Crypto miner indicator (ns=%k8s.ns.name pod=%k8s.pod.name container=%container.name proc=%proc.name\n    cmdline=%proc.cmdline connection=%fd.name image=%container.image.repository)\n  priority: CRITICAL\n  tags: [platform, container, cryptomining, mitre_impact, T1496]"` |  |
| falco.driver.enabled | bool | `true` |  |
| falco.driver.kind | string | `"modern_ebpf"` | `modern_ebpf` (`loader.enabled: false`). |
| falco.driver.loader.enabled | bool | `false` |  |
| falco.falco.http_output.enabled | bool | `true` |  |
| falco.falco.http_output.url | string | `"http://falco-falcosidekick:2801"` |  |
| falco.falco.json_include_output_property | bool | `true` |  |
| falco.falco.json_include_tags_property | bool | `true` |  |
| falco.falco.json_output | bool | `true` |  |
| falco.falco.priority | string | `"notice"` |  |
| falco.falcoctl.image.tag | string | `"0.14.3@sha256:2230fb4802aafe09455b58d38f8f1faedd8f09f042e9a18fffd397e63488c023"` |  |
| falco.falcosidekick.config.cloudevents.address | string | `"http://telemetry-collector.telemetry.svc.cluster.local:8088/falco"` |  |
| falco.falcosidekick.config.cloudevents.minimumpriority | string | `"notice"` |  |
| falco.falcosidekick.config.customfields | string | `""` | Tags events with `cluster:<name>` (`clusterNameFormats`), forwards to `telemetry-collector` and `falco-talon`, and escalates `critical` events via `falcosidekick-escalation`. |
| falco.falcosidekick.config.extraEnv[0].name | string | `"WEBHOOK_ADDRESS"` |  |
| falco.falcosidekick.config.extraEnv[0].valueFrom.secretKeyRef.key | string | `"WEBHOOK_ADDRESS"` |  |
| falco.falcosidekick.config.extraEnv[0].valueFrom.secretKeyRef.name | string | `"falcosidekick-escalation"` |  |
| falco.falcosidekick.config.extraEnv[0].valueFrom.secretKeyRef.optional | bool | `true` |  |
| falco.falcosidekick.config.extraEnv[1].name | string | `"WEBHOOK_CUSTOMHEADERS"` |  |
| falco.falcosidekick.config.extraEnv[1].valueFrom.secretKeyRef.key | string | `"WEBHOOK_CUSTOMHEADERS"` |  |
| falco.falcosidekick.config.extraEnv[1].valueFrom.secretKeyRef.name | string | `"falcosidekick-escalation"` |  |
| falco.falcosidekick.config.extraEnv[1].valueFrom.secretKeyRef.optional | bool | `true` |  |
| falco.falcosidekick.config.extraEnv[2].name | string | `"SLACK_WEBHOOKURL"` |  |
| falco.falcosidekick.config.extraEnv[2].valueFrom.secretKeyRef.key | string | `"SLACK_WEBHOOKURL"` |  |
| falco.falcosidekick.config.extraEnv[2].valueFrom.secretKeyRef.name | string | `"falcosidekick-outputs"` |  |
| falco.falcosidekick.config.extraEnv[2].valueFrom.secretKeyRef.optional | bool | `true` |  |
| falco.falcosidekick.config.extraEnv[3].name | string | `"SLACK_MINIMUMPRIORITY"` |  |
| falco.falcosidekick.config.extraEnv[3].valueFrom.secretKeyRef.key | string | `"SLACK_MINIMUMPRIORITY"` |  |
| falco.falcosidekick.config.extraEnv[3].valueFrom.secretKeyRef.name | string | `"falcosidekick-outputs"` |  |
| falco.falcosidekick.config.extraEnv[3].valueFrom.secretKeyRef.optional | bool | `true` |  |
| falco.falcosidekick.config.otlp.metrics.checkcert | bool | `false` |  |
| falco.falcosidekick.config.otlp.metrics.endpoint | string | `"http://telemetry-collector.telemetry.svc.cluster.local:4317"` |  |
| falco.falcosidekick.config.otlp.metrics.minimumpriority | string | `"notice"` |  |
| falco.falcosidekick.config.otlp.metrics.protocol | string | `"grpc"` |  |
| falco.falcosidekick.config.talon.address | string | `"http://falco-talon:2803"` |  |
| falco.falcosidekick.config.talon.minimumpriority | string | `"warning"` |  |
| falco.falcosidekick.config.webhook.minimumpriority | string | `"critical"` |  |
| falco.falcosidekick.enabled | bool | `true` |  |
| falco.falcosidekick.fullnameOverride | string | `"falco-falcosidekick"` |  |
| falco.falcosidekick.image.tag | string | `"2.35.1@sha256:a9bb60d2c7742febd912315ca1155839abc0199bf322c58d3adbb8b0849fadb9"` |  |
| falco.falcosidekick.replicaCount | int | `1` |  |
| falco.falcosidekick.resources.limits.cpu | string | `"200m"` |  |
| falco.falcosidekick.resources.limits.memory | string | `"128Mi"` |  |
| falco.falcosidekick.resources.requests.cpu | string | `"10m"` |  |
| falco.falcosidekick.resources.requests.memory | string | `"32Mi"` |  |
| falco.falcosidekick.webui.enabled | bool | `false` |  |
| falco.fullnameOverride | string | `"falco"` |  |
| falco.image.tag | string | `"0.45.2@sha256:1562a643953f938e02f47319b5214d93a235f11f646d60e9b8a516fd5a64698e"` |  |
| falco.resources.limits.cpu | string | `"1"` |  |
| falco.resources.limits.memory | string | `"768Mi"` |  |
| falco.resources.requests.cpu | string | `"50m"` |  |
| falco.resources.requests.memory | string | `"192Mi"` |  |
| falco.responseActions.enabled | bool | `false` |  |
| falco.tty | bool | `false` |  |
| secretStore | string | `"default"` |  |
| slack.enabled | bool | `false` |  |
| slack.minimumPriority | string | `"warning"` |  |
| slack.remoteKey | string | `"falco-slack"` |  |

### Design notes

- **Falco 0.45** (chart 9.2.2), driver `modern_ebpf` (CO-RE: no kernel module, no driver loader), default rules + platform rules. JSON alerts go to stdout (Fluent Bit -> OpenSearch on mgmt) and over HTTP to falcosidekick.
- **falcosidekick outputs:** `talon` -> Falco Talon (actions on app namespaces `dp-*`); `cloudevents` -> telemetry collector logs pipeline; `otlp.metrics` -> collector metrics pipeline (alert counters -> Prometheus on mgmt); `webhook` -> escalation endpoint on mgmt (addon argo-events, `POST /falco/<cluster>` with the cluster's own token, >= critical); `slack` off until `slack.enabled`.
- **Falco Talon 0.3** (chart 0.5.0, workload clusters only): crypto miner -> label + terminate; shell in an app container -> label only.
- **Local caveat:** k3d/CAPD node containers share the host kernel, so every cluster's Falco sees every container on the machine (others without k8s metadata). On real nodes each Falco sees its own node.

## Day-2 notes

- Responding to critical Falco alerts and rotating webhook tokens: [incidents](../../docs/runbooks/incidents.md#falco-critical-alert) and [certificates and secrets](../../docs/runbooks/certificates-and-secrets.md#6-eso-backed-platform-and-workload-secrets).

## Links

- [Observability: Falco](../../docs/observability.md#falco)