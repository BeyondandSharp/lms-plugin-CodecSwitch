#!/bin/sh
# Apply the optional LMS core UI patch for the extended bitrate selector.
# Usage: tools/apply-lms-patch.sh /path/to/lms [--check]
set -eu

LMS_ROOT=${1:-${LMS_ROOT:-}}
MODE=${2:-}
PATCH_FILE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/patches/lms/bitrate-codecs.patch

if [ -z "$LMS_ROOT" ]; then
    echo "usage: $0 /path/to/lms [--check]" >&2
    exit 2
fi
if [ ! -f "$LMS_ROOT/Slim/Web/Settings/Player/Audio.pm" ]; then
    echo "error: $LMS_ROOT does not look like a Lyrion Music Server tree" >&2
    exit 2
fi
if [ ! -f "$PATCH_FILE" ]; then
    echo "error: patch not found: $PATCH_FILE" >&2
    exit 2
fi

if [ "$MODE" = "--check" ]; then
    patch -p1 --dry-run -d "$LMS_ROOT" < "$PATCH_FILE"
    echo "LMS bitrate UI patch applies cleanly."
    exit 0
fi

patch -p1 -d "$LMS_ROOT" < "$PATCH_FILE"
echo "Applied LMS bitrate UI patch to $LMS_ROOT."
echo "Restart LMS and re-apply after LMS upgrades."
