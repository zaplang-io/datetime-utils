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
e = datetime_utils.easter(2027)                        # date
for occ in datetime_utils.RRule(datetime_utils.WEEKLY, dtstart=d, count=5):
    print(occ)
```

## Foundation

Built on core Zap `datetime`/`date`/`time` and the core tz database. A missing core capability is filed upstream in `zaplang-io/zap`, not worked around here (see AGENTS.md).

## Build and test

Standard Zap package build/test. Tests are exhaustive (leap years, DST transitions, month-end clamping, ambiguous/imaginary times); details documented as the first modules land.

## Development

Read **[AGENTS.md](AGENTS.md)** before contributing — it covers the dateutil-parity rule, the one-issue-one-PR flow, how design decisions are recorded in **[DECISIONS.md](DECISIONS.md)**, and the rule for reporting core Zap defects upstream in `zaplang-io/zap`.
