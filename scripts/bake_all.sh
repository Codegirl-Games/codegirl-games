#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONTENT_ROOT="${CONTENT_ROOT:-content/characters}"
OUT_ROOT="${OUT_ROOT:-assets_baked/characters}"

if [[ ! -d "$CONTENT_ROOT" ]]; then
	echo "missing content root: $CONTENT_ROOT" >&2
	exit 1
fi

shopt -s nullglob
manifests=("$CONTENT_ROOT"/*/manifest.json)
if [[ ${#manifests[@]} -eq 0 ]]; then
	echo "no character manifests under $CONTENT_ROOT" >&2
	exit 1
fi

for manifest in "${manifests[@]}"; do
	char_dir="$(dirname "$manifest")"
	name="$(basename "$char_dir")"
	out_dir="$OUT_ROOT/$name"
	mkdir -p "$out_dir"
	echo "baking $name -> $out_dir"
	odin run assetbake -- "$char_dir" "$out_dir"
done

echo "baked ${#manifests[@]} character(s)"
