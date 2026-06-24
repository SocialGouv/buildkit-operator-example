#!/usr/bin/env sh
# CI-AGNOSTIC build via buildcat.
#
# The whole integration is: ask buildd to route this repo to its warm daemon, then point
# `docker buildx` at that endpoint over mTLS. No GitHub/GitLab/Jenkins specifics — any runner
# that can run `docker buildx` and reach the buildcat control plane works the same.
#
#   REPO=group/project ./build.sh -t myimage:tag --push .
#
# Env:
#   BUILDCAT_BUILDD_URL   buildd /route API     (e.g. http://buildcat-buildd.buildcat.svc:8080)
#   BUILDCAT_CERTS_DIR    dir with ca.pem cert.pem key.pem (client mTLS material)
#   REPO                  project identity      (default: the git origin URL)
#   ARCH                  amd64 | arm64         (default: amd64)
set -eu

REPO="${REPO:-$(git config --get remote.origin.url 2>/dev/null || basename "$PWD")}"
ARCH="${ARCH:-amd64}"

endpoint=$(curl -fsS -XPOST "$BUILDCAT_BUILDD_URL/route" \
  -H 'content-type: application/json' \
  -d "{\"repo\":\"$REPO\",\"arch\":\"$ARCH\"}" | jq -r .endpoint)
echo "buildcat: routed $REPO ($ARCH) -> $endpoint"

# buildx reads the cert files at create time — use absolute paths.
certs=$(cd "$BUILDCAT_CERTS_DIR" && pwd)
docker buildx rm buildcat >/dev/null 2>&1 || true
docker buildx create --name buildcat --driver remote \
  --driver-opt "cacert=$certs/ca.pem,cert=$certs/cert.pem,key=$certs/key.pem" \
  "$endpoint" --use

exec docker buildx build --builder buildcat "$@"
