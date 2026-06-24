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

# Optional S3 cold cache: layers are pushed to / pulled from an external bucket, so a COLD daemon
# (new project, lost PVC, new cluster) rehydrates instead of rebuilding from scratch. The daemon
# does the S3 I/O — the endpoint is resolved daemon-side (e.g. in-cluster MinIO/OVH Object Storage).
extra=""
if [ -n "${BUILDCAT_S3_BUCKET:-}" ]; then
  s3="type=s3,bucket=$BUILDCAT_S3_BUCKET,region=${BUILDCAT_S3_REGION:-us-east-1},endpoint_url=$BUILDCAT_S3_ENDPOINT,access_key_id=$BUILDCAT_S3_KEY,secret_access_key=$BUILDCAT_S3_SECRET,use_path_style=true,name=$(echo "$REPO" | tr '/' '_')"
  extra="--cache-from $s3 --cache-to $s3,mode=max"
  echo "buildcat: S3 cold cache ON (bucket=$BUILDCAT_S3_BUCKET)"
fi

exec docker buildx build --builder buildcat $extra "$@"
