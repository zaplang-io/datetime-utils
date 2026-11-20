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
