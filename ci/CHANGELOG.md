# Changelog

`ci-vX.Y.Z` releases of `ci/` and the `app-*` reusable workflows, maintained by release-please
([docs/releases.md](../docs/releases.md)).

## [1.2.0](https://github.com/koorikla/platform/compare/ci-v1.1.1...ci-v1.2.0) (2026-11-21)


### Features

* **ci:** app manifest validation in the platform's stack workflows; code-free templates ([#366](https://github.com/koorikla/platform/issues/366)) ([561de3b](https://github.com/koorikla/platform/commit/561de3b45e0e4332c724658e9abf4a4e516e497f))

## [1.1.1](https://github.com/koorikla/platform/compare/ci-v1.1.0...ci-v1.1.1) (2026-11-20)


### Bug Fixes

* **release:** root package without component so single-component grouped releases get tagged ([#313](https://github.com/koorikla/platform/issues/313)) ([#318](https://github.com/koorikla/platform/issues/318)) ([d34c254](https://github.com/koorikla/platform/commit/d34c254adf6c7ccc882df3f32ece0b6d0e3b10e9))

## [1.1.0](https://github.com/koorikla/platform/compare/ci-v1.0.0...ci-v1.1.0) (2026-11-19)


### Features

* **postgresql:** Crossplane Configuration package for the PostgreSQL API ([#239](https://github.com/koorikla/platform/issues/239)) ([7dad12e](https://github.com/koorikla/platform/commit/7dad12e3309ff0b73b0dd1ed3c235f48c71c6d0c))
* release-please with two release lines, platform vX.Y.Z and ci ci-vX.Y.Z ([#222](https://github.com/koorikla/platform/issues/222)) ([dd28954](https://github.com/koorikla/platform/commit/dd2895422477b97c43c0dc1c64e8e9ac6e70712d))


### Bug Fixes

* **ci:** publish toolbox and selftest packages under ghcr.io/koorikla/platform; toolbox tags on ci-v* ([#254](https://github.com/koorikla/platform/issues/254)) ([#263](https://github.com/koorikla/platform/issues/263)) ([db7bcac](https://github.com/koorikla/platform/commit/db7bcac349534a2429809c6744816e0800e2a457))
* QA findings - pin app-* workflow actions by SHA, repoint ci/ templates, live Rust toolchain check, mcp-service tests ([#226](https://github.com/koorikla/platform/issues/226), [#227](https://github.com/koorikla/platform/issues/227)) ([#228](https://github.com/koorikla/platform/issues/228)) ([c760dc6](https://github.com/koorikla/platform/commit/c760dc6157c582f3a7a983a76de7a2ce178251f3))
* **workflow-plane:** pin the toolbox to ghcr.io/koorikla/platform/ci-toolbox ([#254](https://github.com/koorikla/platform/issues/254)) ([#271](https://github.com/koorikla/platform/issues/271)) ([c945e4d](https://github.com/koorikla/platform/commit/c945e4dda5f18ef20d06ffbb9ba60f49d09e62d5))

## 1.0.0 (2026-11-18)

First release from koorikla/platform (moved from the archived koorikla/ci repo, #213).
