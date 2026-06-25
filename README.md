# buildkit-operator-example

A tiny app whose image is built **through [buildkit-operator](https://github.com/SocialGouv/buildkit-operator)** —
the distributed BuildKit service that gives every repo a hot, auto-provisioned `buildkitd` daemon
with a persistent cache.

## buildkit-operator is CI-agnostic

The entire integration is one portable script, [`build.sh`](build.sh): ask `buildd` to **route**
this repo to its warm daemon (`POST /route`), then point `docker buildx` at that endpoint over
**mTLS**. Nothing is GitHub/GitLab/Jenkins specific.

```sh
REPO=group/project ./build.sh -t myimage:tag --push .
```

The same `build.sh` is called from:

- **GitLab** — [`.gitlab-ci.yml`](.gitlab-ci.yml)
- **GitHub** — [`.github/workflows/build.yml`](.github/workflows/build.yml)
- a plain shell, Jenkins, Tekton, … — anything that runs `docker buildx` and can reach the
  buildkit-operator control plane.

The only platform-specific concern is **reachability**: the build job must reach buildkit-operator's
in-cluster Services (`buildkit-operator-buildd:8080` + the daemon `:1234`). Run your CI runners in the same
cluster (any executor), or expose buildkit-operator via an Ingress/LB with mTLS.

## What it demonstrates

`RUN --mount=type=cache npm install` reuses the **cache mount** kept warm by this repo's daemon —
so installs stay fast across builds even when an upstream layer changes, and concurrent builds of
this repo share it. The daemon (and its Cinder gen2 PVC) is auto-provisioned, scales to zero when
idle, and reattaches the cache on the next build. Layers can also be exported to **S3** for
cross-daemon / cold-start sharing.

## Setup

Provide the buildkit-operator **client** mTLS material (minted from the buildkit-operator CA via
`deploy/cert/create-certs.sh`) to the job as `BUILDCAT_CA` / `BUILDCAT_CERT` / `BUILDCAT_KEY`
(base64) and set `BUILDCAT_BUILDD_URL`.
