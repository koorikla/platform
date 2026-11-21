# thunder

## Purpose

Wrapper chart for ThunderID (`1.0.1`). Runs OpenChoreo's OIDC identity provider on `mgmt`, serving console, API, CLI, observer, promotion-gate, and opt-in AI agent OAuth clients over the control-plane `Gateway`, backed by delete-protected PVCs.

## Where it runs

- **Roles / providers:** `roles: [mgmt]`, all providers (`namespace: thunder`).
- **Catalog label:** `addons.platform.koorikla.io/thunder` (`default: true`, opt-out with `"false"`).

## Key values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| bootstrapSecret.aiAgentClients | list | `[]` |  |
| bootstrapSecret.aiRemoteKey | string | `"openchoreo-ai"` |  |
| bootstrapSecret.name | string | `"thunder-bootstrap"` |  |
| bootstrapSecret.observabilityRemoteKey | string | `"openchoreo-observability"` |  |
| bootstrapSecret.promotionGate.property | string | `"client-secret"` |  |
| bootstrapSecret.promotionGate.remoteKey | string | `"promotion-gate"` |  |
| bootstrapSecret.remoteKey | string | `"openchoreo"` |  |
| bootstrapSecret.store | string | `"platform"` | Pulls OIDC client and admin secrets (`bootstrapSecret.{store,remoteKey,observabilityRemoteKey,promotionGate}`) from `ClusterSecretStore/platform` into `thunder-bootstrap`. |
| openchoreo | object | `{"controlPlane":{"host":"openchoreo.localhost"}}` | - installation.yaml (defaults so `helm template` works standalone); templates/validate.yaml checks the hostname - |
| thunderid.bootstrap.scripts."48-csp.yaml" | string | `"resource_type: server_config\nname: csp\nvalue:\n  paths:\n    - location: \"/gate/\"\n      directives:\n        img-src:\n          - \"'self'\"\n          - \"data:\"\n          - \"https://cdn.statically.io\"\n          - \"https://raw.githubusercontent.com\"\n        font-src:\n          - \"'self'\"\n          - \"data:\"\n        style-src-attr:\n          - \"'self'\"\n          - \"'unsafe-inline'\"\n        style-src-elem:\n          - \"'self'\"\n    - location: \"/console/\"\n      directives:\n        img-src:\n          - \"'self'\"\n          - \"data:\"\n          - \"https://cdn.statically.io\"\n          - \"https://raw.githubusercontent.com\"\n        font-src:\n          - \"'self'\"\n          - \"data:\"\n        connect-src:\n          - \"'self'\"\n          - \"https://thunderid.dev\"\n        style-src-attr:\n          - \"'self'\"\n          - \"'unsafe-inline'\"\n        style-src-elem:\n          - \"'self'\"\n          - \"'unsafe-inline'\"\n        worker-src:\n          - \"'self'\"\n          - \"blob:\"\n"` |  |
| thunderid.bootstrap.scripts."49-cors.yaml" | string | `"resource_type: server_config\nname: cors\nvalue:\n  allowedOrigins:\n    - \"http://openchoreo.localhost:8080\"\n"` |  |
| thunderid.bootstrap.scripts."50-user-schema-and-users.yaml" | string | `"resource_type: user_type\nid: 01900000-0000-7000-8001-000000000010\ncategory: user\nname: openchoreo-user\nouHandle: default\nallowSelfRegistration: false\nsystemAttributes:\n  display: username\nschema:\n  username:\n    type: string\n    displayName: Username\n    required: true\n    unique: true\n  password:\n    type: string\n    displayName: Password\n    required: false\n    credential: true\n  given_name:\n    type: string\n    displayName: First Name\n    required: true\n  family_name:\n    type: string\n    displayName: Last Name\n    required: true\n  email:\n    type: string\n    displayName: Email\n    required: true\n    unique: true\n---\nresource_type: user\nid: 01900000-0000-7000-8001-000000000030\ntype: openchoreo-user\nouHandle: default\nattributes:\n  username: admin@openchoreo.dev\n  email: admin@openchoreo.dev\n  given_name: Admin\n  family_name: User\ncredentials:\n  password: \"{{ .OPENCHOREO_ADMIN_PASSWORD }}\"\n---\nresource_type: user\nid: 01900000-0000-7000-8001-000000000031\ntype: openchoreo-user\nouHandle: default\nattributes:\n  username: developer@openchoreo.dev\n  email: developer@openchoreo.dev\n  given_name: Developer\n  family_name: User\ncredentials:\n  password: \"{{ .OPENCHOREO_DEVELOPER_PASSWORD }}\"\n---\nresource_type: group\nid: 01900000-0000-7000-8001-000000000040\nname: admins\ndescription: Openchoreo Admins group\nouHandle: default\nmembers:\n  - id: 01900000-0000-7000-8001-000000000030\n    type: user\n---\nresource_type: group\nid: 01900000-0000-7000-8001-000000000041\nname: developers\ndescription: Openchoreo Developers group\nouHandle: default\nmembers:\n  - id: 01900000-0000-7000-8001-000000000031\n    type: user\n---\nresource_type: group\nid: 01900000-0000-7000-8001-000000000042\nname: demo-developers\ndescription: Developers of OpenChoreo project demo (platform, DEMO; charts/tenant developerGroups default)\nouHandle: default\nmembers:\n  - id: 01900000-0000-7000-8001-000000000031\n    type: user\n"` |  |
| thunderid.bootstrap.scripts."51-backstage-app.yaml" | string | `"resource_type: application\nid: 01900000-0000-7000-8001-000000000060\nouId: 01900000-0000-7000-8000-000000000001\nname: Backstage\ntype: fullstack\nauthFlowId: 01900000-0000-7000-8000-000000000061\ndescription: OpenChoreo Backstage Portal\nlogoUrl: \"https://cdn.statically.io/gh/openchoreo/openchoreo.github.io@main/static/img/openchoreo-logo.png\"\nallowedUserTypes:\n  - openchoreo-user\nassertion:\n  validityPeriod: 3600\ninboundAuthConfig:\n  - type: oauth2\n    config:\n      clientId: openchoreo-backstage-client\n      clientSecret: \"{{ .BACKSTAGE_CLIENT_SECRET }}\"\n      redirectUris:\n        - \"http://openchoreo.localhost:8080/api/auth/openchoreo-auth/handler/frame\"\n      grantTypes:\n        - authorization_code\n        - client_credentials\n        - refresh_token\n      responseTypes:\n        - code\n      tokenEndpointAuthMethod: client_secret_post\n      pkceRequired: false\n      publicClient: false\n      token:\n        accessToken:\n          userConfig:\n            validityPeriod: 86400\n            attributes:\n              - given_name\n              - family_name\n              - username\n              - groups\n          clientConfig:\n            validityPeriod: 86400\n        idToken:\n          validityPeriod: 86400\n          userAttributes:\n            - given_name\n            - family_name\n            - username\n            - groups\n      scopeClaims:\n        email:\n          - email\n        groups:\n          - groups\n        profile:\n          - username\n          - given_name\n          - family_name\n          - picture\n"` |  |
| thunderid.bootstrap.scripts."54-cli-app.yaml" | string | `"resource_type: application\nid: 01900000-0000-7000-8001-000000000063\nouId: 01900000-0000-7000-8000-000000000001\nname: OpenChoreo CLI\ntype: custom\nauthFlowId: 01900000-0000-7000-8000-000000000061\ndescription: OpenChoreo CLI Default Application\nlogoUrl: \"https://cdn.statically.io/gh/openchoreo/openchoreo.github.io@main/static/img/openchoreo-logo.png\"\nallowedUserTypes:\n  - openchoreo-user\nassertion:\n  validityPeriod: 3600\ninboundAuthConfig:\n  - type: oauth2\n    config:\n      clientId: openchoreo-cli\n      redirectUris:\n        - \"http://127.0.0.1:55152/auth-callback\"\n      grantTypes:\n        - authorization_code\n        - refresh_token\n      responseTypes:\n        - code\n      tokenEndpointAuthMethod: none\n      pkceRequired: true\n      publicClient: true\n      token:\n        accessToken:\n          userConfig:\n            validityPeriod: 3600\n            attributes:\n              - given_name\n              - family_name\n              - username\n              - groups\n        idToken:\n          validityPeriod: 3600\n          userAttributes:\n            - given_name\n            - family_name\n            - username\n            - groups\n      scopeClaims:\n        email:\n          - email\n        groups:\n          - groups\n        profile:\n          - username\n          - given_name\n          - family_name\n          - picture\n          - groups\n"` |  |
| thunderid.bootstrap.scripts."57-service-mcp-app.yaml" | string | `"resource_type: application\nid: 01900000-0000-7000-8001-000000000066\nouId: 01900000-0000-7000-8000-000000000001\nname: Service MCP App\ntype: mcp\ndescription: Service MCP app to be used by backend services which can securely store the secret\ninboundAuthConfig:\n  - type: oauth2\n    config:\n      clientId: service_mcp_client\n      clientSecret: \"{{ .SERVICE_MCP_CLIENT_SECRET }}\"\n      grantTypes:\n        - client_credentials\n      tokenEndpointAuthMethod: client_secret_basic\n      pkceRequired: false\n      publicClient: false\n      token:\n        accessToken:\n          clientConfig:\n            validityPeriod: 3600\n"` |  |
| thunderid.bootstrap.scripts."59-openchoreo-observer-app.yaml" | string | `"resource_type: application\nid: 01900000-0000-7000-8001-000000000068\nouId: 01900000-0000-7000-8000-000000000001\nname: OpenChoreo Observer Resource Reader\ntype: m2m\ndescription: OpenChoreo Observer Resource Reader Client\ninboundAuthConfig:\n  - type: oauth2\n    config:\n      clientId: openchoreo-observer-resource-reader-client\n      clientSecret: \"{{ .OBSERVER_CLIENT_SECRET }}\"\n      grantTypes:\n        - client_credentials\n      tokenEndpointAuthMethod: client_secret_post\n      pkceRequired: false\n      publicClient: false\n      token:\n        accessToken:\n          clientConfig:\n            validityPeriod: 3600\n"` |  |
| thunderid.bootstrap.scripts."70-openchoreo-promotion-gate-app.yaml" | string | `"resource_type: application\nid: 01900000-0000-7000-8001-000000000100\nouId: 01900000-0000-7000-8000-000000000001\nname: OpenChoreo Promotion Gate\ntype: m2m\ndescription: Promotion gate workflow - read-only OpenChoreo API and observer queries (docs/promotion.md)\ninboundAuthConfig:\n  - type: oauth2\n    config:\n      clientId: openchoreo-promotion-gate\n      clientSecret: \"{{ .PROMOTION_GATE_CLIENT_SECRET }}\"\n      grantTypes:\n        - client_credentials\n      tokenEndpointAuthMethod: client_secret_post\n      pkceRequired: false\n      publicClient: false\n      token:\n        accessToken:\n          clientConfig:\n            validityPeriod: 900\n"` |  |
| thunderid.certs.persistence.annotations."helm.sh/hook-delete-policy" | string | `"hook-failed"` |  |
| thunderid.certs.persistence.annotations."platform.koorikla.io/delete-protection" | string | `"enabled"` |  |
| thunderid.configuration.database.config.postgres.password | string | `""` |  |
| thunderid.configuration.database.config.type | string | `"sqlite"` |  |
| thunderid.configuration.database.entity.postgres.password | string | `""` |  |
| thunderid.configuration.database.entity.type | string | `"sqlite"` |  |
| thunderid.configuration.database.runtime_persistent.postgres.password | string | `""` |  |
| thunderid.configuration.database.runtime_persistent.type | string | `"sqlite"` |  |
| thunderid.configuration.database.runtime_transient.postgres.password | string | `""` |  |
| thunderid.configuration.database.runtime_transient.type | string | `"sqlite"` |  |
| thunderid.configuration.gateClient.hostname | string | `"thunder.openchoreo.localhost"` |  |
| thunderid.configuration.gateClient.port | int | `8080` |  |
| thunderid.configuration.gateClient.scheme | string | `"http"` |  |
| thunderid.configuration.passkey.allowedOrigins[0] | string | `"http://openchoreo.localhost:8080"` |  |
| thunderid.configuration.server.httpOnly | bool | `true` |  |
| thunderid.configuration.server.publicUrl | string | `"http://thunder.openchoreo.localhost:8080"` |  |
| thunderid.deployment.image.pullPolicy | string | `"IfNotPresent"` |  |
| thunderid.deployment.image.tag | string | `"1.0.1@sha256:d3c0613ff447a551fd440768a15bdfb6668948e80809cbb50f82d6752f22ab3e"` |  |
| thunderid.deployment.replicaCount | int | `1` | `1` (single-writer SQLite persistence) with `1.0.1` pinned by multi-arch index digest. |
| thunderid.fullnameOverride | string | `"thunder"` |  |
| thunderid.hpa.enabled | bool | `false` |  |
| thunderid.httproute.enabled | bool | `true` | Exposes `thunder.<openchoreo.controlPlane.host>` via `openchoreo-control-plane/gateway-default`. |
| thunderid.httproute.hostnames[0] | string | `"thunder.openchoreo.localhost"` |  |
| thunderid.httproute.parentRefs[0].name | string | `"gateway-default"` |  |
| thunderid.httproute.parentRefs[0].namespace | string | `"openchoreo-control-plane"` |  |
| thunderid.ingress.enabled | bool | `false` |  |
| thunderid.persistence.annotations."helm.sh/hook-delete-policy" | string | `"hook-failed"` |  |
| thunderid.persistence.annotations."platform.koorikla.io/delete-protection" | string | `"enabled"` |  |
| thunderid.secrets.persistence.annotations."helm.sh/hook-delete-policy" | string | `"hook-failed"` |  |
| thunderid.secrets.persistence.annotations."platform.koorikla.io/delete-protection" | string | `"enabled"` |  |
| thunderid.setup.admin.passwordRef.key | string | `"thunder-admin-password"` |  |
| thunderid.setup.admin.passwordRef.name | string | `"thunder-bootstrap"` |  |
| thunderid.setup.enabled | bool | `true` |  |
| thunderid.setup.extraVolumeMounts[0].mountPath | string | `"/opt/thunderid/bootstrap/ai-agent-clients"` |  |
| thunderid.setup.extraVolumeMounts[0].name | string | `"ai-agent-clients"` |  |
| thunderid.setup.extraVolumeMounts[0].readOnly | bool | `true` |  |
| thunderid.setup.extraVolumeMounts[0].subPath | string | `"ai-agent-clients"` |  |
| thunderid.setup.extraVolumes[0].configMap.items[0].key | string | `"README"` |  |
| thunderid.setup.extraVolumes[0].configMap.items[0].path | string | `"ai-agent-clients/README"` |  |
| thunderid.setup.extraVolumes[0].configMap.items[1].key | string | `"53-rca-agent-client.yaml"` |  |
| thunderid.setup.extraVolumes[0].configMap.items[1].path | string | `"ai-agent-clients/53-rca-agent-client.yaml"` |  |
| thunderid.setup.extraVolumes[0].configMap.items[2].key | string | `"60-finops-agent-client.yaml"` |  |
| thunderid.setup.extraVolumes[0].configMap.items[2].path | string | `"ai-agent-clients/60-finops-agent-client.yaml"` |  |
| thunderid.setup.extraVolumes[0].configMap.name | string | `"thunder-ai-agent-clients"` |  |
| thunderid.setup.extraVolumes[0].configMap.optional | bool | `true` |  |
| thunderid.setup.extraVolumes[0].name | string | `"ai-agent-clients"` |  |
| thunderid.setup.preserveJob | bool | `true` |  |
| thunderid.setup.secretEnv[0].name | string | `"OPENCHOREO_ADMIN_PASSWORD"` |  |
| thunderid.setup.secretEnv[0].secretKey | string | `"admin-user-password"` |  |
| thunderid.setup.secretEnv[0].secretName | string | `"thunder-bootstrap"` |  |
| thunderid.setup.secretEnv[1].name | string | `"OPENCHOREO_DEVELOPER_PASSWORD"` |  |
| thunderid.setup.secretEnv[1].secretKey | string | `"developer-user-password"` |  |
| thunderid.setup.secretEnv[1].secretName | string | `"thunder-bootstrap"` |  |
| thunderid.setup.secretEnv[2].name | string | `"BACKSTAGE_CLIENT_SECRET"` |  |
| thunderid.setup.secretEnv[2].secretKey | string | `"backstage-client-secret"` |  |
| thunderid.setup.secretEnv[2].secretName | string | `"thunder-bootstrap"` |  |
| thunderid.setup.secretEnv[3].name | string | `"SERVICE_MCP_CLIENT_SECRET"` |  |
| thunderid.setup.secretEnv[3].secretKey | string | `"service-mcp-client-secret"` |  |
| thunderid.setup.secretEnv[3].secretName | string | `"thunder-bootstrap"` |  |
| thunderid.setup.secretEnv[4].name | string | `"OBSERVER_CLIENT_SECRET"` |  |
| thunderid.setup.secretEnv[4].secretKey | string | `"observer-client-secret"` |  |
| thunderid.setup.secretEnv[4].secretName | string | `"thunder-bootstrap"` |  |
| thunderid.setup.secretEnv[5].name | string | `"PROMOTION_GATE_CLIENT_SECRET"` |  |
| thunderid.setup.secretEnv[5].secretKey | string | `"promotion-gate-client-secret"` |  |
| thunderid.setup.secretEnv[5].secretName | string | `"thunder-bootstrap"` |  |
| thunderid.setup.secretEnv[6].name | string | `"RCA_AGENT_CLIENT_SECRET"` |  |
| thunderid.setup.secretEnv[6].optional | bool | `true` |  |
| thunderid.setup.secretEnv[6].secretKey | string | `"rca-agent-client-secret"` |  |
| thunderid.setup.secretEnv[6].secretName | string | `"thunder-bootstrap"` |  |
| thunderid.setup.secretEnv[7].name | string | `"FINOPS_AGENT_CLIENT_SECRET"` |  |
| thunderid.setup.secretEnv[7].optional | bool | `true` |  |
| thunderid.setup.secretEnv[7].secretKey | string | `"finops-agent-client-secret"` |  |
| thunderid.setup.secretEnv[7].secretName | string | `"thunder-bootstrap"` |  |

### Design notes

- **Upstream:** OpenChoreo 1.3.3 `install/k3d/common/values-thunder.yaml` nested under `thunderid:`; every deviation is marked `platform:` in `values.yaml`.
- **Issuer:** browsers and pods use the same URL `http://thunder.openchoreo.localhost:8080` (browsers via the k3d published port, mgmt pods via the coredns-local rewrite to the control-plane Gateway). The HTTPRoute attaches once Gateway `openchoreo-control-plane/gateway-default` exists.
- **Secrets** (no literal credentials in git): `ClusterSecretStore/platform`, key `openchoreo` -> Secret `thunder-bootstrap` (`templates/bootstrap-secret.yaml`). Properties are alphanumeric because Thunder's bootstrap splices them into YAML:

  | Property | Used by |
  |---|---|
  | `thunder-admin-password` | Thunder console admin (user `admin`) |
  | `admin-user-password` | `admin@openchoreo.dev` (group admins -> OpenChoreo role admin) |
  | `developer-user-password` | `developer@openchoreo.dev` (developers: org-wide read-only; demo-developers: role developer in project demo) |
  | `backstage-client-secret` | OAuth client `openchoreo-backstage-client` (also addon openchoreo-control-plane) |
  | `backstage-backend-secret` | addon openchoreo-control-plane only |
  | `service-mcp-client-secret` | OAuth client `service_mcp_client` (headless MCP, [AI agents](../../docs/ai-agents.md)) |

  Plus `openchoreo-observability` / `observer-client-secret` (observer client) and `promotion-gate` / `client-secret` ([promotion](../../docs/promotion.md)). The setup Job resolves `{{ .VAR }}` placeholders from its environment; `setup.secretEnv` puts the values there.
- **Hooks:** Argo CD runs every Helm hook as PreSync on every sync, in this order:
  1. VAP `thunder-pvc-delete-protection` (weight -30): denies deleting the PVCs, so a failed sync cannot make Argo CD delete them.
  2. ExternalSecret `thunder-bootstrap` (-20).
  3. PVCs database/certs/secrets (-15, upstream hooks) with `hook-delete-policy: hook-failed`, so a successful sync never wipes the SQLite DB and keys. They stay Pending until the setup Job mounts them: Argo CD needs a PVC health override ([OpenChoreo](../../docs/openchoreo.md)).
  4. ServiceAccount/ConfigMaps (-10), then the setup Job (-5): a throw-away Thunder on localhost:8090 imports the bundle (upserts by id; every document must be a mapping, `hack/tests/test_thunder_bootstrap.sh`). The setup pod carries the Deployment's selector labels, so `thunder-service` routes to it for ~1 min per sync.
- Argo CD never diffs hooks (#221): ConfigMap `thunder-setup-inputs` carries their checksums so a hook-only change still syncs.
- **Footprint:** one pod 100m/50Mi requests, the setup Job the same while it runs, 3 small local-path PVCs.

## Day-2 notes

- Values are checked by `values.schema.json` (bootstrap Secret keys, AI agent names, host format; `helm` prints the failing path). Host consistency with `openchoreo.controlPlane.host` is checked in `templates/validate.yaml`.
- Backing up and recovering Thunder's delete-protected PVCs: [backup and restore](../../docs/runbooks/backup-restore.md#4-thunder-pvc-recovery-live-verified) and [break-glass](../../docs/runbooks/break-glass.md#intentional-deletion-of-a-delete-protected-pvc).
- Upgrading Thunder with OpenChoreo: [upgrades](../../docs/runbooks/upgrades.md#4-openchoreo-and-thunder).

## Links

- [OpenChoreo](../../docs/openchoreo.md)