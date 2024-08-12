#!/usr/bin/env bash

set -e
set -u
set -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

NIX=false
if command -v nix > /dev/null; then
  NIX=true
fi

if ! GH="$(command -v gh)"; then
  if $NIX; then
    GH=( nix run 'nixpkgs#gh' '--' )
  else
    echo >&2 'Install the GitHub CLI (gh): https://cli.github.com/'
    exit 2
  fi
fi

function gh {
  "${GH[@]}" "$@"
}

if ! JQ="$(command -v jq)"; then
  if $NIX; then
    JQ=( nix run 'nixpkgs#jq' '--' )
  else
    echo >&2 'Install jq: https://jqlang.github.io/jq/'
    exit 2
  fi
fi

function jq {
  "${JQ[@]}" "$@"
}

if ! YQ="$(command -v yq)"; then
  if $NIX; then
    YQ=( nix run 'nixpkgs#yq' '--' )
  else
    echo >&2 'Install yq: https://kislyuk.github.io/yq/'
    exit 2
  fi
fi

function yq {
  "${YQ[@]}" "$@"
}

if [[ $# -ne 1 ]]; then
  echo >&2 "Usage: ${BASH_SOURCE[0]} VERSION"
  exit 2
fi

VERSION="$1"

OUTPUT_DIRECTORY="${PWD}/${VERSION}"
OUTPUT_FILE="${OUTPUT_DIRECTORY}/manifest.yaml"

if [[ -e "$OUTPUT_FILE" ]]; then
  echo >&2 "${OUTPUT_FILE} already exists."
  echo >&2
  echo >&2 'Refusing to go any further. Delete the file and try again.'
  exit 1
fi

mkdir -p "$OUTPUT_DIRECTORY"

ASSETS_JSON="$(gh --repo=hasura/ndc-postgres release view --json=assets "$VERSION")"

SHA256SUM="$(
  gh --repo=hasura/ndc-postgres release download "$VERSION" --pattern 'sha256sum' --output - \
    | jq -R 'split(" +"; "") | {"key": .[1], "value": .[0]}' \
    | jq -s 'from_entries'
)"

echo "$ASSETS_JSON" | jq --arg version "$VERSION" --argjson sha256sum "$SHA256SUM" '
{
  "aarch64-apple-darwin": "darwin-arm64",
  "aarch64-unknown-linux-gnu": "linux-arm64",
  "x86_64-apple-darwin": "darwin-amd64",
  "x86_64-pc-windows-msvc": "windows-amd64",
  "x86_64-unknown-linux-gnu": "linux-amd64"
} as $selectors |
{
  "name": "ndc-postgres",
  "version": $version,
  "shortDescription": "CLI plugin for Hasura ndc-postgres",
  "homepage": "https://hasura.io/connectors/postgres",
  "platforms": (.assets | map(
    (.url | split("/") | last) as $filename
    | select($filename | startswith("ndc-postgres-cli"))
    | ($filename | sub("^ndc-postgres-cli-"; "") | sub("\\.exe$"; "")) as $arch
    | {
      "selector": ($selectors[$arch] // error("no selector for the arch: " + $arch)),
      "uri": .url,
      "sha256": ($sha256sum[$filename] // error("no sha256sum for filename: " + $filename)),
      "bin": "hasura-ndc-postgres",
      "files": [
        {
          "from": ("./" + $filename),
          "to": "hasura-ndc-postgres"
        }
      ]
    }
  ))
}
' | yq --yaml-output . \
  > "$OUTPUT_FILE"
