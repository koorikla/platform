# Runbook: Backup and restore

<img src="../diagrams/backup.svg" alt="Backup and restore: what is stateful where, and the restore order after losing mgmt" width="100%">

## When to use

Use it before a risky upgrade, to recover a stateful component (`etcd`, OpenBao, Thunder, Harbor, CloudNativePG), or for
a restore drill. Everything not in this table is rebuilt from Git by Argo CD.

| Plane | Stateful data | Rebuilt from Git? |
|---|---|---|
| Management `etcd` (`k3d-platform-mgmt`) | CAPI `Cluster`/`Machine` objects, cluster kubeconfigs and CAs in `fleet`, `platform-secrets` (local backend) | Addons and platform CRs rebuild from Git; CAPI node/CA secrets and local `platform-secrets` do **not** |
| Workload `etcd` (`dev1`, cloud clusters) | Workload API state, local Secrets/PV bindings | Addons and OpenChoreo `RenderedRelease` resources re-sync from mgmt |
| OpenBao (`openbao`) | PVC `data-openbao-0` (internal mesh root + intermediate keys, tenant app secrets in `kv-tenant-<project>`) **and** store key `openbao-unseal` | Policies, member roles and tenant mounts rebuild (`mesh-reconcile`, tenant reconcile); CA private keys and app secret values do **not** (locally the demo tenant's value is re-seeded) |
| Thunder (`thunder`) | PVCs `thunder-database-pvc`, `thunder-certs-pvc`, `thunder-secrets-pvc` | Default clients/roles upsert (`thunder-setup`); runtime users, sessions, and signing keys live on the PVCs |
| Harbor (`harbor`) | PVCs `database-data-harbor-database-0`, `harbor-registry` **and** store key `harbor` (`secretKey`) | Projects, proxy caches, replication, and robots rebuild (`harbor-config`); pushed `apps/` images do **not** |
| CloudNativePG (`cnpg-system`, tenant ns) | PostgreSQL PVCs + Barman Cloud object-store WAL/base backups | Operator and `Cluster` CRs rebuild from Git; tenant database rows come from Barman recovery |

## Symptoms

- Management or workload API server fails to start after a full disk or an unclean shutdown.
- Thunder PVCs are `Terminating` (held only by `kubernetes.io/pvc-protection`) or `thunder-mgmt` fails sync with `spec is immutable` on a manually recreated PVC.
- OpenBao pod `openbao-0` starts uninitialized or sealed after storage loss or unseal-key mismatch.
- Harbor database or registry storage needs pre-upgrade backup or post-corruption restore.
- A tenant PostgreSQL `Cluster` requires point-in-time recovery from object storage.

## Steps

### 1. Management cluster etcd (`k3d`)

`k3d-platform-mgmt` runs embedded `etcd` (`--cluster-init` in `bootstrap/k3d-mgmt.yaml`). k3s takes automatic
snapshots every 12 h and keeps 5 under `/var/lib/rancher/k3s/server/db/snapshots`. The local etcd runs without fsync
([why](../dev-environment.md#local-stack-load-and-the-mgmt-datastore)), so a host or Docker VM crash can lose the last
writes: restore a snapshot, or rebuild with `task down` and `task up`.

#### On-demand snapshot and full volume backup

```bash
C=k3d-platform-mgmt-server-0
# Save an etcd snapshot inside the mgmt container
docker exec "$C" k3s etcd-snapshot save --name manual-$(date +%Y%m%d-%H%M)
docker exec "$C" k3s etcd-snapshot ls

# Full cold backup of etcd + server TLS/token + local-path PV storage (chmod 700: contains secrets)
IMG=$(yq -r .image bootstrap/k3d-mgmt.yaml)
VOL=$(docker inspect "$C" -f '{{range .Mounts}}{{if eq .Destination "/var/lib/rancher/k3s"}}{{.Name}}{{end}}{{end}}')
BK="$HOME/platform-mgmt-backup-$(date +%Y%m%d-%H%M)"; mkdir -p "$BK" && chmod 700 "$BK"
docker stop -t 120 "$C"
docker run --rm -v "$VOL":/k3s:ro -v "$BK":/backup --entrypoint tar "$IMG" -C /k3s -cf /backup/k3s.tar server storage
docker start "$C"
```

#### Restore management `etcd` from snapshot `(not yet verified live)`

```bash
C=k3d-platform-mgmt-server-0
SNAP=<snapshot-file-name>   # from `docker exec $C k3s etcd-snapshot ls`
docker stop -t 120 "$C"
IMG=$(yq -r .image bootstrap/k3d-mgmt.yaml)
VOL=$(docker inspect "$C" -f '{{range .Mounts}}{{if eq .Destination "/var/lib/rancher/k3s"}}{{.Name}}{{end}}{{end}}')
docker run --rm -v "$VOL":/var/lib/rancher/k3s "$IMG" server \
  --cluster-reset --cluster-reset-restore-path="/var/lib/rancher/k3s/server/db/snapshots/$SNAP"
docker start "$C"
kubectl --context k3d-platform-mgmt get nodes
```

### 2. CAPD and cloud workload cluster `etcd`

Every CAPI k3s server runs embedded `etcd`. On CAPD, the Docker container name matches the CAPI `Machine` name in `fleet`:

```bash
# List control-plane Machine names for dev1 and save an etcd snapshot
kubectl --context k3d-platform-mgmt -n fleet get machines \
  -l cluster.x-k8s.io/cluster-name=dev1,cluster.x-k8s.io/control-plane
MACHINE=$(kubectl --context k3d-platform-mgmt -n fleet get machines \
  -l cluster.x-k8s.io/cluster-name=dev1,cluster.x-k8s.io/control-plane -o jsonpath='{.items[0].metadata.name}')
docker exec "$MACHINE" k3s etcd-snapshot save --name manual-$(date +%Y%m%d-%H%M)
docker exec "$MACHINE" k3s etcd-snapshot ls
```

- **Cloud workload clusters (`aws`, `hetzner`)** `(not yet verified live)`: run `sudo k3s etcd-snapshot save` on a control-plane node, or pass `--etcd-s3` arguments via `KThreesControlPlane` for off-node S3 retention.
- **Single-server rollout lost quorum**: see [break-glass.md](break-glass.md#single-server-etcd-quorum-loss).

### 3. OpenBao (`raft` storage and unseal key)

OpenBao stores mesh CA private keys (`pki-mesh-<group>-root`, `pki-mesh-<group>-int`) and the tenants' app secrets (KV mounts `kv-tenant-<project>`, [openchoreo.md](../openchoreo.md#application-secrets-developer-view)) encrypted on PVC `data-openbao-0` (`/openbao/data` in `openbao-0`). Locally it uses `seal "static"` from `ClusterSecretStore/platform` key `openbao-unseal` ([multicluster.md](../multicluster.md#unseal)); production replaces this with KMS auto-unseal and 3 raft replicas ([#31](https://github.com/koorikla/platform/issues/31)).

Because OpenBao revokes its root token during self-initialization (`addons/openbao/values.yaml`) and no runtime ACL policy grants `sys/storage/raft/snapshot`, online `bao operator raft snapshot save` requires adding a snapshot role before first start ([#31](https://github.com/koorikla/platform/issues/31)). Until then, take a consistent cold copy of `data-openbao-0` **together with** verifying `openbao-unseal` `(not yet verified live)`:

```bash
K="kubectl --context k3d-platform-mgmt"
# 1. Confirm the unseal secret exists (never print its value); without it, raft data cannot be decrypted
$K -n platform-secrets get secret openbao-unseal -o jsonpath='{.metadata.name} keys={.data | keys}{"\n"}'

# 2. Freeze Argo CD, stop openbao-0 cleanly, and copy its local-path PV directory
$K -n argocd scale statefulset/argocd-application-controller deploy/argocd-applicationset-controller --replicas=0
$K -n openbao scale statefulset/openbao --replicas=0
$K -n openbao wait --for=delete pod/openbao-0 --timeout=120s

PV=$($K -n openbao get pvc data-openbao-0 -o jsonpath='{.spec.volumeName}')
BK="$HOME/openbao-backup-$(date +%Y%m%d-%H%M)"; mkdir -p "$BK" && chmod 700 "$BK"
docker cp "k3d-platform-mgmt-server-0:/var/lib/rancher/k3s/storage/${PV}_openbao_data-openbao-0" "$BK/"

# 3. Start OpenBao and unfreeze Argo CD
$K -n openbao scale statefulset/openbao --replicas=1
$K -n openbao rollout status statefulset/openbao --timeout=180s
$K -n argocd scale statefulset/argocd-application-controller deploy/argocd-applicationset-controller --replicas=1
```

To restore from `$BK` `(not yet verified live)`, confirm the matching `platform-secrets/openbao-unseal` secret is present, freeze Argo CD and scale `statefulset/openbao` to `0` as above, replace `/var/lib/rancher/k3s/storage/${PV}_openbao_data-openbao-0/.` inside `k3d-platform-mgmt-server-0` from `$BK/` (`docker exec` wipe + `docker cp`), then scale `statefulset/openbao` and Argo CD back to `1` and verify `$K -n openbao exec openbao-0 -- bao status` (`Sealed: false`). If `openbao-unseal` or the backup is unavailable locally, re-initialize OpenBao via [break-glass.md](break-glass.md#openbao-local-re-initialization).

### 4. Thunder PVC recovery (live-verified)

Thunder's 3 PVCs (`thunder-database-pvc`, `thunder-certs-pvc`, `thunder-secrets-pvc` in `thunder`) are PreSync hooks with `hook-failed` and `platform.koorikla.io/delete-protection: enabled`, guarded by `ValidatingAdmissionPolicy/thunder-pvc-delete-protection` ([openchoreo.md](../openchoreo.md#argo-cd-requirements)).

Use this when a Thunder PVC is `Terminating` or must be rebound to its `Retain` PV ([#85](https://github.com/koorikla/platform/issues/85) has the live run):

```bash
K="kubectl --context k3d-platform-mgmt"
S=/var/lib/rancher/k3s/storage

# 0. Freeze BOTH Argo CD controllers so ApplicationSets and selfHeal cannot revert or sync mid-recovery
$K -n argocd scale statefulset/argocd-application-controller --replicas=0
$K -n argocd scale deploy/argocd-applicationset-controller --replicas=0
$K -n argocd wait --for=delete pod \
  -l 'app.kubernetes.io/name in (argocd-application-controller,argocd-applicationset-controller)' --timeout=120s

# 1. Discover the 3 bound PVs, ensure Retain policy, and take Backup #1 while Thunder is still up
PV_DB=$($K -n thunder get pvc thunder-database-pvc -o jsonpath='{.spec.volumeName}')
PV_CERT=$($K -n thunder get pvc thunder-certs-pvc -o jsonpath='{.spec.volumeName}')
PV_SEC=$($K -n thunder get pvc thunder-secrets-pvc -o jsonpath='{.spec.volumeName}')
for pv in "$PV_DB" "$PV_CERT" "$PV_SEC"; do
  $K patch pv "$pv" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
done
B="$HOME/thunder-backup-$(date +%Y%m%d-%H%M)"; mkdir -p "$B" && chmod 700 "$B"
for d in "${PV_DB}_thunder_thunder-database-pvc" "${PV_CERT}_thunder_thunder-certs-pvc" "${PV_SEC}_thunder_thunder-secrets-pvc"; do
  docker cp "k3d-platform-mgmt-server-0:$S/$d" "$B/"
done

# 2. Stop Thunder to release pvc-protection, wait for Terminating PVCs to delete, and take Backup #2 (no writer)
$K -n thunder scale deploy/thunder-deployment --replicas=0
$K -n thunder wait --for=delete pod -l app.kubernetes.io/name=thunderid,app.kubernetes.io/instance=thunder --timeout=180s
$K -n thunder wait --for=delete pvc/thunder-database-pvc pvc/thunder-certs-pvc pvc/thunder-secrets-pvc --timeout=120s
B2="${B}-stopped"; mkdir -p "$B2" && chmod 700 "$B2"
for d in "${PV_DB}_thunder_thunder-database-pvc" "${PV_CERT}_thunder_thunder-certs-pvc" "${PV_SEC}_thunder_thunder-secrets-pvc"; do
  docker cp "k3d-platform-mgmt-server-0:$S/$d" "$B2/"
done

# 3. Clear dead claimRef UIDs so PVs move from Released to Available while staying reserved for thunder/*
for pv in "$PV_DB" "$PV_CERT" "$PV_SEC"; do
  $K patch pv "$pv" -p '{"spec":{"claimRef":{"uid":null,"resourceVersion":null}}}'
done

# 4. Recreate PVCs with `kubectl create` (NEVER `kubectl apply`: Argo CD migrates client-side apply to SSA manager
#    argocd-controller and then fails forever with `spec is immutable` trying to strip volumeName/storageClassName)
for spec in "thunder-database-pvc $PV_DB 1Gi" "thunder-certs-pvc $PV_CERT 16Mi" "thunder-secrets-pvc $PV_SEC 16Mi"; do
  set -- $spec
  cat <<EOF | $K create -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $1
  namespace: thunder
  annotations:
    platform.koorikla.io/delete-protection: enabled
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  volumeName: $2
  resources:
    requests:
      storage: $3
EOF
done

# 5. Start Thunder, verify readiness, remove any stale setup Job, and unfreeze Argo CD
$K -n thunder scale deploy/thunder-deployment --replicas=1
$K -n thunder rollout status deploy/thunder-deployment --timeout=300s
curl -fsS http://thunder.openchoreo.localhost:8080/health/readiness
$K -n thunder delete job thunder-setup --ignore-not-found
$K -n argocd scale statefulset/argocd-application-controller deploy/argocd-applicationset-controller --replicas=1
```

- **k3s restarts mid-recovery**: if `k3s` restarts while an older hook-delete was in flight and leaves the recreated PVCs `Terminating`, repeat steps 2–4 once while Argo CD stays frozen.
- **Cleanup**: once `thunder-mgmt` is `Synced` / `Healthy`, delete `$B` and `$B2` (`rm -rf "$B" "$B2"`), which hold Thunder's SQLite DB and keys.

### 5. Harbor (`harbor`)

Harbor's persistent state lives in `database-data-harbor-database-0` (PostgreSQL metadata) and `harbor-registry` (OCI blobs), paired with store key `harbor` (`secretKey` encrypts stored credentials; `addons/harbor/values.yaml`). Projects, proxy-cache endpoints, replication rules, and robot accounts (`robot$builder`, `robot$nodes`) are re-applied hourly by `CronJob/harbor-config` ([build-plane.md](../build-plane.md#registry-harbor)).

```bash
K="kubectl --context k3d-platform-mgmt"
BK="$HOME/harbor-backup-$(date +%Y%m%d-%H%M)"; mkdir -p "$BK" && chmod 700 "$BK"

# 1. Logical PostgreSQL dump
$K -n harbor exec statefulset/harbor-database -- pg_dumpall -U postgres > "$BK/harbor-db.sql"

# 2. Copy registry blobs from local-path storage
PV_REG=$($K -n harbor get pvc harbor-registry -o jsonpath='{.spec.volumeName}')
docker cp "k3d-platform-mgmt-server-0:/var/lib/rancher/k3s/storage/${PV_REG}_harbor_harbor-registry" "$BK/"
```

Restoring `harbor-db.sql` + `harbor-registry` onto a fresh `harbor` namespace requires the **same** `harbor` secret key in `ClusterSecretStore/platform` `(not yet verified live)`.

### 6. CloudNativePG (`cloudnative-pg`)

Cloud installations back up tenant PostgreSQL clusters to object storage via the **Barman Cloud plugin** (`barmancloud.cnpg.io/v1` `ObjectStore` + `ScheduledBackup` with `method: plugin` and workload identity; never deprecated `spec.backup.barmanObjectStore`; [data-services.md](../data-services.md#backups)). Local Docker clusters keep no S3 backups.

```bash
# Trigger an on-demand Barman plugin backup on a workload cluster (not yet verified live)
task kubeconfig CLUSTER=dev1
cat <<'EOF' | kubectl --kubeconfig dev1.kubeconfig apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: orders-db-pre-upgrade
  namespace: demo
spec:
  cluster:
    name: orders-db
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
kubectl --kubeconfig dev1.kubeconfig -n demo get backup orders-db-pre-upgrade
```

To restore, declare a new `postgresql.cnpg.io/v1` `Cluster` in Git with `spec.bootstrap.recovery.source` referencing an `externalClusters` entry backed by the same `barmanObjectName` `(not yet verified live)`.

### 7. Restore drills

Run these checks regularly without disrupting live traffic:

1. **etcd snapshots**: run `docker exec k3d-platform-mgmt-server-0 k3s etcd-snapshot ls` and confirm recent automatic snapshots exist and are non-empty.
2. **Thunder PVC delete guard + OIDC**: verify the admission guard denies PVC deletion (`--dry-run=server`) and Thunder serves its JWKS.
3. **Disposable restore test** `(not yet verified live)`: restore a mgmt `etcd` snapshot into an isolated container or bootstrap a recovery CNPG `Cluster` in a `staging` namespace, verify data integrity, then tear down the scratch target.

## Verify

```bash
K="kubectl --context k3d-platform-mgmt"

# 1. Management node Ready and etcd snapshots present
$K get nodes
docker exec k3d-platform-mgmt-server-0 k3s etcd-snapshot ls

# 2. All PVCs Bound and Thunder delete-protection VAP enforced
$K get pvc -A
$K -n thunder delete pvc thunder-database-pvc --dry-run=server   # expected: Forbidden (thunder-pvc-delete-protection)
curl -fsS http://thunder.openchoreo.localhost:8080/oauth2/.well-known/openid-configuration | head -c 200; echo

# 3. OpenBao unsealed and Argo CD Applications Synced/Healthy
$K -n openbao exec openbao-0 -- bao status
$K -n argocd get applications
```

## Rollback

- **Failed Thunder sync after PVC rebind**: `thunder-pvc-delete-protection` prevents `hook-failed` from deleting the rebound PVCs, and `$B2` preserves the stopped PV contents. Keep PVs on `Retain`, fix the chart/config in Git, and re-sync.
- **Lost `openbao-unseal` or `data-openbao-0` locally**: re-initialize OpenBao by deleting `pvc/data-openbao-0` and restarting `openbao-0` ([incidents.md](incidents.md#openbao-sealed)), then roll mesh members' `istiod` and `ztunnel` once ESO updates `mesh-root-ca`.

## Related links

- [Operations handbook](../operations.md)
- [Mgmt datastore settings](../dev-environment.md#local-stack-load-and-the-mgmt-datastore)
- [Thunder PVC hook protection](../openchoreo.md#argo-cd-requirements)
- [OpenBao unseal and mesh CA](../multicluster.md#unseal)
- [Harbor registry persistence](../build-plane.md#registry-harbor)
- [CloudNativePG Barman Cloud backups](../data-services.md#backups)
- [Break-glass](break-glass.md)
