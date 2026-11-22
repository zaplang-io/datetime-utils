#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
zap=${ZAP:-zap}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
trap 'exit 1' HUP INT TERM
export ZAP_CACHE="$scratch/cache"
unset ZAP_ZENV

cd "$root"
"$zap" fmt --check src tests
"$zap" publish --dry-run

# Run the native suites against the package installed in a temporary consumer.
mkdir "$scratch/consumer"
cp -R tests "$scratch/consumer/tests"
cd "$scratch/consumer"
cat > zap.toml <<'MANIFEST'
[package]
name = "datetime_utils_tests"
version = "0.0.0"
MANIFEST
"$zap" add datetime_utils --path "$root"
"$zap" zenv create --no-venv
TZ=America/New_York ZAP_ZENV="$PWD/zenv" "$zap" test tests
