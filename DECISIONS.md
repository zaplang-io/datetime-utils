# datetime-utils package decisions

Design decisions for the Zap `datetime-utils` package, keyed to issues. Each
records a choice that could not be read straight off
[python-dateutil](https://dateutil.readthedocs.io/) or the core Zap datetime
surface, with the reference it follows or departs from.

## Parity target: python-dateutil

The package tracks [**python-dateutil**](https://dateutil.readthedocs.io/) as its
primary API reference (`parser`, `relativedelta`, `rrule`, `tz`, `easter`,
`utils`). dateutil is the de-facto standard datetime-utilities library for
Python, so matching it gives Zap users the least-surprise surface. Deviations
are recorded below, keyed to the issue that introduces them.

## Foundation: wrap core, don't reimplement

The package is built on Zap's **core `datetime`** types and the **core tz
database**. It adds the dateutil layer on top and must **not** reimplement IANA
tz data or core datetime arithmetic — where core already provides a capability
(named-zone lookup, fold/DST, date math), the package wraps or aliases it to the
dateutil name. Each such alias is recorded here as it is made. A missing core
capability is filed in `zaplang-io/zap` and the dependent work is kept blocked,
never worked around.

## Easter year ranges and result type (issue #5)

`easter(year, method=EASTER_WESTERN)` follows the method names and calendar
conventions in the [python-dateutil Easter reference](https://dateutil.readthedocs.io/en/stable/easter.html).
The Zap API returns core `Date` in all three cases. For the Julian method,
the fields carry the original Julian calendar date, as in python-dateutil.

The package enforces the calculation ranges documented by python-dateutil,
with a 9999 upper limit for the Julian method matching Python's date type.
Out-of-range calculations may return a value in python-dateutil, but fall
outside its documented validity. Zap signals invalid arguments with a typed `ValueError`.

## Timezone helpers over core DateTime (issue #3)

The [python-dateutil timezone reference](https://dateutil.readthedocs.io/en/stable/tz.html)
defines the meaning of wall-clock existence, ambiguity, and imaginary-time
resolution. `datetime_exists` negates core `datetime.is_imaginary`,
`datetime_ambiguous` calls `datetime.is_ambiguous`, and `resolve_imaginary`
calls the identically named core helper. A supplied zone uses
`datetime.resolve` on the civil fields before classification.

The classifier override has type `Optional[TimeZone]`. As in dateutil, an
omitted override uses the datetime's zone and raises for a naive datetime.
The public core `TimeZone` fields carry a fixed zone's name and exact offset
in seconds. `tzoffset` enforces the valid datetime offset range at construction
and takes whole seconds. `UTC` and `tzutc()` return core values with zero offset.

`tzlocal` delegates to `datetime.local_zone`. `gettz` delegates explicit
IANA names and aliases to `datetime.zone`. Omitted, `None`, and empty names
select the host-local zone. Unknown names raise the catchable core lookup
exception, as allowed by issue #3. The return type is core `TimeZone`.

## Relative month and year arithmetic (issue #2)

Adding or subtracting years and months follows the target-month and day
clamping order in the [python-dateutil reference](https://dateutil.readthedocs.io/en/stable/relativedelta.html).
The operator uses core `datetime.replace` to apply the calendar fields and
preserve the input's fractional second and zone rules. It accepts signed
`int64` components and checks overflow and the Gregorian date range before
calling core.

The package applies deltas to core `Date` and `DateTime`. See the Date operand decision below for the result type.

## Relative weekday selectors (issues #2 and #14)

The [python-dateutil weekday rules](https://dateutil.readthedocs.io/en/stable/relativedelta.html)
apply the weekday after month and year arithmetic. `MO` through `SU` are
value tokens that can be called with an occurrence. A bare token stores zero,
which selects the first occurrence on or after the shifted date. A negative
occurrence searches backward, including the current date. Addition keeps the
right delta's selector if present. Negation and scaling preserve it.

Weekday movement uses wall-clock `datetime.add` with bounded day steps to
fit core's nanosecond-backed `Duration`. This preserves the Gregorian range,
fractional second and zone behavior of the preceding calendar operation.

## Relative time units and normalization (issues #2 and #16)

The [python-dateutil normalization rules](https://dateutil.readthedocs.io/en/stable/relativedelta.html)
carry fractions from days down to rounded microseconds. The time fields
use `f64` so their keyword arguments accept fractions and the same field type
can also hold the whole-valued result from `normalized()`. Raw constructor
fields keep the supplied units. Normalization folds weeks into days and carries
whole units. Year, month, and leap-day counts use `int64`.

The relative time shift uses the same core wall-clock arithmetic as weekday
movement. Microseconds round to nearest even and addition preserves any
nanosecond fraction already present on the input. Leap days use the clamped
calendar date. A nonzero right-hand leap-day count wins when adding deltas,
and negation and integer scaling leave the count intact.

## Two-datetime constructor (issues #2 and #18)

`relativedelta(dt1, dt2)` follows the [python-dateutil difference constructor](https://dateutil.readthedocs.io/en/stable/relativedelta.html).
It aligns the base datetime by whole calendar months, backs off when that
would overshoot, and normalizes the remaining days and time. Separate entry
points serve the two forms. `RelativeDelta(...)` takes field keywords and
`relativedelta(dt1, dt2)` takes core `Date` or `DateTime` values.

Equal named-zone identities select wall-clock comparison and subtraction.
Different zones use instants for the constructor and the base zone's wall
clock when applying the result, matching dateutil. A repeated wall time in a
single zone compares equal for this purpose even when the folds differ.
Mixed awareness raises `TypeError`. Zap values with equal nanosecond
remainders can round-trip at microsecond granularity. A difference with
residual nanoseconds raises `ValueError` because a RelativeDelta applies
whole microseconds.

## Absolute fields (issues #2 and #20)

The [python-dateutil absolute field rules](https://dateutil.readthedocs.io/en/stable/relativedelta.html)
place replacement before relative arithmetic. The absolute fields use
`Optional[int64]` and accept direct integer keywords or `None`. Calendar
zero leaves the input field in place, matching dateutil. Day values above
the end of the target month clamp to its last day. Calendar year and month
must be in their Gregorian ranges. Core `datetime.replace` preserves the
zone and fractional seconds unless a `microsecond` replacement is supplied.

When deltas are added, a present right-hand absolute field wins, including
zero. Negation, scaling, and normalization preserve the absolute fields.

## Date operands and the result type (issues #2 and #22)

`Date ± RelativeDelta` always returns core `DateTime`, per the maintainer's
decision. The Date is promoted to naive midnight before applying the delta.
[python-dateutil](https://dateutil.readthedocs.io/en/stable/relativedelta.html)
returns a date for calendar-only operations and can return a datetime when
clock fields are present. The Zap operator has a single result type.

The difference constructor accepts Date or DateTime in either position and
uses the same midnight promotion. The mixed-awareness rule still applies,
so a Date paired with an aware DateTime raises `TypeError`.

## Datetime convenience functions (issue #6)

The [python-dateutil utilities](https://dateutil.readthedocs.io/en/stable/utils.html)
use the local date for `today()`, attach timezones without moving naive wall
times, and compare signed differences against an inclusive absolute tolerance.
Zap uses `Optional[TimeZone]` for zone arguments that allow `None` and core
`Duration` for the tolerance. The core civil resolver attaches the requested
zone, and `datetime.replace` restores input nanoseconds. Shared named zones
use wall-time comparison, and distinct zones use elapsed-time comparison.
The comparison keeps seconds and nanoseconds separate so wide differences
remain comparable within the range of the supplied tolerance.

DST existence and ambiguity checks live in `datetime_utils.tz`.

## Strict ISO parser (issues #4 and #25)

The [python-dateutil ISO parser](https://dateutil.readthedocs.io/en/stable/parser.html#dateutil.parser.isoparse)
defines the supported formats and microsecond precision. Zap accepts a string
and reports malformed input with a standalone typed `ParserError`. The date/time separator
is `T`, `t`, or a single space. Week 53 must exist in the ISO week year.
At hour 24 the entire fraction must be zero, including digits past the first
six. The parser validates civil fields before using core date arithmetic and
the core civil resolver.

## Heuristic parser fields and defaults (issues #4 and #27)

The [python-dateutil parser](https://dateutil.readthedocs.io/en/stable/parser.html#dateutil.parser.parse)
defines numeric ambiguity, English names, fuzzy parsing, default-field
inheritance, and the two-digit year window. Zap uses a core `DateTime` for the
result and an optional core `DateTime` default. Explicit fractions truncate to
microseconds. An inherited nanosecond value retains its full precision.

This slice recognizes `Z`, `z`, `UTC`, `GMT`, and signed numeric offsets.
The tokenizer recognizes ASCII date and clock fields.
Fuzzy parsing can skip surrounding Unicode prose.

## Timezone alias inputs (issue #4)

[python-dateutil](https://dateutil.readthedocs.io/en/stable/parser.html#dateutil.parser.parse)
accepts a mapping or callback under the same keyword, with integer seconds
and timezone objects as values. Zap exposes separate `tzinfos` and
`tzresolver` keywords and uses `TimeZone` values for both. Use
`datetime_utils.tz.tzoffset(name, seconds)` for a fixed offset, including
offsets with sub-minute precision. The resolver receives optional name and
seconds fields and can return `None` to produce a naive datetime. Supplying
both options raises `ParserError` unless `ignoretz=True`.

An unrecognized abbreviation without a numeric offset leaves the default's
zone in place. Zap resolves an explicit alias using the core timezone
database. At an ambiguous wall time, the parser selects the occurrence whose
IANA abbreviation matches the input. If neither occurrence matches, it uses
the earlier occurrence. Core resolves the selected fold with full
subsecond precision.

## Base recurrence frequencies and bounds (issues #7 and #30)

The [python-dateutil recurrence API](https://dateutil.readthedocs.io/en/stable/rrule.html#dateutil.rrule.rrule)
defines the seven frequency constants, the positive interval, reusable
iteration, whole-second start precision, and inclusive counting and cutoff.
`RRule` captures local now when the start keyword is omitted. It validates
options at the start of iteration through Zap's iterable protocol.

RFC 5545 §3.3.10 requires nonexistent civil dates and times to be skipped
and excludes them from the count. Dateutil 2.9.0.post0 can emit an imaginary
local timestamp for an hourly rule despite the documented RFC rule. Zap
skips these occurrences and uses the earlier occurrence of a repeated
wall time. It enforces separate `count` and `until` bounds and a UTC
cutoff for an aware start. A count of zero yields an empty recurrence.

## Recurrence queries (issues #7 and #32)

The [python-dateutil query API](https://dateutil.readthedocs.io/en/stable/rrule.html#dateutil.rrule.rrule)
defines inclusive and exclusive boundaries and query order. Zap returns
`Optional[DateTime]` from `before` and `after` and a `list[DateTime]` from
`between`. The latter keeps dateutil's legacy `count` keyword, which does
not limit results. `count()` traverses the same iterator as the other
queries and counts valid, emitted occurrences.

Query comparisons use civil time when both values refer to the same named
zone and use instant order across zones. This matches dateutil's handling of
queries inside a repeated hour when the bounds share the rule's zone.
The comparisons retain nanosecond precision and reject mixed awareness.

## Recurrence month selectors (issues #7 and #34)

Both `bymonth` and `bymonthday` accept optional integer lists. A one-item list
represents a single selector. Omission uses the frequency's start-date
defaults. An explicit empty list places no restriction on the selected
field, as in python-dateutil. Signed month days count from the end of each
month, and equivalent selectors emit the date once. [Python-dateutil recurrence API](https://dateutil.readthedocs.io/en/stable/rrule.html#dateutil.rrule.rrule)

RFC 5545 §3.3.10 defines valid selector ranges and excludes `bymonthday`
from weekly rules. The iterator validates options before generating
occurrences. It retains the interval phase when skipping dates and applies
the existing count and cutoff to emitted occurrences.

## Recurrence weekdays and week starts (issues #7 and #36)

`byweekday` accepts lists of the existing `relativedelta.Weekday` values.
`wkst` accepts a plain weekday token and defaults to Monday. An explicit
empty weekday list leaves weekdays unrestricted, including when it
replaces the default weekday of a weekly rule. Yearly ordinals count
within the year, or within each selected month if `bymonth` is set and
nonempty. [Python-dateutil recurrence API](https://dateutil.readthedocs.io/en/stable/rrule.html#dateutil.rrule.rrule)

RFC 5545 §3.3.10 restricts ordinal weekdays to monthly and yearly rules.
Plain and ordinal weekdays are alternatives within one BYDAY selector.
Month and month-day rules still apply in combination with the weekday
selection. This preserves the RFC interpretation when a list mixes plain
and ordinal tokens, where python-dateutil 2.9.0.post0 intersects them.

<!--
Add one section per decision as issues are implemented, e.g.:

## relativedelta constructor form (issue #2)
...how the dateutil kwargs map to Zap's constructor / return type...

## parser keyword ergonomics (issue #4)
...dayfirst/yearfirst/fuzzy/default/tzinfos shape in Zap...

## tz aliases over core (issue #3)
...which core tz capability each dateutil name wraps...

## rrule weekday tokens (issues #2/#7)
...shared MO/TU/... tokens between relativedelta and rrule...
-->
