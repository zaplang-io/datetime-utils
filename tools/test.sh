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
"$zap" fmt --check src/*.zap tests/*_test.zap
"$zap" publish --dry-run

mkdir -p "$scratch/consumer/src"
cp tests/*_test.zap "$scratch/consumer/src/"
cd "$scratch/consumer"
cat > zap.toml <<'MANIFEST'
[package]
name = "datetime_utils_tests"
version = "0.0.0"
MANIFEST
"$zap" add datetime_utils --path "$root"
"$zap" zenv create --no-venv
export ZAP_ZENV="$PWD/zenv"
if [ "${1:-}" = --check ]; then
    "$zap" ir src/easter_test.zap > /dev/null
    "$zap" ir src/tz_test.zap > /dev/null
else
    "$zap" run src/easter_test.zap > actual
    if command -v sha256sum > /dev/null; then
        sha256sum -c "$root/tests/easter.sha256"
    else
        shasum -a 256 -c "$root/tests/easter.sha256"
    fi
    "$zap" run src/tz_test.zap
fi
