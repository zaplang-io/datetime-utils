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
"$zap" fmt --check src/easter.zap tests/easter_test.zap
"$zap" publish --dry-run

mkdir -p "$scratch/consumer/src"
cp tests/easter_test.zap "$scratch/consumer/src/main.zap"
cd "$scratch/consumer"
cat > zap.toml <<'MANIFEST'
[package]
name = "easter_test"
version = "0.0.0"
MANIFEST
"$zap" add datetime_utils --path "$root"
"$zap" zenv create --no-venv
export ZAP_ZENV="$PWD/zenv"
if [ "${1:-}" = --check ]; then
    "$zap" ir src/main.zap > /dev/null
else
    "$zap" run src/main.zap > actual
    if command -v sha256sum > /dev/null; then
        sha256sum -c "$root/tests/easter.sha256"
    else
        shasum -a 256 -c "$root/tests/easter.sha256"
    fi
fi
