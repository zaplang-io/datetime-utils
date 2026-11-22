# datetime-utils

dateutil-style datetime utilities for [Zap](https://github.com/zaplang-io/zap) — an official **non-core** package.

- Tracking issue: [zaplang-io/zap#324](https://github.com/zaplang-io/zap/issues/324)
- Roadmap: [bootstrap epic #1](https://github.com/zaplang-io/datetime-utils/issues/1)
- Contributor & agent conventions: [AGENTS.md](AGENTS.md)
- Design decisions: [DECISIONS.md](DECISIONS.md)

> **Status: early / scaffolding.** The modules are being built out issue-by-issue (see the epic). The APIs sketched below describe the *target* surface and are not all implemented yet.

## Goals

A typed Zap package whose public API mirrors [**python-dateutil**](https://dateutil.readthedocs.io/) as closely as Zap's static typing allows — API-parity with the popular Python library is a project rule (see [AGENTS.md](AGENTS.md)). It layers on top of Zap's **core `datetime`** types and the **tz database**; it does not reimplement IANA tz data.

Target modules:

| Module | dateutil reference |
|---|---|
| `relativedelta` | calendar-aware deltas + arithmetic |
| `tz` | `gettz` / `tzutc` / `tzlocal` / `tzoffset` + DST classifiers (over core tz) |
| `parser` | `parse()` heuristic + `isoparse()` ISO-8601 |
| `easter` | Western / Julian / Orthodox |
| `utils` | `today` / `default_tzinfo` / `within_delta` |
| `rrule` | RFC 5545 recurrence generator + `RRuleSet` / `rrulestr` |

## Usage (target surface)

```zap
# Sketch — see the epic for what is implemented today.
d = datetime_utils.parse("2026-11-20T14:30:00Z")     # datetime
nxt = d + datetime_utils.RelativeDelta(months=1, weekday=datetime_utils.MO(+1))
for occ in datetime_utils.RRule(datetime_utils.WEEKLY, dtstart=d, count=5):
    print(occ)
```

## Easter dates

Add this repository as a path dependency with `zap add datetime_utils --path /path/to/datetime-utils`, then run `zap zenv create --no-venv` in the consumer project.

```zap
import datetime
import datetime_utils.easter as easter

def main():
    print(datetime.isoformat(easter.easter(2024)))  # 2024-03-31
    print(datetime.isoformat(easter.easter(2024, method=easter.EASTER_ORTHODOX)))  # 2024-05-05
```

| Method | Returned calendar | Supported years |
| --- | --- | --- |
| `EASTER_JULIAN` (1) | Julian | 327–9999 |
| `EASTER_ORTHODOX` (2) | Gregorian, converted from Julian Easter | 1583–4099 |
| `EASTER_WESTERN` (3, default) | Gregorian | 1583–4099 |

Each call returns a core `Date`. For the Julian method, its fields hold the Julian date. Interpret them in that calendar when doing further calendar calculations. Invalid method and year values raise `ValueError`.

The year and method can come from untrusted input. The function validates both integers before doing a fixed amount of calendar arithmetic. Computation uses no external input, I/O, or shared mutable state.

## Timezone helpers

`datetime_utils.tz` provides `gettz(name=None)`, `tzlocal()`, `UTC`, `tzutc()`, `tzoffset(name, offset)`, `datetime_exists(dt, tz=None)`, `datetime_ambiguous(dt, tz=None)`, and `resolve_imaginary(dt)`. Fixed offsets are integer seconds east of UTC and must have magnitude below 24 hours. The named-zone operations use the IANA data bundled with Zap. Its recurring transitions are expanded through 2100.

```zap
import datetime
import datetime_utils.tz as tz

def main():
    auto ny = tz.gettz("America/New_York")
    auto missing = datetime.resolve(ny, 2024, 3, 10, 2, 30, 0)
    print(tz.datetime_exists(missing))  # False
    print(datetime.isoformat(tz.resolve_imaginary(missing)))  # 2024-03-10T03:30:00-04:00
```

The classifiers use the datetime's own zone when `tz` is omitted. An explicit `Optional[TimeZone]` override reinterprets the existing wall-clock fields in that zone. Classifying a naive datetime without an override raises `ValueError`. An out-of-range fixed offset also raises `ValueError`. Resolving a naive datetime returns it unchanged.

The helpers accept caller-supplied core datetime and zone values. Zone transition rules come from the toolchain. The helpers use no shared mutable state.

`gettz` accepts bundled IANA names and aliases. Omitted, `None`, and empty names use the same system zone as `tzlocal()`. Core consults `TZ` for a bundled name and may use system timezone files on Unix. Unknown names and host lookup failures raise a catchable core exception. See the [Zap host timezone decision](https://github.com/zaplang-io/zap/blob/main/decisions/stdlib/1171-system-local-zone.md).

## Foundation

Built on core Zap `datetime`/`date`/`time` and the core tz database. A missing core capability is filed upstream in `zaplang-io/zap`, not worked around here (see AGENTS.md).

## Relative calendar deltas

`datetime_utils.relativedelta.RelativeDelta(years=0, months=0)` adds or subtracts calendar years and months from a core `DateTime`. The target day is clamped to the last day of the target month. Core `datetime.replace` preserves the wall-clock fields, fractional seconds, and timezone rules.

```zap
import datetime
import datetime_utils.relativedelta as rd

def main():
    auto january = datetime.parse("2024-01-31T12:00:00")
    print(datetime.isoformat(january + rd.RelativeDelta(months=1)))  # 2024-02-29T12:00:00
```

Deltas can also be added together, negated, or multiplied by an integer. The operation checks integer overflow and requires a Gregorian result year from 1 through 9999. The inputs may come from callers, and all operations do constant work without I/O or shared state.

Pass `weekday=rd.MO` for the first Monday on or after the shifted date, or `weekday=rd.FR(-1)` for the first Friday on or before it. The weekday selector runs after month-end clamping. All seven weekday tokens support positive and negative occurrences. A bare token and occurrence zero both select the first occurrence on or after the shifted date. The right delta's explicit selector wins when adding deltas and is preserved by negation or scaling.

## Build and test

Run `sh tools/test.sh` with a codegen-enabled Zap toolchain. The script installs the package in a temporary path-dependent consumer and runs the suites with native `zap test`. The Easter tests compare all 14,707 method/year combinations against month and day vectors generated by python-dateutil 2.9.0.post0. The vectors are in method order 1, 2, 3 and ascending year within each documented range. The timezone tests cover named and host-local lookup, invalid keys and offsets, explicit overrides, historical and future transitions, and gaps and folds.

The RelativeDelta matrix asserts 131,976 results across a full Gregorian cycle. The month-length vectors cover 1696–2103, with one January-to-December row per year and digits 0–3 for lengths 28–31. The matrix reconstructs the same python-dateutil 2.9.0.post0 results as the previous checksum. The weekday vectors use that same dateutil version and contain 49 start-day/target-day rows, each with occurrences −4 through +4.

## Development

Read **[AGENTS.md](AGENTS.md)** before contributing — it covers the dateutil-parity rule, the one-issue-one-PR flow, how design decisions are recorded in **[DECISIONS.md](DECISIONS.md)**, and the rule for reporting core Zap defects upstream in `zaplang-io/zap`.
