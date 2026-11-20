import datetime
import time

const int64 EASTER_JULIAN = 1
const int64 EASTER_ORTHODOX = 2
const int64 EASTER_WESTERN = 3

# Compute a date in the pre-reform Julian calendar. The returned fields
# represent the Julian year, month, and day.
def _julian_easter(int64 year) -> Date:
    auto golden_index = year % 19
    auto moon = (19 * golden_index + 15) % 30
    auto sunday = (2 * (year % 4) + 4 * (year % 7) - moon + 34) % 7
    auto march_index = moon + sunday + 114
    return datetime.date(year, march_index // 31, march_index % 31 + 1)

# Meeus/Jones/Butcher Gregorian computus.
def _western_easter(int64 year) -> Date:
    auto golden_index = year % 19
    auto century = year // 100
    auto year_in_century = year % 100
    auto solar_correction = century // 4
    auto lunar_correction = (century - (century + 8) // 25 + 1) // 3
    auto moon = (19 * golden_index + century - solar_correction - lunar_correction + 15) % 30
    auto weekday_base = 32 + 2 * (century % 4) + 2 * (year_in_century // 4)
    auto sunday = (weekday_base - moon - year_in_century % 4) % 7
    auto late_moon_correction = (golden_index + 11 * moon + 22 * sunday) // 451
    auto march_index = moon + sunday - 7 * late_moon_correction + 114
    return datetime.date(year, march_index // 31, march_index % 31 + 1)

def easter(int64 year, int64 method = EASTER_WESTERN) -> Date:
    """Return Easter Sunday using the selected dateutil method.

    The Julian method returns Julian calendar fields for years 327 through
    9999. The Orthodox and Western methods return Gregorian calendar fields
    for years 1583 through 4099. An invalid method or year raises a string
    exception with a `ValueError:` prefix.
    """
    if method == EASTER_JULIAN:
        if year < 327 or year > 9999:
            raise "ValueError: Julian Easter requires a year from 327 through 9999"
        return _julian_easter(year)
    if method != EASTER_ORTHODOX and method != EASTER_WESTERN:
        raise "ValueError: invalid Easter method"
    if year < 1583 or year > 4099:
        raise "ValueError: Gregorian Easter requires a year from 1583 through 4099"
    if method == EASTER_WESTERN:
        return _western_easter(year)
    # Easter is after February, so the calendar difference includes every
    # century leap day omitted by the Gregorian calendar through this year.
    auto days = year // 100 - year // 400 - 2
    auto midnight = datetime.combine(_julian_easter(year), datetime.time(0, 0, 0))
    return datetime.to_date(datetime.add(midnight, time.seconds(86400 * days)))
