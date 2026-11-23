"ISO-8601 parsing into core DateTime values."

import datetime
import time

struct ParserError:
    str message

const int64 _DASH = 45
const int64 _PLUS = 43
const int64 _COLON = 58
const int64 _DOT = 46
const int64 _COMMA = 44
const int64 _SPACE = 32
const int64 _UPPER_T = 84
const int64 _LOWER_T = 116
const int64 _WEEK = 87
const int64 _UPPER_Z = 90
const int64 _LOWER_Z = 122
const int64 _ZERO = 48
const int64 _NINE = 57

def _at(bytes text, int64 index, int64 expected) -> bool:
    return index < len(text) and int64(text[index]) == expected

def _number(bytes text, int64 start, int64 width) -> int64:
    if width > len(text) - start:
        raise ParserError("Incomplete ISO number")
    auto result = 0
    for index in range(start, start + width):
        auto digit = int64(text[index])
        if digit < _ZERO or digit > _NINE:
            raise ParserError("Expected an ASCII digit in ISO input")
        result = result * 10 + digit - _ZERO
    return result

def _leap(int64 year) -> bool:
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

def _check_year(int64 year):
    if year < 1 or year > 9999:
        raise ParserError("ISO year must be in 1..9999")

def _calendar_date(int64 year, int64 month, int64 day) -> Date:
    if month < 1 or month > 12 or day < 1:
        raise ParserError("Invalid ISO calendar date")
    auto last = 31
    if month == 2:
        last = 28
        if _leap(year):
            last = 29
    elif month == 4 or month == 6 or month == 9 or month == 11:
        last = 30
    if day > last:
        raise ParserError("Invalid ISO calendar date")
    return datetime.date(year, month, day)

def _shift_date(Date day, int64 days) -> Date:
    auto midnight = datetime.combine(day, datetime.time(0, 0, 0))
    auto result = datetime.to_date(datetime.add(midnight, time.seconds(days * 86400)))
    _check_year(result.year)
    return result

def _week_date(int64 year, int64 week, int64 weekday) -> Date:
    auto first = datetime.date_weekday(datetime.date(year, 1, 1))
    auto last_week = 52
    if first == 3 or first == 2 and _leap(year):
        last_week = 53
    if week < 1 or week > last_week or weekday < 1 or weekday > 7:
        raise ParserError("Invalid ISO week or weekday")
    auto january_fourth = datetime.date(year, 1, 4)
    auto start = datetime.date_weekday(january_fourth)
    return _shift_date(january_fourth, (week - 1) * 7 + weekday - 1 - start)

def _parse_date(bytes text, bool has_time) -> Date:
    auto year = _number(text, 0, 4)
    _check_year(year)
    if len(text) == 4 and not has_time:
        return datetime.date(year, 1, 1)

    auto start = 4
    auto extended = _at(text, start, _DASH)
    if extended:
        start = start + 1
    auto width = len(text) - start

    if _at(text, start, _WEEK):
        auto week = _number(text, start + 1, 2)
        if width == 3 and not has_time:
            return _week_date(year, week, 1)
        if not extended and width == 4:
            return _week_date(year, week, _number(text, start + 3, 1))
        if extended and width == 5 and _at(text, start + 3, _DASH):
            return _week_date(year, week, _number(text, start + 4, 1))
        raise ParserError("Invalid ISO week-date form")

    if width == 3:
        auto ordinal = _number(text, start, 3)
        auto last = 365
        if _leap(year):
            last = 366
        if ordinal < 1 or ordinal > last:
            raise ParserError("Invalid ISO ordinal day")
        return _shift_date(datetime.date(year, 1, 1), ordinal - 1)
    if extended and width == 2 and not has_time:
        return _calendar_date(year, _number(text, start, 2), 1)
    if not extended and width == 4:
        return _calendar_date(
            year,
            _number(text, start, 2),
            _number(text, start + 2, 2),
        )
    if extended and width == 5 and _at(text, start + 2, _DASH):
        return _calendar_date(
            year,
            _number(text, start, 2),
            _number(text, start + 3, 2),
        )
    raise ParserError("Invalid ISO calendar-date form")

def _offset_minutes(bytes text, int64 start) -> int64:
    auto marker = int64(text[start])
    auto width = len(text) - start
    if (marker == _UPPER_Z or marker == _LOWER_Z) and width == 1:
        return 0
    if marker != _PLUS and marker != _DASH:
        raise ParserError("Invalid ISO timezone suffix")
    auto hours = _number(text, start + 1, 2)
    auto minutes = 0
    if width == 5:
        minutes = _number(text, start + 3, 2)
    elif width == 6 and _at(text, start + 3, _COLON):
        minutes = _number(text, start + 4, 2)
    elif width != 3:
        raise ParserError("Invalid ISO timezone offset form")
    if hours > 23 or minutes > 59:
        raise ParserError("ISO timezone offset is out of range")
    auto offset = hours * 60 + minutes
    if marker == _DASH:
        return -offset
    return offset

def _parse_time(Date day, bytes text) -> DateTime:
    auto hour = _number(text, 0, 2)
    auto zone_start = len(text)
    auto clock_end = len(text)
    for index in range(2, len(text)):
        auto marker = int64(text[index])
        if marker == _DASH or marker == _PLUS or marker == _UPPER_Z or marker == _LOWER_Z:
            zone_start = index
            break
        if clock_end == len(text) and (marker == _DOT or marker == _COMMA):
            clock_end = index

    auto has_fraction = clock_end < zone_start
    if clock_end > zone_start:
        clock_end = zone_start
    auto minute = 0
    auto second = 0
    if clock_end == 4 or clock_end == 6:
        minute = _number(text, 2, 2)
        if clock_end == 6:
            second = _number(text, 4, 2)
    elif (clock_end == 5 or clock_end == 8) and _at(text, 2, _COLON):
        minute = _number(text, 3, 2)
        if clock_end == 8:
            if not _at(text, 5, _COLON):
                raise ParserError("Inconsistent ISO time separators")
            second = _number(text, 6, 2)
    elif clock_end != 2:
        raise ParserError("Invalid ISO time form")

    auto microsecond = 0
    auto nonzero_fraction = False
    if has_fraction:
        auto first = clock_end + 1
        if clock_end != 6 and clock_end != 8 or first == zone_start:
            raise ParserError("An ISO fraction requires seconds and at least one digit")
        auto scale = 100000
        for index in range(first, zone_start):
            auto digit = int64(text[index])
            if digit < _ZERO or digit > _NINE:
                raise ParserError("Expected an ASCII digit in ISO fraction")
            if digit != _ZERO:
                nonzero_fraction = True
            microsecond = microsecond + (digit - _ZERO) * scale
            scale = scale // 10

    if hour > 24 or minute > 59 or second > 59:
        raise ParserError("ISO time is out of range")
    if hour == 24:
        if minute != 0 or second != 0 or nonzero_fraction:
            raise ParserError("Hour 24 requires zero minutes, seconds, and fraction")
        day = _shift_date(day, 1)
        hour = 0

    if zone_start == len(text):
        auto naive = datetime.combine(day, datetime.time(hour, minute, second))
        return datetime.replace(naive, microsecond=microsecond)
    auto zone = datetime.fixed_offset(_offset_minutes(text, zone_start))
    auto aware = datetime.resolve(
        zone,
        day.year,
        day.month,
        day.day,
        hour,
        minute,
        second,
    )
    return datetime.replace(aware, microsecond=microsecond)

def isoparse(str s) -> DateTime:
    """Parse an ISO calendar, ordinal, or week date with optional time and offset.

    Fractions truncate to microseconds. Invalid syntax or out-of-range
    fields raise ParserError.
    """
    if s is None:
        raise ParserError("Expected an ISO string")
    auto text = bytes(s)
    for index in range(4, len(text)):
        auto marker = int64(text[index])
        if marker == _UPPER_T or marker == _LOWER_T or marker == _SPACE:
            auto day = _parse_date(text[:index], True)
            return _parse_time(day, text[index + 1:])
    auto day = _parse_date(text, False)
    return datetime.combine(day, datetime.time(0, 0, 0))
