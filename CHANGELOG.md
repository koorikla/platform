# Changelog

Platform releases (`vX.Y.Z`), maintained by release-please ([docs/releases.md](docs/releases.md)).

## [0.9.0](https://github.com/koorikla/platform/compare/v0.8.0...v0.9.0) (2026-11-21)


### Features

* **ci:** app manifest validation in the platform's stack workflows; code-free templates ([#366](https://github.com/koorikla/platform/issues/366)) ([561de3b](https://github.com/koorikla/platform/commit/561de3b45e0e4332c724658e9abf4a4e516e497f))

## [0.8.0](https://github.com/koorikla/platform/compare/v0.7.0...v0.8.0) (2026-11-21)


### Features

* **crossplane:** Project tooling contract for every API package, crossplane-api golden path, verified inner loop ([#240](https://github.com/koorikla/platform/issues/240)) ([#362](https://github.com/koorikla/platform/issues/362)) ([3c4222a](https://github.com/koorikla/platform/commit/3c4222a7d9f731334dfaef087ac903b65db4b415))
* **mysql:** enable the MySQL API end to end with the MOCO operator addon (Fixes [#256](https://github.com/koorikla/platform/issues/256)) ([#363](https://github.com/koorikla/platform/issues/363)) ([aecd0bf](https://github.com/koorikla/platform/commit/aecd0bfab559559459ffb4b9d9d90fcbd103af76))
* **openchoreo:** opt-in app metrics ClusterTrait + app config files ([#252](https://github.com/koorikla/platform/issues/252)) ([#361](https://github.com/koorikla/platform/issues/361)) ([ef8c848](https://github.com/koorikla/platform/commit/ef8c8488f111f7204ef93a4e2452a08baa35c173))


### Bug Fixes

* **argocd:** immutable-field changes no longer deadlock server-side diff ([#281](https://github.com/koorikla/platform/issues/281)) ([#359](https://github.com/koorikla/platform/issues/359)) ([c8f6ca6](https://github.com/koorikla/platform/commit/c8f6ca63c383fcdc4e27c105b4e33749ca2c574d))
* **strimzi:** keep HBONE 15008 reachable for Kafka pods in Istio ambient cells ([#210](https://github.com/koorikla/platform/issues/210)) ([#357](https://github.com/koorikla/platform/issues/357)) ([59be6f0](https://github.com/koorikla/platform/commit/59be6f053323ce11c35bf9dded30cbbefe1d534e))

## [0.7.0](https://github.com/koorikla/platform/compare/v0.6.0...v0.7.0) (2026-11-20)


### Features

* **kyverno-policies:** per-cell AuthorizationPolicy admits only the cell and platform identities ([#324](https://github.com/koorikla/platform/issues/324)) ([#347](https://github.com/koorikla/platform/issues/347)) ([a77bfa0](https://github.com/koorikla/platform/commit/a77bfa06ab086cdee0659100b11711d6755bf891))


### Bug Fixes

* **bootstrap:** mgmt etcd without fsync and long k3s leases ([#344](https://github.com/koorikla/platform/issues/344)) ([#349](https://github.com/koorikla/platform/issues/349)) ([11d9f60](https://github.com/koorikla/platform/commit/11d9f60f61242be70eb07ad326137e254d68492b))
* **openchoreo:** per-project developer authz (negative test), correct preview comment, reconcile test gaps ([#335](https://github.com/koorikla/platform/issues/335)) ([#348](https://github.com/koorikla/platform/issues/348)) ([5ca9014](https://github.com/koorikla/platform/commit/5ca9014e0ce569d9ad9298584bfa59a4996e89ef))

## [0.6.0](https://github.com/koorikla/platform/compare/v0.5.0...v0.6.0) (2026-11-20)


### Features

* **demo-check:** step 9 hello-world database claim Ready check ([#70](https://github.com/koorikla/platform/issues/70)) ([#326](https://github.com/koorikla/platform/issues/326)) ([cda9288](https://github.com/koorikla/platform/commit/cda92886c7ddcd741d593c5f56a0e4adba410332))
* previews provision the app's Resources; ResourceReleaseBindings need no hand-computed release ([#330](https://github.com/koorikla/platform/issues/330)) ([#333](https://github.com/koorikla/platform/issues/333)) ([8571514](https://github.com/koorikla/platform/commit/8571514635affe49b02c573965194a78cbaa1c3b))


### Bug Fixes

* **build:** retry infra-killed build steps and failed missing-digest rebuilds (development stuck on unbuilt image) ([#343](https://github.com/koorikla/platform/issues/343)) ([b4d4f41](https://github.com/koorikla/platform/commit/b4d4f4152ff1b5f1788c4ae159d20bca3ea74723))
* **demo-check:** app held by an active deny sync window (production freeze) is PENDING with the reason, not FAIL ([#342](https://github.com/koorikla/platform/issues/342)) ([8d7dcd8](https://github.com/koorikla/platform/commit/8d7dcd867f0382a842fb9f0bb816308b422adc0d))
* **kyverno-policies:** admit exactly the pinned CloudNativePG images in production cells ([#327](https://github.com/koorikla/platform/issues/327)) ([#329](https://github.com/koorikla/platform/issues/329)) ([4f2f1a3](https://github.com/koorikla/platform/commit/4f2f1a39e242fd71e71975d2c159fd0c5c9d34a8))
* **kyverno-policies:** preview CiliumNetworkPolicy uses top-level specs (Cilium rejected it; whole preview generate failed) ([#339](https://github.com/koorikla/platform/issues/339)) ([d50193f](https://github.com/koorikla/platform/commit/d50193fce35d15658c617a970f19753f202165b1))
* **openbao:** preview GeneratingPolicy syncs after its RBAC (Kyverno never re-checks RBACPermissionsGranted) ([#337](https://github.com/koorikla/platform/issues/337)) ([e2506e6](https://github.com/koorikla/platform/commit/e2506e651fc3ea016b25a1a72f92c6d213e83804))
* **openbao:** preview tenant GeneratingPolicy readable by Kyverno's reports controller (clean-bootstrap stall) ([#336](https://github.com/koorikla/platform/issues/336)) ([0f225a3](https://github.com/koorikla/platform/commit/0f225a328fbd27c1e870dd28a858328829083e1e))
* PR previews read their tenant's OpenBao secrets and run their own PostgreSQL ([#267](https://github.com/koorikla/platform/issues/267), [#331](https://github.com/koorikla/platform/issues/331)) ([#334](https://github.com/koorikla/platform/issues/334)) ([782fb53](https://github.com/koorikla/platform/commit/782fb53f8c7bb1de1c5b1940f1e8109daff139ce))
* **previews:** teardown leaks the preview's ResourceReleaseBinding (stuck finalizer) and its OpenBao descriptor ([#345](https://github.com/koorikla/platform/issues/345)) ([49f7e36](https://github.com/koorikla/platform/commit/49f7e36c247e8780f36f35f06096f6ba2607676c))
* **task:** test:changed defaults BASE to origin/main (shellQuote of an unset var failed) ([#332](https://github.com/koorikla/platform/issues/332)) ([67dd8a7](https://github.com/koorikla/platform/commit/67dd8a73c322352bd642f3a79b047833d0b5f21a))
* **tenant:** app Applications retry without limit (clean bootstrap: environments arrive later) ([#338](https://github.com/koorikla/platform/issues/338)) ([801401e](https://github.com/koorikla/platform/commit/801401ee4afb3ad31dfd90add70d789745d2a53e))

## [0.5.0](https://github.com/koorikla/platform/compare/v0.4.0...v0.5.0) (2026-11-20)


### Features

* **promotion-gate:** HTTP smoke probe on in installation local via node IP ([#156](https://github.com/koorikla/platform/issues/156)) ([#319](https://github.com/koorikla/platform/issues/319)) ([40af5e4](https://github.com/koorikla/platform/commit/40af5e44f860e8c4b1f85e53eece42934eac6b3e))


### Bug Fixes

* **console:** hide Cost Insights / Cost Analysis while FinOps is off ([#322](https://github.com/koorikla/platform/issues/322)) ([a5ce3a4](https://github.com/koorikla/platform/commit/a5ce3a4d6bd659646b6af2811b2afe429c51a05b)), closes [#207](https://github.com/koorikla/platform/issues/207)
* **release:** root package without component so single-component grouped releases get tagged ([#313](https://github.com/koorikla/platform/issues/313)) ([#318](https://github.com/koorikla/platform/issues/318)) ([d34c254](https://github.com/koorikla/platform/commit/d34c254adf6c7ccc882df3f32ece0b6d0e3b10e9))
* **telemetry:** scrape STRICT-mTLS ambient cells from inside the mesh ([#323](https://github.com/koorikla/platform/issues/323)) ([d374e43](https://github.com/koorikla/platform/commit/d374e43c5099c7abb211490acd4cc8e5cea7326d)), closes [#209](https://github.com/koorikla/platform/issues/209)

## [0.4.0](https://github.com/koorikla/platform/compare/v0.3.0...v0.4.0) (2026-11-19)


### Features

* **addons:** values.schema.json for the 14 wrapper addons; strict schema contract (Wave C) ([#312](https://github.com/koorikla/platform/issues/312)) ([b6fe389](https://github.com/koorikla/platform/commit/b6fe389bad7de7bcd4fb05ec5d9fd46eb2150731)), closes [#116](https://github.com/koorikla/platform/issues/116)


### Bug Fixes

* **demo-check:** no promotion-gate run before the first promotion is PENDING, not FAIL ([#317](https://github.com/koorikla/platform/issues/317)) ([41c3d43](https://github.com/koorikla/platform/commit/41c3d43172b6b82412771b591491368bf7b01e98))
* **openbao:** tenant CA copy syncs after openbao-ca-bundle (clean-bootstrap deadlock) ([#316](https://github.com/koorikla/platform/issues/316)) ([41c6543](https://github.com/koorikla/platform/commit/41c65430690558e2a71ca068983e6c475cebe026))
* **schema:** keep security reasons in validate.yaml ([#311](https://github.com/koorikla/platform/issues/311)) ([#315](https://github.com/koorikla/platform/issues/315)) ([adc3782](https://github.com/koorikla/platform/commit/adc378228a268b67abec52f6227ffbb31a689d78))

## [0.3.0](https://github.com/koorikla/platform/compare/v0.2.0...v0.3.0) (2026-11-19)


### Features

* **addons:** values.schema.json for crossplane, mesh, openbao, harbor, thunder (Wave C) ([#308](https://github.com/koorikla/platform/issues/308)) ([604182e](https://github.com/koorikla/platform/commit/604182e3f32af48a88945fbd20aaf0dd5fc16304)), closes [#116](https://github.com/koorikla/platform/issues/116)
* **addons:** values.schema.json for kyverno-policies, secret-stores, external-dns, argo-events ([#116](https://github.com/koorikla/platform/issues/116)) ([#309](https://github.com/koorikla/platform/issues/309)) ([bc7f467](https://github.com/koorikla/platform/commit/bc7f467168690a5fc729abed492c7007a49fbeb5))
* **addons:** values.schema.json for observability-plane, workflow-plane, telemetry (Wave C) ([#305](https://github.com/koorikla/platform/issues/305)) ([f17ae7b](https://github.com/koorikla/platform/commit/f17ae7b20afe4339f062f5b4a9555f271b445069))
* **cluster:** values.schema.json + one templates/validate.yaml for charts/cluster ([#306](https://github.com/koorikla/platform/issues/306)) ([966abda](https://github.com/koorikla/platform/commit/966abda897f4b8f186140244c053150ca57bf81b))
* **mesh:** single-source the ambient probe SNAT address + Istio bump check ([#287](https://github.com/koorikla/platform/issues/287)) ([#288](https://github.com/koorikla/platform/issues/288)) ([7cf486c](https://github.com/koorikla/platform/commit/7cf486cd56b5fde5631e0157f04efc332d136e9e))
* **openchoreo:** values.schema.json for openchoreo-platform/control-plane/data-plane (Wave C) ([#307](https://github.com/koorikla/platform/issues/307)) ([0a0fa9b](https://github.com/koorikla/platform/commit/0a0fa9b139cbb5fa5637bcf0cb7d817853065d98)), closes [#116](https://github.com/koorikla/platform/issues/116)
* **templates:** GitHub org + manifest-created scaffolder App, documented (Refs [#109](https://github.com/koorikla/platform/issues/109)) ([#275](https://github.com/koorikla/platform/issues/275)) ([ab6e383](https://github.com/koorikla/platform/commit/ab6e38348badffd6c4f819d2896f1fb74a7fef06))
* values.schema.json for platform (catalog shape), tenant, preview and small addons + schema contract test ([#310](https://github.com/koorikla/platform/issues/310)) ([2770721](https://github.com/koorikla/platform/commit/27707215e6f5721168efbde2a393e5c51c94ce52))


### Bug Fixes

* **kyverno-policies:** admit kubelet probes from ambient's SNAT source in every cell ([#286](https://github.com/koorikla/platform/issues/286)) ([00b5d16](https://github.com/koorikla/platform/commit/00b5d16b5ea853aff3483b6bab782a86f71804db))
* **kyverno:** 60s leader leases so etcd stalls do not restart every controller ([#284](https://github.com/koorikla/platform/issues/284)) ([81cfccb](https://github.com/koorikla/platform/commit/81cfccb0a71ece18f32fb5cf0c5b2f567611dfb6))
* **openbao:** seed the demo tenant secret on every clean bootstrap with the tenant's writer identity ([#285](https://github.com/koorikla/platform/issues/285)) ([9130ccd](https://github.com/koorikla/platform/commit/9130ccd2996806c22b10f87035437c2894114ef4))
* **test:** hook allowlist entries must name an existing addon ([#299](https://github.com/koorikla/platform/issues/299)) ([#300](https://github.com/koorikla/platform/issues/300)) ([a3a7657](https://github.com/koorikla/platform/commit/a3a76575d74aecfa3689fec1df714d6c215988c6))
* **test:** hook allowlist staleness only judged for addons rendered in this run (scoped PR CI) ([#298](https://github.com/koorikla/platform/issues/298)) ([4990cae](https://github.com/koorikla/platform/commit/4990caedde4425430648c2d13ffc80809b39eaf4))
* **test:** Windows Git Bash portability (CRLF, process substitution) ([#304](https://github.com/koorikla/platform/issues/304)) ([821f9f7](https://github.com/koorikla/platform/commit/821f9f712137ef74b168c4d6274005365afd543a))

## [0.2.0](https://github.com/koorikla/platform/compare/v0.1.0...v0.2.0) (2026-11-19)


### ⚠ BREAKING CHANGES

* **platform:** remove examples/ (east-west custom chart); apps ship as OpenChoreo objects ([#234](https://github.com/koorikla/platform/issues/234))

### Features

* **apps:** resilience defaults for OpenChoreo components - spread, PDB, graceful shutdown, priority; production enforcement ([#251](https://github.com/koorikla/platform/issues/251)) ([#264](https://github.com/koorikla/platform/issues/264)) ([a54aec7](https://github.com/koorikla/platform/commit/a54aec79c1c24c3d958adbfb2b7ba4ec85330f4f))
* **ci:** scope PR validation to changed charts, addons, packages and ci stacks ([#242](https://github.com/koorikla/platform/issues/242)) ([6a6038a](https://github.com/koorikla/platform/commit/6a6038a505ece84cea64a07d2910126729c4870f))
* **crossplane:** layout-only Configuration packages for MySQL, Valkey, Bucket, KafkaTopic (Refs [#241](https://github.com/koorikla/platform/issues/241)) ([#260](https://github.com/koorikla/platform/issues/260)) ([91ad14b](https://github.com/koorikla/platform/commit/91ad14b89de78bd1fbc1df641574aed10222986c))
* **crossplane:** pin the split postgresql Configuration and its embedded function compose-postgresql (Refs [#116](https://github.com/koorikla/platform/issues/116)) ([#272](https://github.com/koorikla/platform/issues/272)) ([e009b04](https://github.com/koorikla/platform/commit/e009b044644b889f9f76590463f54e6647927956))
* **postgresql:** Crossplane Configuration package for the PostgreSQL API ([#239](https://github.com/koorikla/platform/issues/239)) ([7dad12e](https://github.com/koorikla/platform/commit/7dad12e3309ff0b73b0dd1ed3c235f48c71c6d0c))
* release-please with two release lines, platform vX.Y.Z and ci ci-vX.Y.Z ([#222](https://github.com/koorikla/platform/issues/222)) ([dd28954](https://github.com/koorikla/platform/commit/dd2895422477b97c43c0dc1c64e8e9ac6e70712d))
* **secrets:** app secrets from OpenBao via OpenChoreo SecretReference, demo-check + negatives + docs ([#250](https://github.com/koorikla/platform/issues/250)) ([#262](https://github.com/koorikla/platform/issues/262)) ([e14372a](https://github.com/koorikla/platform/commit/e14372aded430bebc67e905861baf4563781c45a))


### Bug Fixes

* **apps:** app PriorityClasses never preempt platform pods ([#276](https://github.com/koorikla/platform/issues/276)) ([#279](https://github.com/koorikla/platform/issues/279)) ([45aafff](https://github.com/koorikla/platform/commit/45aafff3687c4f015d5e9742703e74fb20de6c9c))
* **argocd:** Argo CD detects changes to hook-rendered config (thunder-bootstrap ExternalSecret, authz bootstrap) ([#221](https://github.com/koorikla/platform/issues/221)) ([#278](https://github.com/koorikla/platform/issues/278)) ([4dd400f](https://github.com/koorikla/platform/commit/4dd400f8e4dce049d8d5c05c2e3351ee46ecdd1a))
* **argocd:** detect Argo Workflows spec changes under server-side diff ([#184](https://github.com/koorikla/platform/issues/184)) ([#273](https://github.com/koorikla/platform/issues/273)) ([0a5d2f4](https://github.com/koorikla/platform/commit/0a5d2f45a27725fc9c362d80ed5128914f5d16f0))
* **ci:** docs changes run the tests that read them ([#253](https://github.com/koorikla/platform/issues/253)) ([#261](https://github.com/koorikla/platform/issues/261)) ([39599e7](https://github.com/koorikla/platform/commit/39599e7ad65258a8d989f9e28fcb8d514bf78b3c))
* **ci:** docs read through a path prefix also select their tests ([#277](https://github.com/koorikla/platform/issues/277)) ([#280](https://github.com/koorikla/platform/issues/280)) ([3a4738b](https://github.com/koorikla/platform/commit/3a4738bb8d5b49a2e4ee7a7f8a91c14c2d5e6fae))
* **ci:** publish toolbox and selftest packages under ghcr.io/koorikla/platform; toolbox tags on ci-v* ([#254](https://github.com/koorikla/platform/issues/254)) ([#263](https://github.com/koorikla/platform/issues/263)) ([db7bcac](https://github.com/koorikla/platform/commit/db7bcac349534a2429809c6744816e0800e2a457))
* **cluster:** byo unittests point at templates/common paths; contract test rejects stale unittest template paths ([#236](https://github.com/koorikla/platform/issues/236)) ([#238](https://github.com/koorikla/platform/issues/238)) ([474e8af](https://github.com/koorikla/platform/commit/474e8af27553368b262f7fc5d10318edb53bd38d))
* **crossplane:** package signature verification off until Crossplane reads Sigstore bundles ([#247](https://github.com/koorikla/platform/issues/247)) ([#248](https://github.com/koorikla/platform/issues/248)) ([020fbc0](https://github.com/koorikla/platform/commit/020fbc0658edf9eb3cf1b7659558209a41664d01))
* **openchoreo-data-plane:** gate the agent on every addon CRD traits and resource types render ([#255](https://github.com/koorikla/platform/issues/255)) ([#265](https://github.com/koorikla/platform/issues/265)) ([d2a68a1](https://github.com/koorikla/platform/commit/d2a68a1c570b26a3106d01f23c3060ddba5715dc))
* **openchoreo-data-plane:** start the cluster agent only after opt-in addon CRDs exist ([#246](https://github.com/koorikla/platform/issues/246)) ([#249](https://github.com/koorikla/platform/issues/249)) ([e57329f](https://github.com/koorikla/platform/commit/e57329f7f91e54e7ef9f1cb29784258c192676c8))
* QA findings - pin app-* workflow actions by SHA, repoint ci/ templates, live Rust toolchain check, mcp-service tests ([#226](https://github.com/koorikla/platform/issues/226), [#227](https://github.com/koorikla/platform/issues/227)) ([#228](https://github.com/koorikla/platform/issues/228)) ([c760dc6](https://github.com/koorikla/platform/commit/c760dc6157c582f3a7a983a76de7a2ce178251f3))
* **workflow-plane:** pin the toolbox to ghcr.io/koorikla/platform/ci-toolbox ([#254](https://github.com/koorikla/platform/issues/254)) ([#271](https://github.com/koorikla/platform/issues/271)) ([c945e4d](https://github.com/koorikla/platform/commit/c945e4dda5f18ef20d06ffbb9ba60f49d09e62d5))


### Performance Improvements

* **bootstrap:** clean bootstrap 33 -&gt; ~15 min warm (registry caches, 1m backoff, 120s resync, task timings) ([#266](https://github.com/koorikla/platform/issues/266)) ([018a996](https://github.com/koorikla/platform/commit/018a996d87db3d87c0a737709a997b2fb8f81697))


### Code Refactoring

* **platform:** remove examples/ (east-west custom chart); apps ship as OpenChoreo objects ([#234](https://github.com/koorikla/platform/issues/234)) ([5a13e94](https://github.com/koorikla/platform/commit/5a13e9449859703466d97105892ea5731811a978))

## 0.1.0 (2026-11-18)

First tagged release: CAPI + Argo CD + OpenChoreo + ESO platform lab (see [README.md](README.md)).
