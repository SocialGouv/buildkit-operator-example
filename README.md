# buildcat-example

A tiny app whose CI builds its image **through [buildcat](https://github.com/SocialGouv/buildcat)**
— the distributed BuildKit service that gives every repo a hot, auto-provisioned `buildkitd`
daemon with a persistent cache.

## How it works

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs on the **`arc-runners`**
self-hosted runners (inside the cluster, so it can reach buildcat's Services) and:

1. asks `buildd` to **route** this repo to its warm daemon — `POST /route {repo, arch}` returns the
   daemon's mTLS endpoint (the daemon is created + kept warm on demand);
2. points `docker buildx` at that endpoint over **mTLS** (the `remote` driver);
3. builds. The `RUN --mount=type=cache npm install` reuses the **same cache mount** kept by the warm
   daemon — so installs are fast across builds, and concurrent builds of this repo share it.

There is no per-job BuildKit to cold-start and no cache to download: the daemon (and its Cinder
gen2 PVC) is already warm, scales to zero when idle, and reattaches the cache on the next build.

## Setup

The workflow expects three repo secrets holding the buildcat **client** mTLS material (base64):
`BUILDCAT_CA`, `BUILDCAT_CERT`, `BUILDCAT_KEY` (minted from the buildcat CA via
`deploy/cert/create-certs.sh`). The `arc-runners` image must provide `docker buildx`, `curl`, `jq`.

## Run locally against buildcat

```bash
kubectl -n buildcat port-forward svc/buildkitd-<key> 1234 &
docker buildx create --name buildcat --driver remote \
  --driver-opt cacert=ca.pem,cert=cert.pem,key=key.pem tcp://127.0.0.1:1234 --use
docker buildx build -t buildcat-example .
```
