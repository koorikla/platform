# harbor

## Purpose

Wrapper chart for Harbor (`1.19.4` / `v2.15.4`) on `mgmt`. Hosts the `apps` project for in-cluster builds and upstream pull-through proxy caches (`dockerhub`, `ghcr`, `quay`, `k8s`, `openchoreo`, `gcr`) for cluster nodes, with TLS from a `mgmt`-local CA and declarative project reconciliation.

## Where it runs

- **Roles / providers:** `roles: [mgmt]`, all providers (`namespace: harbor`).
- **Catalog label:** `addons.platform.koorikla.io/harbor` (`default: true`; cloud/external-registry installations set `mgmt.addons.harbor: "false"`).

## Key values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| caPublic.namespaceRegexes[0] | string | `"^workflows-.+$"` |  |
| caPublic.namespaces[0] | string | `"fleet"` |  |
| caPublic.secretName | string | `"harbor-ca-bundle"` |  |
| caPublic.store | string | `"mgmt-harbor"` |  |
| cluster.name | string | `"mgmt"` |  |
| config.apps.autoScan | bool | `true` |  |
| config.apps.contentTrustCosign | bool | `false` |  |
| config.apps.preventVulnerable | bool | `false` |  |
| config.apps.severity | string | `"critical"` |  |
| config.coreURL | string | `"http://harbor-core"` |  |
| config.endpoints."cr.openchoreo.dev".type | string | `"docker-registry"` |  |
| config.endpoints."cr.openchoreo.dev".url | string | `"https://cr.openchoreo.dev"` |  |
| config.endpoints."docker.io".type | string | `"docker-hub"` |  |
| config.endpoints."docker.io".url | string | `"https://hub.docker.com"` |  |
| config.endpoints."gcr.io".type | string | `"docker-registry"` |  |
| config.endpoints."gcr.io".url | string | `"https://gcr.io"` |  |
| config.endpoints."ghcr.io".credentials | string | `"ghcr"` |  |
| config.endpoints."ghcr.io".type | string | `"github-ghcr"` |  |
| config.endpoints."ghcr.io".url | string | `"https://ghcr.io"` |  |
| config.endpoints."quay.io".type | string | `"docker-registry"` |  |
| config.endpoints."quay.io".url | string | `"https://quay.io"` |  |
| config.endpoints."registry.k8s.io".type | string | `"docker-registry"` |  |
| config.endpoints."registry.k8s.io".url | string | `"https://registry.k8s.io"` |  |
| config.image | string | `"docker.io/library/python:3.14.10-alpine3.24@sha256:5862d971d1f0ae26b258cefa4e893556b1d3aba81bd2ff30888704ad378bab67"` |  |
| config.replication[0].cron | string | `"0 0 */6 * * *"` |  |
| config.replication[0].destProject | string | `"apps-ghcr"` |  |
| config.replication[0].enabled | bool | `true` |  |
| config.replication[0].endpoint | string | `"ghcr.io"` |  |
| config.replication[0].filters[0].type | string | `"name"` |  |
| config.replication[0].filters[0].value | string | `"koorikla/**"` |  |
| config.replication[0].filters[1].type | string | `"tag"` |  |
| config.replication[0].filters[1].value | string | `"**"` |  |
| config.replication[0].name | string | `"ghcr-koorikla"` |  |
| config.resources.limits.cpu | string | `"200m"` |  |
| config.resources.limits.memory | string | `"128Mi"` |  |
| config.resources.requests.cpu | string | `"10m"` |  |
| config.resources.requests.memory | string | `"32Mi"` |  |
| config.robots[0].description | string | `"OpenChoreo workflow plane builds (push to apps)"` |  |
| config.robots[0].name | string | `"builder"` |  |
| config.robots[0].pull[0] | string | `"apps-ghcr"` |  |
| config.robots[0].pull[1] | string | `"proxyCache"` |  |
| config.robots[0].push[0] | string | `"apps"` |  |
| config.robots[0].secretProperty | string | `"builder-secret"` |  |
| config.robots[1].description | string | `"Node image pulls (k3s registries.yaml)"` |  |
| config.robots[1].name | string | `"nodes"` |  |
| config.robots[1].pull[0] | string | `"apps"` |  |
| config.robots[1].pull[1] | string | `"apps-ghcr"` |  |
| config.robots[1].pull[2] | string | `"proxyCache"` |  |
| config.robots[1].push | list | `[]` |  |
| config.robots[1].secretProperty | string | `"nodes-secret"` |  |
| config.schedule | string | `"17 * * * *"` |  |
| config.storageLimitGiB | int | `-1` |  |
| gateway.className | string | `"kgateway"` |  |
| gateway.name | string | `"harbor"` |  |
| gateway.requestTimeout | string | `"30m"` |  |
| gateway.routeName | string | `"harbor-route"` |  |
| gateway.streamIdleTimeout | string | `"5m"` |  |
| harbor.cache.enabled | bool | `false` |  |
| harbor.core.existingSecret | string | `"harbor-platform"` |  |
| harbor.core.existingXsrfSecret | string | `"harbor-platform"` |  |
| harbor.core.existingXsrfSecretKey | string | `"CSRF_KEY"` |  |
| harbor.core.image.repository | string | `"docker.io/goharbor/harbor-core"` |  |
| harbor.core.image.tag | string | `"v2.15.4@sha256:7d2ba5304a729887cdec7cb222a82b500278423de230ae5150c386a6c332b112"` |  |
| harbor.core.replicas | int | `1` |  |
| harbor.core.resources.limits.cpu | string | `"1"` |  |
| harbor.core.resources.limits.memory | string | `"512Mi"` |  |
| harbor.core.resources.requests.cpu | string | `"50m"` |  |
| harbor.core.resources.requests.memory | string | `"128Mi"` |  |
| harbor.core.secretName | string | `"harbor-token"` |  |
| harbor.database.external.existingSecret | string | `"harbor-platform"` |  |
| harbor.database.internal.extraEnvVars[0].name | string | `"POSTGRES_PASSWORD"` |  |
| harbor.database.internal.extraEnvVars[0].valueFrom.secretKeyRef.key | string | `"POSTGRES_PASSWORD"` |  |
| harbor.database.internal.extraEnvVars[0].valueFrom.secretKeyRef.name | string | `"harbor-platform"` |  |
| harbor.database.internal.image.repository | string | `"docker.io/goharbor/harbor-db"` |  |
| harbor.database.internal.image.tag | string | `"v2.15.4@sha256:a32d51e636d76303e086a7c5251a2c8415c6f165b2f87bafa914efd866c5403f"` |  |
| harbor.database.internal.password | string | `"set-from-secret-harbor-platform"` |  |
| harbor.database.internal.resources.limits.cpu | string | `"1"` |  |
| harbor.database.internal.resources.limits.memory | string | `"512Mi"` |  |
| harbor.database.internal.resources.requests.cpu | string | `"25m"` |  |
| harbor.database.internal.resources.requests.memory | string | `"128Mi"` |  |
| harbor.database.internal.shmSizeLimit | string | `"128Mi"` |  |
| harbor.database.type | string | `"internal"` |  |
| harbor.existingSecretAdminPassword | string | `"harbor-platform"` |  |
| harbor.existingSecretAdminPasswordKey | string | `"HARBOR_ADMIN_PASSWORD"` |  |
| harbor.existingSecretSecretKey | string | `"harbor-platform"` |  |
| harbor.expose.route.hosts[0] | string | `"harbor.openchoreo.localhost"` |  |
| harbor.expose.route.parentRefs[0].group | string | `"gateway.networking.k8s.io"` |  |
| harbor.expose.route.parentRefs[0].kind | string | `"Gateway"` |  |
| harbor.expose.route.parentRefs[0].name | string | `"harbor"` |  |
| harbor.expose.route.parentRefs[0].sectionName | string | `"https"` |  |
| harbor.expose.tls.certSource | string | `"none"` |  |
| harbor.expose.tls.enabled | bool | `true` |  |
| harbor.expose.type | string | `"route"` |  |
| harbor.externalURL | string | `"https://harbor.openchoreo.localhost:9443"` |  |
| harbor.ipFamily.ipv6.enabled | bool | `false` |  |
| harbor.jobservice.existingSecret | string | `"harbor-platform"` |  |
| harbor.jobservice.existingSecretKey | string | `"JOBSERVICE_SECRET"` |  |
| harbor.jobservice.image.repository | string | `"docker.io/goharbor/harbor-jobservice"` |  |
| harbor.jobservice.image.tag | string | `"v2.15.4@sha256:f143578ef30e2be5c48873298257ed0fca31545025958c534e536a06765d2b82"` |  |
| harbor.jobservice.replicas | int | `1` |  |
| harbor.jobservice.resources.limits.cpu | string | `"500m"` |  |
| harbor.jobservice.resources.limits.memory | string | `"256Mi"` |  |
| harbor.jobservice.resources.requests.cpu | string | `"20m"` |  |
| harbor.jobservice.resources.requests.memory | string | `"64Mi"` |  |
| harbor.metrics.enabled | bool | `false` |  |
| harbor.persistence.enabled | bool | `true` |  |
| harbor.persistence.persistentVolumeClaim.database.size | string | `"2Gi"` |  |
| harbor.persistence.persistentVolumeClaim.jobservice.jobLog.size | string | `"1Gi"` |  |
| harbor.persistence.persistentVolumeClaim.redis.size | string | `"1Gi"` |  |
| harbor.persistence.persistentVolumeClaim.registry.size | string | `"20Gi"` |  |
| harbor.persistence.persistentVolumeClaim.trivy.size | string | `"2Gi"` |  |
| harbor.persistence.resourcePolicy | string | `"keep"` |  |
| harbor.portal.image.repository | string | `"docker.io/goharbor/harbor-portal"` |  |
| harbor.portal.image.tag | string | `"v2.15.4@sha256:01edf478505b21dba23a83c095f6ecac0c1e705690093edbab41e9a4d6754a75"` |  |
| harbor.portal.replicas | int | `1` |  |
| harbor.portal.resources.limits.cpu | string | `"100m"` |  |
| harbor.portal.resources.limits.memory | string | `"64Mi"` |  |
| harbor.portal.resources.requests.cpu | string | `"10m"` |  |
| harbor.portal.resources.requests.memory | string | `"32Mi"` |  |
| harbor.redis.internal.image.repository | string | `"docker.io/goharbor/valkey-photon"` |  |
| harbor.redis.internal.image.tag | string | `"v2.15.4@sha256:bb022e8f236f56f53cee7bb1f609595e497da67d829048e0af2284f97e6eb54f"` |  |
| harbor.redis.internal.resources.limits.cpu | string | `"200m"` |  |
| harbor.redis.internal.resources.limits.memory | string | `"128Mi"` |  |
| harbor.redis.internal.resources.requests.cpu | string | `"10m"` |  |
| harbor.redis.internal.resources.requests.memory | string | `"32Mi"` |  |
| harbor.redis.type | string | `"internal"` |  |
| harbor.registry.controller.image.repository | string | `"docker.io/goharbor/harbor-registryctl"` |  |
| harbor.registry.controller.image.tag | string | `"v2.15.4@sha256:30bd1ace4e3bb390d75b84673f98ddb4a69fcc6d116932ea764391df01943fb7"` |  |
| harbor.registry.controller.resources.limits.cpu | string | `"200m"` |  |
| harbor.registry.controller.resources.limits.memory | string | `"128Mi"` |  |
| harbor.registry.controller.resources.requests.cpu | string | `"10m"` |  |
| harbor.registry.controller.resources.requests.memory | string | `"32Mi"` |  |
| harbor.registry.credentials.existingSecret | string | `"harbor-platform"` |  |
| harbor.registry.existingSecret | string | `"harbor-platform"` |  |
| harbor.registry.existingSecretKey | string | `"REGISTRY_HTTP_SECRET"` |  |
| harbor.registry.registry.image.repository | string | `"docker.io/goharbor/registry-photon"` |  |
| harbor.registry.registry.image.tag | string | `"v2.15.4@sha256:dc0cb388a6445c69c8a0c406679290d2991c9698833d9e6e86a23bdfaf2f83c3"` |  |
| harbor.registry.registry.resources.limits.cpu | string | `"1"` |  |
| harbor.registry.registry.resources.limits.memory | string | `"512Mi"` |  |
| harbor.registry.registry.resources.requests.cpu | string | `"20m"` |  |
| harbor.registry.registry.resources.requests.memory | string | `"64Mi"` |  |
| harbor.registry.replicas | int | `1` |  |
| harbor.trace.enabled | bool | `false` |  |
| harbor.trivy.enabled | bool | `true` |  |
| harbor.trivy.image.repository | string | `"docker.io/goharbor/trivy-adapter-photon"` |  |
| harbor.trivy.image.tag | string | `"v2.15.4@sha256:813ca81b4a4ea0f44f5fa81cca2645eeb58d4b1f6c66b428df9d506174bb71d9"` |  |
| harbor.trivy.replicas | int | `1` |  |
| harbor.trivy.resources.limits.cpu | string | `"1"` |  |
| harbor.trivy.resources.limits.memory | string | `"1Gi"` |  |
| harbor.trivy.resources.requests.cpu | string | `"50m"` |  |
| harbor.trivy.resources.requests.memory | string | `"192Mi"` |  |
| pki.caDuration | string | `"87600h"` |  |
| pki.caIssuer | string | `"harbor-ca"` | Issues `harbor-tls` (`pki.{caIssuer,tlsSecret}`), exposes Harbor via `gateway.{name,className}` (`kgateway`), and exports the public CA via `ClusterSecretStore/mgmt-harbor`. |
| pki.tlsSecret | string | `"harbor-tls"` |  |
| pki.tokenSecret | string | `"harbor-token"` |  |
| registry.appsProject | string | `"apps"` |  |
| registry.host | string | `"harbor.openchoreo.localhost:9443"` |  |
| registry.proxyCache[0].project | string | `"dockerhub"` |  |
| registry.proxyCache[0].upstream | string | `"docker.io"` |  |
| registry.proxyCache[1].project | string | `"ghcr"` |  |
| registry.proxyCache[1].upstream | string | `"ghcr.io"` |  |
| registry.proxyCache[2].project | string | `"quay"` |  |
| registry.proxyCache[2].upstream | string | `"quay.io"` |  |
| registry.proxyCache[3].project | string | `"k8s"` |  |
| registry.proxyCache[3].upstream | string | `"registry.k8s.io"` |  |
| registry.proxyCache[4].project | string | `"openchoreo"` |  |
| registry.proxyCache[4].upstream | string | `"cr.openchoreo.dev"` |  |
| registry.proxyCache[5].project | string | `"gcr"` |  |
| registry.proxyCache[5].upstream | string | `"gcr.io"` |  |
| registry.type | string | `"harbor"` | Registry mode, `host` (`harbor.externalURL` via `installationParameters`), `appsProject`, and upstream `proxyCache` projects. |
| secrets.ghcrKey | string | `""` |  |
| secrets.remoteKey | string | `"harbor"` |  |
| secrets.secretName | string | `"harbor-platform"` |  |
| secrets.store | string | `"platform"` | Pulls Harbor admin, robot, and component credentials (`secrets.{store,remoteKey,ghcrKey,secretName}`) from `ClusterSecretStore/platform`. |

### Design notes

| Object | What it is |
|---|---|
| `harbor` (upstream chart) | HTTPRoute (`expose.type: route`), core, portal, jobservice, registry, internal PostgreSQL + Redis, Trivy (scan on push). No notary/exporter/metrics. |
| `templates/gateway.yaml` | Gateway `harbor` (HTTPS 9443, TLS terminated) + timeouts for the chart HTTPRoute |
| `templates/pki.yaml` | Registry CA scoped to ns harbor (Issuer `harbor-ca`) -> `harbor-tls`; `harbor-token` (core token-signing cert); `harbor-ca-bundle` (ca.crt only) |
| `templates/ca-store.yaml` | ClusterSecretStore `mgmt-harbor`: name-scoped GET of `harbor-ca-bundle` only (for CAPI node bootstrap data and build pods; no private key is read) |
| `templates/secrets.yaml` | Secret `harbor-platform` from ClusterSecretStore `platform` (key `harbor`, plus `platform-ghcr`) |
| `templates/config.yaml` | Harbor has no CRDs: a PostSync Job + CronJob apply `files/harbor-config.py` to the desired state in `config` (projects, proxy caches, replication, robot accounts, empty CVE allowlist). Idempotent. |

- **Images:** Harbor v2.15 publishes linux/amd64 only. On arm64 hosts set `registry.type: external` and disable this addon ([Registry](../../docs/build-plane.md)).
- **Endpoint** `https://<registry.host>`, e.g. `https://harbor.openchoreo.localhost:9443`. Harbor's token realm is `externalURL`, so the same name must resolve everywhere:
  - host browser: k3d publishes 127.0.0.1:9443 -> klipper hostPort of the Gateway Service;
  - mgmt pods: coredns-local rewrites the name to `harbor.harbor.svc.cluster.local`;
  - CAPD nodes: `/etc/hosts` alias to the k3d serverlb (ClusterClass variable `registryHostAlias`); k3s `registries.yaml` trusts the CA.

## Day-2 notes

- Values are checked by `values.schema.json` (`registry.host` format, `secrets.store` and other platform keys; `helm` prints the failing path). `registry.type` other than `harbor` and cross-field rules (upstream literals vs `registry.host`, gateway, token Secret, proxy-cache endpoints) are in `templates/validate.yaml`.
- Database/blob backups and node registry secret recovery: [backup and restore](../../docs/runbooks/backup-restore.md#5-harbor-harbor) and [break-glass](../../docs/runbooks/break-glass.md#blocked-cluster-sync-on-node-registry-secret).

## Links

- [Build plane: Harbor](../../docs/build-plane.md#registry-harbor)