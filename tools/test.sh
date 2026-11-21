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

# Stage each module with its native suite, as done in memcached and msgpack.
mkdir "$scratch/suites"
for suite in tests/*_test.zap; do
    name=${suite#tests/}
    module=${name%_test.zap}
    {
        cat "src/$module.zap"
        printf '\n'
        cat "$suite"
    } > "$scratch/suites/$name"
done
TZ=America/New_York "$zap" test "$scratch/suites"

# Keep separate compiler coverage for the public installed-package imports.
mkdir -p "$scratch/consumer/src"
cd "$scratch/consumer"
cat > zap.toml <<'MANIFEST'
[package]
name = "datetime_utils_tests"
version = "0.0.0"
MANIFEST
cat > src/main.zap <<'ZAP'
import datetime
import datetime_utils.easter as easter
import datetime_utils.tz as tz

def main():
    auto zone = tz.gettz("America/New_York")
    auto override = Optional.Some(datetime.zone("America/New_York"))
    auto gap = datetime.resolve(zone, 2024, 3, 10, 2, 30, 0)
    print(tz.datetime_exists(gap, tz=override))
    print(datetime.isoformat(easter.easter(2024)))
ZAP
"$zap" add datetime_utils --path "$root"
"$zap" zenv create --no-venv
ZAP_ZENV="$PWD/zenv" "$zap" ir src/main.zap > /dev/null
