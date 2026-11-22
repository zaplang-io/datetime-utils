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

The package currently applies deltas to core `DateTime`.

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
