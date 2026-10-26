#!/bin/sh
# Build a local LMS image with the optional bitrate UI patch applied.
# Usage: tools/build-lms-patched-image.sh <tag> [output-tag]
set -eu
TAG=${1:-9.1.1}
OUT=${2:-codecswitch-lms:$TAG}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found" >&2
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$ROOT/patches/lms/bitrate-codecs.patch" "$tmp/"

cat > "$tmp/Dockerfile" <<EOF
FROM lmscommunity/lyrionmusicserver:$TAG
USER root
COPY bitrate-codecs.patch /tmp/bitrate-codecs.patch
RUN apt-get update \\
 && apt-get install -y --no-install-recommends patch \\
 && cd /lms \\
 && patch -p1 < /tmp/bitrate-codecs.patch \\
 && rm -f /tmp/bitrate-codecs.patch \\
 && rm -rf /var/lib/apt/lists/*
EOF

docker build -t "$OUT" "$tmp"
echo "Built $OUT"
