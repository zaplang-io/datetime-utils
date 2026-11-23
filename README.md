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

`datetime_utils.relativedelta.RelativeDelta(years=0, months=0)` adds or subtracts calendar years and months from a core `Date` or `DateTime`. The result is always a `DateTime`. A `Date` starts at naive midnight, even for a calendar-only delta. The target day is clamped to the last day of the target month. Core `datetime.replace` preserves the wall-clock fields, fractional seconds, and timezone rules.

```zap
import datetime
import datetime_utils.relativedelta as rd

def main():
    auto january = datetime.parse("2024-01-31T12:00:00")
    print(datetime.isoformat(january + rd.RelativeDelta(months=1)))  # 2024-02-29T12:00:00
```

Deltas can also be added together, negated, or multiplied by an integer. The operation checks integer overflow and requires a Gregorian result year from 1 through 9999. The inputs may come from callers, and all operations do constant work without I/O or shared state.

Pass `weekday=rd.MO` for the first Monday on or after the shifted date, or `weekday=rd.FR(-1)` for the first Friday on or before it. The weekday selector runs after month-end clamping. All seven weekday tokens support positive and negative occurrences. A bare token and occurrence zero both select the first occurrence on or after the shifted date. The right delta's explicit selector wins when adding deltas and is preserved by negation or scaling.

Relative `weeks`, `days`, `hours`, `minutes`, `seconds`, and `microseconds` can be fractional. They advance the wall clock after month-end clamping and before weekday selection. `leapdays` adds days when the clamped date is after February in a leap year. Call `normalized()` to carry fractions into smaller units and round to whole microseconds. For example, `rd.RelativeDelta(days=1.5, hours=2).normalized()` has one day and fourteen hours.

Absolute `year`, `month`, `day`, `hour`, `minute`, `second`, and `microsecond` replace fields before relative arithmetic. Omit a keyword or pass `None` to use the input field. For example, `rd.RelativeDelta(day=1, hours=25, weekday=rd.MO(1))` starts from the first day of the month, adds 25 wall-clock hours, and then selects the next Monday inclusively. An explicit clock zero replaces the field. A supplied `microsecond` sets the entire fractional second.

`rd.relativedelta(dt1, dt2)` computes the calendar difference from `dt2` to `dt1`. Either operand can be a core `Date` or `DateTime`. A `Date` supplies naive midnight. It takes whole months first and uses days and clock units for the remainder. Two datetimes in the same named zone compare by wall clock. Different zones compare by instant, while applying the delta still uses the base datetime’s wall clock. This can affect round trips across DST. Mixed naive and aware operands raise `TypeError`. A difference finer than one microsecond raises `ValueError`.

## Datetime utilities

`datetime_utils.utils.today(tzinfo=None)` returns midnight on the current date. Without a zone it uses the system’s local date and returns a naive datetime. With a zone it uses that zone’s current date and returns an aware datetime.

`default_tzinfo(dt, tzinfo)` attaches a zone to a naive datetime and preserves its wall-clock fields and fractional second. It returns an aware datetime unchanged, including its overlap fold. Passing `None` leaves the input unchanged.

`within_delta(dt1, dt2, delta)` checks whether the difference is at most the magnitude of a core `Duration`, including the boundary. It compares wall time in a shared named zone and instants across zones. Mixed naive and aware inputs raise `TypeError`.

## Date and time parsing

`datetime_utils.parser.parse(s, dayfirst=False, yearfirst=False, fuzzy=False, default=None, ignoretz=False, tzinfos=None, tzresolver=None)` parses English month and weekday names, numeric dates, colon and compact clock forms, and AM/PM. Use `dayfirst` and `yearfirst` to guide ambiguous numeric dates. Two-digit years resolve within the window from 50 years before the current local year to 49 years after it.

The parser fills missing fields from `default` or local midnight today. It clamps an inherited day to the end of the selected month. With a weekday and no explicit day, it advances to the first matching day on or after the resulting date. UTC markers and signed numeric offsets override the default zone unless `ignoretz=True`. With `fuzzy=True`, the parser skips surrounding prose. Invalid input raises `ParserError`.

Supply `tzinfos={"CST": tz.gettz("America/Chicago"), "BRST": tz.tzoffset("BRST", -7200)}` for case-sensitive aliases. The aliases take precedence over a numeric offset in the input. An unmapped abbreviation falls back to the numeric offset if one was parsed, or to the default's zone otherwise.

For custom resolution, pass `tzresolver` with signature `fn(Optional[str], Optional[int64]) -> Optional[TimeZone]`. It receives the parsed timezone name and UTC offset in seconds, including when neither field is present. Returning `None` produces a naive datetime. Use one of `tzinfos` and `tzresolver`. With `ignoretz=True`, both are ignored.

### ISO parsing

`datetime_utils.parser.isoparse(s)` parses ISO calendar, ordinal, and week dates into a core `DateTime`. It accepts basic and extended times, `T`, `t`, or a single space before the time, dot or comma fractions, and `Z` or signed numeric UTC offsets. Fractions truncate to microseconds. A time without a zone produces a naive datetime. A zero offset produces an aware UTC datetime.

Year-only, year-month, and week-only dates default to their first day. A time requires a complete date. `24:00` advances to the next date when every smaller time component is zero. Invalid fields or syntax raise `ParserError`. Parsing is linear in the input length.

## Build and test

Run `sh tools/test.sh` with a codegen-enabled Zap toolchain. The script installs the package in a temporary path-dependent consumer and runs the suites with native `zap test`. The Easter tests compare all 14,707 method/year combinations against month and day vectors generated by python-dateutil 2.9.0.post0. The vectors are in method order 1, 2, 3 and ascending year within each documented range. The timezone tests cover named and host-local lookup, invalid keys and offsets, explicit overrides, historical and future transitions, and gaps and folds.

The heuristic parser suite compares 367 vectors against python-dateutil 2.9.0.post0 and checks the full two-digit year window against the current local year.

The RelativeDelta matrix asserts 131,976 results across a full Gregorian cycle. The month-length vectors cover 1696–2103, with one January-to-December row per year and digits 0–3 for lengths 28–31. The matrix reconstructs the same python-dateutil 2.9.0.post0 results as the previous checksum. The weekday vectors use that same dateutil version and contain 49 start-day/target-day rows, each with occurrences −4 through +4. The difference vectors compare the fields and round-trip result for 196 ordered datetime pairs.

## Development

Read **[AGENTS.md](AGENTS.md)** before contributing — it covers the dateutil-parity rule, the one-issue-one-PR flow, how design decisions are recorded in **[DECISIONS.md](DECISIONS.md)**, and the rule for reporting core Zap defects upstream in `zaplang-io/zap`.
