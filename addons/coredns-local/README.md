# coredns-local

## Purpose

Renders k3s `coredns-custom` `ConfigMap` rules so pods inside local Docker (`k3d` and CAPD) clusters resolve `*.openchoreo.localhost` (and local observability/Harbor hosts on `mgmt`) to in-cluster Gateway Services or `k3d-platform-mgmt-serverlb`.

## Where it runs

- **Roles / providers:** `roles: [mgmt, workload]`, `providers: [docker, byo]` (`namespace: kube-system`; layers `values/role-<role>.yaml`). On byo clusters `enabled: false` (`values/provider-byo.yaml`) unless the installation turns it on: `installations/local/addons/coredns-local/values.yaml` does, its byo k3d clusters share network `kind`.
- **Catalog label:** `addons.platform.koorikla.io/coredns-local` (`default: true`, opt-out with `"false"`).

## Key values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | `true` |  |
| observabilityRewrite.target | string | `""` | Optional `mgmt` CNAME rewrite for observability (alongside `registryRewrite.target` for Harbor when `registry.type: harbor`). |
| openchoreo.controlPlane.host | string | `"openchoreo.localhost"` | Control-plane base domain (`openchoreo.localhost`). |
| openchoreo.observability.enabled | bool | `false` |  |
| registry.host | string | `""` |  |
| registry.type | string | `"external"` |  |
| registryRewrite.target | string | `""` |  |
| rewrite.target | string | `"k3d-platform-mgmt-serverlb"` | `gateway-default.openchoreo-control-plane.svc.cluster.local` on `mgmt`; `k3d-platform-mgmt-serverlb` on CAPD workload clusters. |

### Design notes

k3s's CoreDNS imports the optional ConfigMap `kube-system/coredns-custom` (`*.override` keys go into the `.:53` block, `*.server` become extra blocks); k3s does not own it, so Argo CD can. Every name under `openchoreo.controlPlane.host` (and the host itself) is answered with the address of `rewrite.target`; `answer auto` renames the answer back. The regex is anchored on the FQDN, so search-path expansions and look-alikes pass through. Pods and browsers use the same URLs: `http(s)://<x>.openchoreo.localhost:8080|8443`.

| Names | mgmt | workload |
|---|---|---|
| `*.<host>` | control-plane Gateway Service (`rewrite` runs before the `kubernetes` plugin) | k3d serverlb of mgmt on docker network `kind` (publishes 8080/8443) |
| `observer.<host>`, `*.observability.<host>` (with `openchoreo.observability.enabled`) | `observabilityRewrite.target`, placed first (`rewrite stop`: first match wins) | generic rule (serverlb publishes 11080/11085) |
| registry host (`registry.type: harbor`) | `registryRewrite.target`, Harbor's Gateway Service, first rule | generic rule; containerd on CAPD nodes uses an `/etc/hosts` alias instead (`registryHostAlias`) |

## Day-2 notes

- Debugging local agent or gateway DNS resolution: [incidents](../../docs/runbooks/incidents.md#data-plane-agent-disconnected).

## Links

- [OpenChoreo: Local networking](../../docs/openchoreo.md#local-networking)