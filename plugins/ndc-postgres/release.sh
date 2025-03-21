#!/usr/bin/env nix-shell
#!nix-shell -i bash -p gh jq yq

set -e
set -u
set -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

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

echo >&2 'Fetching assets information...'
ASSETS_JSON="$(gh --repo=hasura/ndc-postgres release view --json=assets "$VERSION")"

echo >&2 'Fetching sha256sums...'
SHA256SUM="$(
  gh --repo=hasura/ndc-postgres release download "$VERSION" --pattern 'sha256sum' --output - \
    | jq -R 'split(" +"; "") | {"key": .[1], "value": .[0]}' \
    | jq -s 'from_entries'
)"

echo >&2 'Processing the manifest.json file...'
echo "$ASSETS_JSON" | jq --arg version "$VERSION" --argjson sha256sum "$SHA256SUM" '
{
  "aarch64-apple-darwin": {"selector": "darwin-arm64"},
  "aarch64-unknown-linux-gnu": {"selector": "linux-arm64"},
  "x86_64-apple-darwin": {"selector": "darwin-amd64"},
  "x86_64-pc-windows-msvc": {"selector": "windows-amd64", "extension": ".exe"},
  "x86_64-unknown-linux-gnu": {"selector": "linux-amd64"}
} as $arch_specific_details |
{
  "name": "ndc-postgres",
  "version": $version,
  "shortDescription": "CLI plugin for Hasura ndc-postgres",
  "homepage": "https://hasura.io/connectors/postgres",
  "platforms": (.assets | map(
    (.url | split("/") | last) as $filename
    | select($filename | startswith("ndc-postgres-cli"))
    | ($filename | sub("^ndc-postgres-cli-"; "") | sub("\\.exe$"; "")) as $arch
    | ($arch_specific_details[$arch] // error("arch not supported: " + $arch)) as $details
    | ("hasura-ndc-postgres" + ($details.extension // "")) as $bin
    | {
      "selector": $details.selector,
      "uri": .url,
      "sha256": ($sha256sum[$filename] // error("no sha256sum for filename: " + $filename)),
      "bin": $bin,
      "files": [
        {
          "from": ("./" + $filename),
          "to": $bin
        }
      ]
    }
  ))
}
' | yq --yaml-output . \
  > "$OUTPUT_FILE"

echo >&2 'Done.'
