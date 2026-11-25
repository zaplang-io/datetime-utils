# Changelog

## Unreleased

- Add Western, Orthodox, and Julian Easter calculations and method constants.
- Add named, local, UTC, and fixed-offset zones, DST classifiers, and imaginary-time resolution.
- Add calendar month and year arithmetic for core DateTime values.
- Add callable weekday selectors for calendar deltas.
- Add fractional relative time units, leap days, and delta normalization.
- Add a two-datetime constructor for calendar differences.
- Add absolute calendar and clock keywords for RelativeDelta.
- Support core Date operands in RelativeDelta arithmetic and difference construction.
- Add midnight, default timezone, and datetime tolerance utilities.
- Add strict ISO-8601 parsing for calendar, ordinal, and week dates.
- Add heuristic English calendar and clock parsing with defaults, fuzzy text, and numeric UTC offsets.
- Add timezone alias mapping and custom timezone resolution to the heuristic parser.
- Add lazy iteration across the seven base recurrence frequencies with interval, count, and until bounds.
- Add before, after, between, and count queries to recurrence rules.
- Add list-based month and signed month-day filters to recurrence rules.
- Add plain and ordinal weekday selection and configurable weekly starts.
- Add hour, minute, and second recurrence selectors with frequency-based expansion.
- Add signed year-day selectors and Western Easter day offsets to recurrence rules.
