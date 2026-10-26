#!/bin/sh
# Server-side smoke test for CodecSwitch.
#
# Starts the official LMS 9.0.0 and 9.1.1 images with the built plugin mounted,
# waits for the web UI, checks the CodecSwitch server settings page and scans
# the log for plugin load errors.  No player is created and no playback is
# tested.
set -eu

cd "$(dirname "$0")/.."

IMAGE_PREFIX="${IMAGE_PREFIX:-lmscommunity/lyrionmusicserver}"
PORT_BASE="${SMOKE_PORT_BASE:-19100}"

command -v docker >/dev/null 2>&1 || {
    echo "docker not found" >&2
    exit 1
}
command -v curl >/dev/null 2>&1 || {
    echo "curl not found" >&2
    exit 1
}

make dist

name=""
cleanup() {
    if [ -n "${name:-}" ]; then
        docker rm -f "$name" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

idx=0
for tag in 9.0.0 9.1.1; do
    idx=$((idx + 1))
    port=$((PORT_BASE + idx))
    name="codecswitch-smoke-$tag-$$"
    image="$IMAGE_PREFIX:$tag"

    echo "== $image (port $port)"
    docker run -d --rm --name "$name" \
        -p "$port:9000" \
        -v "$PWD/dist/CodecSwitch:/config/cache/Plugins/CodecSwitch" \
        "$image" >/dev/null

    ok=0
    for i in $(seq 1 90); do
        code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" || true)
        if [ "$code" != "000" ] && [ -n "$code" ]; then
            ok=1
            break
        fi
        sleep 1
    done

    if [ "$ok" -ne 1 ]; then
        echo "LMS did not start; log follows:" >&2
        docker logs "$name" >&2 || true
        exit 1
    fi

    page_code=$(curl -s -o /tmp/codecswitch-smoke-page.$$ -w '%{http_code}' \
        "http://127.0.0.1:$port/plugins/CodecSwitch/settings/basic.html" || true)
    if [ "$page_code" != "200" ]; then
        echo "settings page returned $page_code" >&2
        cat /tmp/codecswitch-smoke-page.$$ >&2 || true
        docker logs "$name" >&2 || true
        rm -f /tmp/codecswitch-smoke-page.$$
        exit 1
    fi

    if ! grep -q 'CodecSwitch' /tmp/codecswitch-smoke-page.$$; then
        echo "settings page does not mention CodecSwitch" >&2
        rm -f /tmp/codecswitch-smoke-page.$$
        exit 1
    fi
    rm -f /tmp/codecswitch-smoke-page.$$

    logs=$(docker logs "$name" 2>&1 || true)
    if printf '%s\n' "$logs" | grep -q "Can't locate Plugins/CodecSwitch"; then
        echo "plugin module failed to load:" >&2
        printf '%s\n' "$logs" >&2
        exit 1
    fi
    if printf '%s\n' "$logs" | grep -qi "Plugin CodecSwitch failed"; then
        echo "plugin initialization failed:" >&2
        printf '%s\n' "$logs" >&2
        exit 1
    fi

    echo "PASS $tag"
    docker stop "$name" >/dev/null
    name=""
done

echo "CodecSwitch Docker smoke tests passed."
