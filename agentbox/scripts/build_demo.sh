#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
image=agentbox-runtime:local
output="$root/examples/mover/mover"
temporary="$output.tmp"

cleanup() {
    rm -f "$temporary"
}
trap cleanup EXIT INT TERM

docker build -q -t "$image" -f "$root/environment/Dockerfile" "$root" >/dev/null
docker run --rm --network=none --entrypoint cat "$image" /opt/agentbox/mover >"$temporary"
chmod 0755 "$temporary"
mv "$temporary" "$output"
