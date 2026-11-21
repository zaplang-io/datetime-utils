"Calendar-relative arithmetic over core DateTime."

import datetime

const int64 _MAX = 9223372036854775807
const int64 _MIN = -9223372036854775807 - 1

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
        if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0):
            return 29
        return 28
    if month == 4 or month == 6 or month == 9 or month == 11:
        return 30
    return 31

def _apply(DateTime dt, int64 years, int64 months, bool subtract) -> DateTime:
    if dt.year < 1 or dt.year > 9999 or dt.month < 1 or dt.month > 12:
        raise ValueError("RelativeDelta requires a valid Gregorian date")
    if dt.day < 1 or dt.day > _days_in_month(dt.year, dt.month):
        raise ValueError("RelativeDelta requires a valid Gregorian date")

    auto year_shift = _add(years, months // 12)
    if year_shift < -10000 or year_shift > 10000:
        raise ValueError("RelativeDelta result year must be in 1..9999")
    auto month_shift = 12 * year_shift + months % 12
    if subtract:
        month_shift = -month_shift
    auto target = 12 * (dt.year - 1) + dt.month - 1 + month_shift
    if target < 0 or target >= 9999 * 12:
        raise ValueError("RelativeDelta result year must be in 1..9999")
    auto year = target // 12 + 1
    auto month = target % 12 + 1
    auto day = dt.day
    auto last_day = _days_in_month(year, month)
    if day > last_day:
        day = last_day
    return datetime.replace(dt, year=year, month=month, day=day)

value struct RelativeDelta:
    int64 years = 0
    int64 months = 0

    def __radd__(self, DateTime dt) -> DateTime:
        "Apply the calendar delta and clamp to the target month's last day."
        return _apply(dt, self.years, self.months, False)

    def __rsub__(self, DateTime dt) -> DateTime:
        "Subtract the calendar delta and clamp to the target month's last day."
        return _apply(dt, self.years, self.months, True)

    def __add__(self, RelativeDelta other) -> RelativeDelta:
        "Combine the corresponding relative calendar components."
        return RelativeDelta(
            _add(self.years, other.years),
            _add(self.months, other.months),
        )

    def __neg__(self) -> RelativeDelta:
        "Negate both relative calendar components."
        return RelativeDelta(_negate(self.years), _negate(self.months))

    def __mul__(self, int64 factor) -> RelativeDelta:
        "Scale the relative calendar components by an integer."
        return RelativeDelta(_scale(self.years, factor), _scale(self.months, factor))
