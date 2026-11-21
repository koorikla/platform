# strimzi

## Purpose

Wrapper chart for `strimzi-kafka-operator` (`1.3.1`) on workload clusters. Manages Apache Kafka (KRaft) clusters, `KafkaTopic`s, and `KafkaUser`s across all namespaces, with Prometheus `PodMonitor` scraping.

## Where it runs

- **Roles / providers:** `roles: [workload]`, all providers (`namespace: strimzi`).
- **Catalog label:** `addons.platform.koorikla.io/strimzi` (`default: false`, opt-in with `"true"` per cluster via `addons.strimzi: true`).

## Key values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| monitoring.podMonitor | bool | `true` | `true` (scrapes operator metrics via `addons/telemetry`). |
| namespace.ambient | bool | `true` |  |
| namespace.podSecurity | string | `"restricted"` | `restricted` Pod Security admission label on namespace `strimzi`. |
| strimzi-kafka-operator.buildah.image.tag | string | `"1.3.1@sha256:7a2f75ee2a66b5cd83ebadf9be5efdf452e31cf006714e8f46f8ce16b3806b98"` |  |
| strimzi-kafka-operator.extraEnvs[0].name | string | `"STRIMZI_POD_SECURITY_PROVIDER_CLASS"` |  |
| strimzi-kafka-operator.extraEnvs[0].value | string | `"restricted"` |  |
| strimzi-kafka-operator.extraEnvs[1].name | string | `"STRIMZI_NETWORK_POLICY_GENERATION"` |  |
| strimzi-kafka-operator.extraEnvs[1].value | string | `"false"` |  |
| strimzi-kafka-operator.image.tag | string | `"1.3.1@sha256:55f43849559a0d151be473c588c89e9d72649ecadf088c8b9d92d37654a5e5eb"` | `1.3.1` pinned by multi-arch index digest (alongside `topicOperator.image`, `userOperator.image`, `kafkaInit.image`). |
| strimzi-kafka-operator.kafkaBridge.image.tag | string | `"1.2.1@sha256:4597700f87ab33b7768863728730bc2eb68a0d7fa9633ab2a4cebb3a2730cfa9"` |  |
| strimzi-kafka-operator.kafkaInit.image.tag | string | `"1.3.1@sha256:55f43849559a0d151be473c588c89e9d72649ecadf088c8b9d92d37654a5e5eb"` |  |
| strimzi-kafka-operator.mavenBuilder.image.tag | string | `"1.3.1@sha256:ce67465a4df0fa0a684e64962d6d4fff0b767636ae18e2ee7834bba14f5e4813"` |  |
| strimzi-kafka-operator.podSecurityContext.runAsNonRoot | bool | `true` |  |
| strimzi-kafka-operator.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| strimzi-kafka-operator.resources.limits.cpu | string | `"1000m"` |  |
| strimzi-kafka-operator.resources.limits.memory | string | `"384Mi"` |  |
| strimzi-kafka-operator.resources.requests.cpu | string | `"50m"` |  |
| strimzi-kafka-operator.resources.requests.memory | string | `"384Mi"` |  |
| strimzi-kafka-operator.topicOperator.image.tag | string | `"1.3.1@sha256:55f43849559a0d151be473c588c89e9d72649ecadf088c8b9d92d37654a5e5eb"` |  |
| strimzi-kafka-operator.userOperator.image.tag | string | `"1.3.1@sha256:55f43849559a0d151be473c588c89e9d72649ecadf088c8b9d92d37654a5e5eb"` |  |
| strimzi-kafka-operator.watchAnyNamespace | bool | `true` | `true` so dynamically created OpenChoreo cell namespaces are reconciled. |

### Design notes

- **Strimzi 1.x:** KRaft only; Kafka / KafkaNodePool / KafkaTopic / KafkaUser in `kafka.strimzi.io/v1`. CRDs come from the chart's `crds/` and are applied server-side (the Kafka CRD is too large for client-side apply).
- **Watch scope:** all namespaces (cell namespaces `dp-*` appear at runtime). The operator can therefore manage Pods, Services, Secrets, ConfigMaps, PVCs, NetworkPolicies, PDBs and Roles in every namespace. Restrict with `watchNamespaces` + `watchAnyNamespace: false` in an installation overlay when Kafka clusters live in known namespaces.
- **Images:** multi-arch, pinned by digest (operator, kafka-init, Kafka Bridge, builders). Broker images follow `spec.kafka.version` by tag; pin one with `spec.kafka.image` ([example](../../docs/data-services.md)).

## Day-2 notes

- Operator upgrades and workload cluster sizing: [upgrades](../../docs/runbooks/upgrades.md#3-addon-chart-bumps-and-staged-rollout-addonsrevision) and [scaling and capacity](../../docs/runbooks/scaling-and-capacity.md).

## Links

- [Data services: Kafka (Strimzi)](../../docs/data-services.md#kafka-strimzi)