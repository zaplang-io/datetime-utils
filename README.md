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

Each call returns a core `Date`. For the Julian method, its fields hold the Julian date. Interpret them in that calendar when doing further calendar calculations. Invalid method and year values raise a string exception with a `ValueError:` prefix.

The year and method can come from untrusted input. The function validates both integers before doing a fixed amount of calendar arithmetic. Computation uses no external input, I/O, or shared mutable state.

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

## Build and test

Run `sh tools/test.sh` with a codegen-enabled Zap toolchain. The suite imports the installed path dependency in a temporary consumer and checks newline-terminated ISO output against python-dateutil 2.9.0.post0. The Easter checksum covers 14,707 dates, ordered by method and year. The relative delta checksum covers 131,976 results, ordered by input year, month, and day and then by the shifts listed in the test.

## Development

Read **[AGENTS.md](AGENTS.md)** before contributing — it covers the dateutil-parity rule, the one-issue-one-PR flow, how design decisions are recorded in **[DECISIONS.md](DECISIONS.md)**, and the rule for reporting core Zap defects upstream in `zaplang-io/zap`.
