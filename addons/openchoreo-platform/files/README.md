# Upstream OpenChoreo 1.3.3 platform defaults

Copied from `openchoreo/openchoreo@v1.3.3:samples/getting-started/` (the resources `all.yaml` applies), one object per
file, rendered verbatim by `templates/upstream-defaults.yaml` (no Helm templating inside these files).

| Here | Upstream | Change |
|---|---|---|
| `cluster-component-types/{scheduled-task,service,webapp,worker}.yaml` | `component-types/*.yaml` | see below |
| `cluster-traits/{health-probes,hpa,observability-alert-rule,pvc}.yaml` | `component-traits/{health-probes,hpa,alert-rule,pvc}-trait.yaml` | none |
| `cluster-project-types/default.yaml` | `cluster-project-types/default.yaml` | none |

Component types: upstream's `spec.allowedWorkflows` removed from the files (they name upstream's podman/buildpacks
ClusterWorkflows, which are not installed); `templates/upstream-defaults.yaml` sets it at render time to the platform's
build ClusterWorkflows (`buildWorkflows.stacks`, docs/build-plane.md). `vertical-pod-autoscaler` removed from
`spec.allowedTraits` (that trait is not installed; the VPA trait needs the VPA CRDs on data planes). Reproduce:

```bash
T='del(.spec.allowedWorkflows) | (select(.spec.allowedTraits) | .spec.allowedTraits) |=
   map(select(.name != "vertical-pod-autoscaler"))'
yq "$T" samples/getting-started/component-types/service.yaml > files/cluster-component-types/service.yaml
```

Not taken: `ClusterResourceType`s (postgres/valkey/nats: plain StatefulSets; the platform's `postgresql` type below
renders the Crossplane XR instead), upstream `ClusterWorkflow`s and
workflow templates (replaced by templates/build-workflows.yaml + addon openchoreo-workflow-plane: rootless BuildKit,
ci/scripts, GitOps hand-off instead of writing Workloads through the API), `vertical-pod-autoscaler` (not installed), the sample `Project default` and
its `ProjectReleaseBinding`s (projects come from tenants), `Environment`s (charts/cluster renders them per cluster),
`DeploymentPipeline` (templates/deployment-pipeline.yaml, from values).

## Platform types (`platform/`)

Not upstream; rendered by `templates/platform-types.yaml`, each behind a values switch:

| File | Switch | What it is |
|---|---|---|
| `cluster-traits/keda-scaler.yaml` | `dataServices.enabled` | KEDA ScaledObject trait ([data services](../../../docs/data-services.md)) |
| `cluster-resource-types/{postgresql,mysql}.yaml` | `dataServices.enabled` | the Crossplane platform APIs as OpenChoreo Resources |
| `cluster-traits/resilience.yaml` | `resilience.enabled` | spread, PDB, graceful shutdown, priority ([docs/openchoreo.md "Resilience defaults"](../../../docs/openchoreo.md#resilience-defaults)) |
| `cluster-traits/metrics.yaml` | `appMetrics.enabled` | opt-in PodMonitor ([docs/openchoreo.md "Application metrics"](../../../docs/openchoreo.md#application-metrics)) |

The data-service types carry `platform.koorikla.io/requires-addons`: the addons a data plane must announce
(ClusterDataPlane annotations from the fleet file; hack/tests/test_openchoreo_types.sh).

`templates/upstream-defaults.yaml` edits the Deployment-based component types at render time:

- `allowedTraits` += `keda-scaler`, `metrics` (when their switch is on);
- `spec.traits` += `resilience` and `environmentConfigs` += the `resilience` knobs, so developers never attach it;
- `deployment` resource annotated `secret.reloader.stakater.com/auto: "true"`: addon reloader rolls the pods when a
  Secret they reference rotates (docs/runbooks/certificates-and-secrets.md section 7);
- with `secrets.tenantStores.enabled`, ExternalSecrets use the cell's SecretStore `tenantStoreName`.
