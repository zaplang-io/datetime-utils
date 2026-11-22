"Calendar-relative arithmetic over core DateTime."

import datetime
import math
import time

const int64 _MAX = 9223372036854775807
const int64 _MIN = -9223372036854775807 - 1

value struct Weekday:
    int64 weekday
    int64 n

    def __call__(self, int64 n) -> Weekday:
        "Return this weekday with the requested occurrence."
        return Weekday(self.weekday, n)

const Weekday MO = Weekday(0, 0)
const Weekday TU = Weekday(1, 0)
const Weekday WE = Weekday(2, 0)
const Weekday TH = Weekday(3, 0)
const Weekday FR = Weekday(4, 0)
const Weekday SA = Weekday(5, 0)
const Weekday SU = Weekday(6, 0)

def _has_weekday(Weekday selector) -> bool:
    return selector.weekday != -1 or selector.n != 0

def _shift_days(DateTime dt, int64 days) -> DateTime:
    # Duration stores int64 nanoseconds. Use bounded steps to cover the
    # whole Gregorian date range without overflowing a single Duration.
    while days > 100000:
        dt = datetime.add(dt, time.seconds(8640000000))
        days = days - 100000
    while days < -100000:
        dt = datetime.add(dt, time.seconds(-8640000000))
        days = days + 100000
    return datetime.add(dt, time.seconds(days * 86400))

def _apply_weekday(DateTime dt, Weekday selector) -> DateTime:
    if not _has_weekday(selector):
        return dt
    if selector.weekday < 0 or selector.weekday > 6:
        raise ValueError("RelativeDelta weekday must be in 0..6")
    auto occurrence = selector.n
    if occurrence < -521723 or occurrence > 521723:
        raise ValueError(
            "RelativeDelta weekday occurrence is outside the Gregorian date range",
        )
    auto current = datetime.weekday(dt)
    auto days = (selector.weekday - current) % 7
    if occurrence > 0:
        days = days + 7 * (occurrence - 1)
    if occurrence < 0:
        days = 7 * (occurrence + 1) - (current - selector.weekday) % 7
    auto result = _shift_days(dt, days)
    if result.year < 1 or result.year > 9999:
        raise ValueError("RelativeDelta result year must be in 1..9999")
    return result

def _add(int64 left, int64 right) -> int64:
    if right > 0 and left > _MAX - right or right < 0 and left < _MIN - right:
        raise ValueError("RelativeDelta integer overflow")
    return left + right

def _negate(int64 value) -> int64:
    if value == _MIN:
        raise ValueError("RelativeDelta integer overflow")
    return -value

def _scale(int64 value, int64 factor) -> int64:
    if factor == 0 or value == 0:
        return 0
    if factor == _MIN:
        if value == 1:
            return _MIN
        raise ValueError("RelativeDelta integer overflow")
    if factor < 0:
        value = _negate(value)
        factor = -factor
    auto minimum = _MIN // factor
    if _MIN % factor != 0:
        minimum = minimum + 1
    if value < minimum or value > _MAX // factor:
        raise ValueError("RelativeDelta integer overflow")
    return value * factor

def _days_in_month(int64 year, int64 month) -> int64:
    if month == 2:
        if _is_leap_year(year):
            return 29
        return 28
    if month == 4 or month == 6 or month == 9 or month == 11:
        return 30
    return 31

def _is_leap_year(int64 year) -> bool:
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

# Round ties to an even integer, matching Python's microsecond rounding.
def _round_even(f64 value) -> f64:
    auto lower = math.floor(value)
    auto fraction = value - lower
    if fraction > 0.5 or fraction == 0.5 and lower / 2.0 != math.floor(lower / 2.0):
        return lower + 1.0
    return lower

def _round_places(f64 value, f64 scale) -> f64:
    return _round_even(value * scale) / scale

def _carry(f64 value, f64 unit) -> (f64, f64):
    if not math.isfinite(value):
        raise ValueError("RelativeDelta time units must be finite")
    auto whole = math.trunc(value / unit)
    auto remainder = math.remainder(value, unit)
    if value > 0.0 and remainder < 0.0:
        remainder = remainder + unit
    if value < 0.0 and remainder > 0.0:
        remainder = remainder - unit
    return (whole, remainder)

def _apply_time(DateTime dt, RelativeDelta delta, bool subtract) -> DateTime:
    auto clock = delta._carried_time()
    auto days = clock.days
    if subtract:
        days = -days
    if dt.month > 2 and _is_leap_year(dt.year):
        days = days + f64(delta.leapdays)
    # A Gregorian datetime in years 1..9999 cannot move this far and
    # remain in range, even after adding the sub-day remainder.
    if days < -3652060.0 or days > 3652060.0:
        raise ValueError("RelativeDelta result year must be in 1..9999")
    auto whole_days = math.trunc(days)
    auto clock_micros = clock.hours * 3600000000.0 + clock.minutes * 60000000.0 + clock.seconds * 1000000.0 + clock.microseconds
    if subtract:
        clock_micros = -clock_micros
    auto micros = int64(_round_even((days - whole_days) * 86400000000.0 + clock_micros))
    auto result = dt
    if whole_days != 0.0:
        result = _shift_days(result, int64(whole_days))
    if micros != 0:
        result = datetime.add(result, time.micros(micros))
    if result.year < 1 or result.year > 9999:
        raise ValueError("RelativeDelta result year must be in 1..9999")
    return result

def _validate_date(DateTime dt):
    if dt.year < 1 or dt.year > 9999 or dt.month < 1 or dt.month > 12:
        raise ValueError("RelativeDelta requires a valid Gregorian date")
    if dt.day < 1 or dt.day > _days_in_month(dt.year, dt.month):
        raise ValueError("RelativeDelta requires a valid Gregorian date")

def _calendar_component(Optional[int64] component, int64 original) -> int64:
    auto value = component.unwrap_or(0)
    if value == 0:
        return original
    return value

def _clock_component(Optional[int64] component, int64 original, int64 maximum) -> int64:
    if component.is_none():
        return original
    auto value = component.unwrap()
    if value < 0 or value > maximum:
        raise ValueError("RelativeDelta absolute clock field is out of range")
    return value

def _right_absolute(Optional[int64] left, Optional[int64] right) -> Optional[int64]:
    if right.is_some():
        return right
    return left

def _apply(DateTime dt, RelativeDelta delta, bool subtract) -> DateTime:
    _validate_date(dt)

    auto base_year = _calendar_component(delta.year, dt.year)
    auto base_month = _calendar_component(delta.month, dt.month)
    auto day = _calendar_component(delta.day, dt.day)
    if base_year < 1 or base_year > 9999 or base_month < 1 or base_month > 12 or day < 1:
        raise ValueError("RelativeDelta absolute calendar field is out of range")

    auto year_shift = _add(delta.years, delta.months // 12)
    if year_shift < -10000 or year_shift > 10000:
        raise ValueError("RelativeDelta result year must be in 1..9999")
    auto month_shift = 12 * year_shift + delta.months % 12
    if subtract:
        month_shift = -month_shift
    auto target = 12 * (base_year - 1) + base_month - 1 + month_shift
    if target < 0 or target >= 9999 * 12:
        raise ValueError("RelativeDelta result year must be in 1..9999")
    auto year = target // 12 + 1
    auto month = target % 12 + 1
    auto last_day = _days_in_month(year, month)
    if day > last_day:
        day = last_day
    auto hour = _clock_component(delta.hour, dt.hour, 23)
    auto minute = _clock_component(delta.minute, dt.minute, 59)
    auto second = _clock_component(delta.second, dt.second, 59)
    if delta.microsecond.is_some():
        auto microsecond = _clock_component(delta.microsecond, 0, 999999)
        return datetime.replace(
            dt,
            year=year,
            month=month,
            day=day,
            hour=hour,
            minute=minute,
            second=second,
            microsecond=microsecond,
        )
    return datetime.replace(
        dt,
        year=year,
        month=month,
        day=day,
        hour=hour,
        minute=minute,
        second=second,
    )

value struct RelativeDelta:
    int64 years = 0
    int64 months = 0
    Weekday weekday = Weekday(-1, 0)
    f64 weeks = 0.0
    f64 days = 0.0
    f64 hours = 0.0
    f64 minutes = 0.0
    f64 seconds = 0.0
    f64 microseconds = 0.0
    int64 leapdays = 0
    Optional[int64] year = None
    Optional[int64] month = None
    Optional[int64] day = None
    Optional[int64] hour = None
    Optional[int64] minute = None
    Optional[int64] second = None
    Optional[int64] microsecond = None

    def _carried_time(self) -> RelativeDelta:
        auto carry_seconds, microseconds = _carry(self.microseconds, 1000000.0)
        auto carry_minutes, seconds = _carry(self.seconds + carry_seconds, 60.0)
        auto carry_hours, minutes = _carry(self.minutes + carry_minutes, 60.0)
        auto carry_days, hours = _carry(self.hours + carry_hours, 24.0)
        auto days = self.days + 7.0 * self.weeks + carry_days
        if not math.isfinite(days):
            raise ValueError("RelativeDelta time units must be finite")
        auto clock = self
        clock.weeks = 0.0
        clock.days = days
        clock.hours = hours
        clock.minutes = minutes
        clock.seconds = seconds
        clock.microseconds = microseconds
        return clock

    def normalized(self) -> RelativeDelta:
        "Return a delta with whole-valued units and fractions carried to microseconds."
        auto clock = self._carried_time()
        auto days = math.trunc(clock.days)
        auto hours_fraction = _round_places(
            clock.hours + 24.0 * (clock.days - days),
            100000000000.0,
        )
        auto hours = math.trunc(hours_fraction)
        auto minutes_fraction = _round_places(
            clock.minutes + 60.0 * (hours_fraction - hours),
            10000000000.0,
        )
        auto minutes = math.trunc(minutes_fraction)
        auto seconds_fraction = _round_places(
            clock.seconds + 60.0 * (minutes_fraction - minutes),
            100000000.0,
        )
        auto seconds = math.trunc(seconds_fraction)
        auto microseconds = _round_even(
            clock.microseconds + 1000000.0 * (seconds_fraction - seconds),
        )
        auto years = clock.months // 12
        auto months = clock.months % 12
        if clock.months < 0 and months != 0:
            years = years + 1
            months = months - 12
        clock.years = _add(clock.years, years)
        clock.months = months
        clock.days = days
        clock.hours = hours
        clock.minutes = minutes
        clock.seconds = seconds
        clock.microseconds = microseconds
        return clock._carried_time()

    def __radd__(self, DateTime dt) -> DateTime:
        "Apply the calendar shift, relative time, then weekday selection."
        auto calendar = _apply(dt, self, False)
        return _apply_weekday(_apply_time(calendar, self, False), self.weekday)

    def __rsub__(self, DateTime dt) -> DateTime:
        "Subtract the calendar and relative time shifts, then select the weekday."
        auto calendar = _apply(dt, self, True)
        return _apply_weekday(_apply_time(calendar, self, True), self.weekday)

    def __add__(self, RelativeDelta other) -> RelativeDelta:
        "Combine calendar components, taking the rightmost explicit selector."
        auto selector = self.weekday
        if _has_weekday(other.weekday):
            selector = other.weekday
        auto leapdays = other.leapdays
        if leapdays == 0:
            leapdays = self.leapdays
        return RelativeDelta(
            _add(self.years, other.years),
            _add(self.months, other.months),
            selector,
            weeks=self.weeks + other.weeks,
            days=self.days + other.days,
            hours=self.hours + other.hours,
            minutes=self.minutes + other.minutes,
            seconds=self.seconds + other.seconds,
            microseconds=self.microseconds + other.microseconds,
            leapdays=leapdays,
            year=_right_absolute(self.year, other.year),
            month=_right_absolute(self.month, other.month),
            day=_right_absolute(self.day, other.day),
            hour=_right_absolute(self.hour, other.hour),
            minute=_right_absolute(self.minute, other.minute),
            second=_right_absolute(self.second, other.second),
            microsecond=_right_absolute(self.microsecond, other.microsecond),
        )

    def __neg__(self) -> RelativeDelta:
        "Negate the relative calendar components, preserving weekday selection."
        auto result = self
        result.years = _negate(self.years)
        result.months = _negate(self.months)
        result.weeks = -self.weeks
        result.days = -self.days
        result.hours = -self.hours
        result.minutes = -self.minutes
        result.seconds = -self.seconds
        result.microseconds = -self.microseconds
        return result

    def __mul__(self, int64 factor) -> RelativeDelta:
        "Scale the relative calendar components, preserving weekday selection."
        auto clock = self._carried_time()
        auto scale = f64(factor)
        clock.years = _scale(self.years, factor)
        clock.months = _scale(self.months, factor)
        clock.days = math.trunc(clock.days * scale)
        clock.hours = math.trunc(clock.hours * scale)
        clock.minutes = math.trunc(clock.minutes * scale)
        clock.seconds = math.trunc(clock.seconds * scale)
        clock.microseconds = math.trunc(clock.microseconds * scale)
        return clock

def _validate_difference_operand(DateTime dt):
    _validate_date(dt)
    if dt.hour < 0 or dt.hour > 23 or dt.minute < 0 or dt.minute > 59 or dt.second < 0 or dt.second > 59:
        raise ValueError("RelativeDelta requires a valid clock time")
    if dt.nanosecond < 0 or dt.nanosecond >= 1000000000:
        raise ValueError("RelativeDelta requires a valid fractional second")
    if dt.is_aware and (dt.offset <= -86400 or dt.offset >= 86400):
        raise ValueError(
            "RelativeDelta requires a UTC offset below 24 hours in magnitude",
        )

def _comparison_seconds(DateTime dt, bool same_named_zone) -> int64:
    auto seconds = datetime.to_timestamp(dt)
    if same_named_zone:
        return seconds + dt.offset
    return seconds

def _before(DateTime left, DateTime right, bool same_named_zone) -> bool:
    auto left_seconds = _comparison_seconds(left, same_named_zone)
    auto right_seconds = _comparison_seconds(right, same_named_zone)
    return left_seconds < right_seconds or left_seconds == right_seconds and left.nanosecond < right.nanosecond

def relativedelta(DateTime dt1, DateTime dt2) -> RelativeDelta:
    """Return the calendar difference from dt2 to dt1.

    Select whole months without overshooting, then decompose the remaining
    time. Two values in the same named zone compare by wall clock. Naive
    and aware values cannot be mixed. The remainder must be representable
    to the microsecond.
    """
    _validate_difference_operand(dt1)
    _validate_difference_operand(dt2)
    if dt1.is_aware != dt2.is_aware:
        raise TypeError("RelativeDelta cannot mix naive and aware datetimes")
    auto nanos = dt1.nanosecond - dt2.nanosecond
    if nanos % 1000 != 0:
        raise ValueError(
            "RelativeDelta difference must be a whole number of microseconds",
        )

    auto same_named_zone = dt1.is_aware and dt1.zone_id >= 0 and dt1.zone_id == dt2.zone_id
    auto months = (dt1.year - dt2.year) * 12 + dt1.month - dt2.month
    auto anchor = _apply(dt2, RelativeDelta(months=months), False)
    auto backwards = _before(dt1, dt2, same_named_zone)
    if backwards:
        while _before(anchor, dt1, same_named_zone):
            months = months + 1
            anchor = _apply(dt2, RelativeDelta(months=months), False)
    else:
        while _before(dt1, anchor, same_named_zone):
            months = months - 1
            anchor = _apply(dt2, RelativeDelta(months=months), False)

    # Month alignment bounds the remainder to roughly a month. Split
    # negative remainders with a nonnegative fractional part, like timedelta.
    auto seconds = _comparison_seconds(dt1, same_named_zone) - _comparison_seconds(anchor, same_named_zone)
    auto micros = seconds * 1000000 + nanos // 1000
    return RelativeDelta(months=months, seconds=f64(micros // 1000000), microseconds=f64(micros % 1000000)).normalized()
