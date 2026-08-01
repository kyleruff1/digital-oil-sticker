#!/bin/sh
# Verify the catalog artifact against its manifest.
#
# The catalog IS the product. A truncated, swapped, or stale artifact would
# ship and stay invisible until a user got a wrong answer, so this runs at
# image build (against the build context) and again in the runtime stage
# (against what actually shipped).
#
# This lives in a file rather than inline in the Dockerfile because it did not
# survive being inlined: a `sed` backreference passed through the Dockerfile
# parser, the shell, and BuildKit arrived as a literal 0x01 byte, and the check
# failed on its own quoting rather than on the artifact. A verification step
# that can fail for reasons unrelated to what it verifies is worse than none —
# it trains you to ignore it. There are no backreferences here.
#
# Usage: verify_catalog.sh <catalog.sqlite3> <catalog-manifest.json> [--expect-no-fixtures]
#
# `--expect-no-fixtures` additionally asserts that no test fixture sits beside
# the production catalog. That is correct inside the image (.dockerignore keeps
# them out of the build context) and deliberately NOT the default, because in a
# developer working tree the fixtures are supposed to be there.
#
# Exits non-zero with a distinct message per failure mode.

set -eu

catalog="${1:?usage: verify_catalog.sh <catalog> <manifest> [--expect-no-fixtures]}"
manifest="${2:?usage: verify_catalog.sh <catalog> <manifest> [--expect-no-fixtures]}"
expect_no_fixtures="${3:-}"

# Supported catalog schema versions. Must track @supported_schema_versions in
# lib/digital_oil_sticker/catalog/metadata.ex — a mismatch means the image
# builds and then fails to boot, which is a worse place to find out.
supported_schemas="1"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# grep -o rather than sed capture groups: no backreference to be mangled.
json_string() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$manifest" \
    | head -1 \
    | sed 's/.*"\([^"]*\)"$/\1/' \
    | tr -d '"'
}

json_number() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*[0-9][0-9]*" "$manifest" \
    | head -1 \
    | grep -o '[0-9][0-9]*$'
}

[ -f "$manifest" ] || fail "$manifest is absent — the catalog build did not run"
[ -f "$catalog" ] || fail "$catalog is absent — there is no catalog to serve"

expected_sha="$(grep -o '[0-9a-f]\{64\}' "$manifest" | head -1)"
expected_size="$(json_number size)"
expected_schema="$(json_string schema_version)"

[ -n "$expected_sha" ] || fail "the manifest carries no payload_sha256 — it was not written by the catalog compiler"
[ -n "$expected_size" ] || fail "the manifest carries no size"

actual_size="$(wc -c < "$catalog" | tr -d ' ')"
[ "$actual_size" = "$expected_size" ] \
  || fail "catalog is $actual_size bytes, manifest says $expected_size — truncated or replaced"

actual_sha="$(sha256sum "$catalog" | cut -d' ' -f1)"
[ "$actual_sha" = "$expected_sha" ] \
  || fail "catalog sha256 $actual_sha does not match manifest $expected_sha — this is not the artifact that was built"

case " $supported_schemas " in
  *" $expected_schema "*) : ;;
  *) fail "catalog schema_version '$expected_schema' is outside the window this app supports ($supported_schemas)" ;;
esac

# A synthetic fixture served as if it were real data is a correctness failure,
# not a housekeeping one — but only inside the image. In a developer working
# tree the fixtures are supposed to be there.
if [ "$expect_no_fixtures" = "--expect-no-fixtures" ]; then
  catalog_dir="$(dirname "$catalog")"
  for fixture in catalog-fixture-a.sqlite3 catalog-fixture-b.sqlite3 catalog-fixture-manifest.json; do
    [ ! -f "$catalog_dir/$fixture" ] \
      || fail "test fixture $fixture reached the image beside the production catalog"
  done
fi

echo "catalog verified: sha256 $actual_sha, $actual_size bytes, schema $expected_schema"
