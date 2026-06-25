#!/usr/bin/env sh
# CI-AGNOSTIC build via buildcat.
#
# The whole integration is: ask buildd to route this repo to its warm daemon, then point
# `docker buildx` at that endpoint over mTLS. No GitHub/GitLab/Jenkins specifics — any runner that
# can run `docker buildx` + curl + jq and reach the buildcat control plane works the same.
#
#   REPO=group/project ./build.sh -t myimage:tag --push .
#
# Env:
#   BUILDCAT_BUILDD_URL   buildd /route API     (e.g. http://buildcat-buildd.buildcat.svc:8080)
#   BUILDCAT_CERTS_DIR    dir with ca.pem cert.pem key.pem (client mTLS material)
#   REPO                  project identity      (default: the git origin URL)
#   NAME                  optional monorepo component (one daemon per image)
#   ARCH                  amd64 | arm64         (default: amd64)
#
# The S3 cold cache, if buildd has one configured, is applied automatically from the /route
# response — no S3 config or credentials on this side (the daemon holds them).
set -eu

REPO="${REPO:-$(git config --get remote.origin.url 2>/dev/null || basename "$PWD")}"
ARCH="${ARCH:-amd64}"
NAME="${NAME:-}"

resp=$(curl -fsS -XPOST "$BUILDCAT_BUILDD_URL/route" \
  -H 'content-type: application/json' \
  -d "{\"repo\":\"$REPO\",\"name\":\"$NAME\",\"arch\":\"$ARCH\"}")
endpoint=$(printf '%s' "$resp" | jq -r .endpoint)
echo "buildcat: routed $REPO${NAME:+/$NAME} ($ARCH) -> $endpoint"

# buildx reads the cert files at create time — use absolute paths.
certs=$(cd "$BUILDCAT_CERTS_DIR" && pwd)
docker buildx rm buildcat >/dev/null 2>&1 || true
docker buildx create --name buildcat --driver remote \
  --driver-opt "cacert=$certs/ca.pem,cert=$certs/cert.pem,key=$certs/key.pem" \
  "$endpoint" --use

# Cold cache: buildd hands us the project's cache reference (no creds — the daemon holds them), so a
# COLD daemon (new project / lost PVC / new cluster) rehydrates instead of rebuilding from scratch.
extra=""
if [ "$(printf '%s' "$resp" | jq -r '.cache.type // empty')" = "s3" ]; then
  s3="type=s3,bucket=$(printf '%s' "$resp" | jq -r .cache.bucket),name=$(printf '%s' "$resp" | jq -r .cache.name)"
  rg=$(printf '%s' "$resp" | jq -r '.cache.region // empty')
  ep=$(printf '%s' "$resp" | jq -r '.cache.endpointUrl // empty')
  [ -n "$rg" ] && s3="$s3,region=$rg"
  [ -n "$ep" ] && s3="$s3,endpoint_url=$ep,use_path_style=true"
  extra="--cache-from $s3 --cache-to $s3,mode=max"
  echo "buildcat: S3 cold cache (project-managed) ON"
fi

exec docker buildx build --builder buildcat $extra "$@"
