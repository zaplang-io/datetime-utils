"Parse date and time strings into core DateTime values."

import datetime
import time

@exception
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
        raise ParserError("Incomplete number")
    auto result = 0
    for index in range(start, start + width):
        auto digit = int64(text[index])
        if digit < _ZERO or digit > _NINE:
            raise ParserError("Expected an ASCII digit")
        result = result * 10 + digit - _ZERO
    return result

def _leap(int64 year) -> bool:
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

def _check_year(int64 year):
    if year < 1 or year > 9999:
        raise ParserError("Year must be in 1..9999")

def _month_end(int64 year, int64 month) -> int64:
    if month < 1 or month > 12:
        raise ParserError("Month must be in 1..12")
    if month == 2:
        if _leap(year):
            return 29
        return 28
    if month == 4 or month == 6 or month == 9 or month == 11:
        return 30
    return 31

def _calendar_date(int64 year, int64 month, int64 day) -> Date:
    if day < 1 or day > _month_end(year, month):
        raise ParserError("Invalid calendar date")
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

const int64 _NO_OFFSET = 86400
const int64 _END = 0
const int64 _DIGITS = 1
const int64 _WORD = 2
const int64 _PUNCTUATION = 3
const int64 _OTHER = 4

value struct _Token:
    bytes text
    int64 kind
    bool joined

def _token_kind(int64 c) -> int64:
    if _ZERO <= c and c <= _NINE:
        return _DIGITS
    if 65 <= c and c <= 90 or 97 <= c and c <= 122:
        return _WORD
    if c < 128:
        return _PUNCTUATION
    return _OTHER

def _lex(bytes input) -> list[_Token]:
    list[_Token] tokens = []
    auto index = 0
    auto previous_end = 0
    while index < len(input):
        auto start = index
        auto symbol = int64(input[index])
        index += 1
        if symbol == 0:
            raise ParserError("Unexpected NUL in date string")
        if symbol == _SPACE or 9 <= symbol and symbol <= 13:
            continue
        auto kind = _token_kind(symbol)
        if kind != _PUNCTUATION:
            while index < len(input) and _token_kind(int64(input[index])) == kind:
                index += 1
        tokens.append(_Token(input[start:index], kind, start == previous_end))
        previous_end = index
    return tokens

def _token_at(list[_Token] tokens, int64 index) -> _Token:
    if index < len(tokens):
        return tokens[index]
    return _Token(b"", _END, False)

def _joined(list[_Token] tokens, int64 index, bytes spelling) -> bool:
    auto token = _token_at(tokens, index)
    return token.joined and token.text == spelling

def _date_delimiter(_Token token) -> bool:
    return token.joined and (token.text == b"-" or token.text == b"/" or token.text == b".")

def _long_date_field(list[_Token] tokens, int64 index) -> bool:
    auto token = tokens[index]
    if len(token.text) < 3:
        return False
    if _date_delimiter(_token_at(tokens, index + 1)):
        return True
    return index > 0 and token.joined and _date_delimiter(tokens[index - 1])

def _small_number(_Token token) -> int64:
    if token.kind != _DIGITS or len(token.text) > 4:
        raise ParserError("Expected a date or clock field")
    return _number(token.text, 0, len(token.text))

def _month_name(str word) -> int64:
    match word:
        case "jan" | "january":
            return 1
        case "feb" | "february":
            return 2
        case "mar" | "march":
            return 3
        case "apr" | "april":
            return 4
        case "may":
            return 5
        case "jun" | "june":
            return 6
        case "jul" | "july":
            return 7
        case "aug" | "august":
            return 8
        case "sep" | "sept" | "september":
            return 9
        case "oct" | "october":
            return 10
        case "nov" | "november":
            return 11
        case "dec" | "december":
            return 12
        case _:
            return 0

def _weekday_name(str word) -> int64:
    match word:
        case "mon" | "monday":
            return 0
        case "tue" | "tuesday":
            return 1
        case "wed" | "wednesday":
            return 2
        case "thu" | "thursday":
            return 3
        case "fri" | "friday":
            return 4
        case "sat" | "saturday":
            return 5
        case "sun" | "sunday":
            return 6
        case _:
            return -1

def _separator(_Token token) -> bool:
    if token.kind == _PUNCTUATION:
        return token.text in [b".", b",", b";", b"-", b"/", b"'"]
    if token.kind == _WORD:
        return str(token.text).lower() in ["at", "on", "and", "ad", "of", "st", "nd", "rd", "th", "t"]
    return False

value struct _DateField:
    int64 value
    bool named_month
    bool full_year

value struct _CivilDate:
    int64 year = -1
    int64 month = -1
    int64 day = -1
    bool full_year = False

def _ymd(_DateField year, _DateField month, _DateField day) -> _CivilDate:
    return _CivilDate(year.value, month.value, day.value, year.full_year)

def _resolve_named_month(
    list[_DateField] fields,
    int64 month_index,
    bool yearfirst,
) -> _CivilDate:
    auto month = fields[month_index]
    if len(fields) == 1:
        return _CivilDate(month=month.value)
    auto first = fields[0]
    if month_index == 0:
        first = fields[1]
    if len(fields) == 2:
        if first.full_year or first.value > 31:
            return _CivilDate(
                year=first.value,
                month=month.value,
                full_year=first.full_year,
            )
        return _CivilDate(month=month.value, day=first.value)

    auto second = fields[2]
    if month_index == 2:
        second = fields[1]
    if first.full_year:
        return _ymd(first, month, second)
    if second.full_year:
        return _ymd(second, month, first)
    if month_index == 0 and first.value > 31:
        return _ymd(first, month, second)
    if month_index == 1 and (first.value > 31 or yearfirst and second.value <= 31):
        return _ymd(first, month, second)
    if month_index == 2 and second.value <= 31:
        return _ymd(first, month, second)
    return _ymd(second, month, first)

def _resolve_calendar(
    list[_DateField] fields,
    bool dayfirst,
    bool yearfirst,
) -> _CivilDate:
    auto month_index = -1
    auto year_index = -1
    for index in range(len(fields)):
        auto field = fields[index]
        if field.named_month:
            if month_index != -1:
                raise ParserError("Multiple month names")
            month_index = index
        if field.full_year:
            if year_index != -1:
                raise ParserError("Multiple explicit years")
            year_index = index
    if month_index != -1:
        return _resolve_named_month(fields, month_index, yearfirst)
    if len(fields) == 0:
        return _CivilDate()

    auto first = fields[0]
    if len(fields) == 1:
        if first.full_year or first.value > 31:
            return _CivilDate(year=first.value, full_year=first.full_year)
        return _CivilDate(day=first.value)

    auto second = fields[1]
    if len(fields) == 2:
        if first.full_year or first.value > 31:
            return _CivilDate(
                year=first.value,
                month=second.value,
                full_year=first.full_year,
            )
        if second.full_year or second.value > 31:
            return _CivilDate(
                year=second.value,
                month=first.value,
                full_year=second.full_year,
            )
        if dayfirst and second.value <= 12:
            return _CivilDate(month=second.value, day=first.value)
        return _CivilDate(month=first.value, day=second.value)

    auto third = fields[2]
    if first.value > 31 or year_index == 0 or yearfirst and second.value <= 12 and third.value <= 31:
        if dayfirst and third.value <= 12:
            return _ymd(first, third, second)
        return _ymd(first, second, third)
    if first.value > 12 or dayfirst and second.value <= 12:
        return _ymd(third, second, first)
    return _ymd(third, first, second)

value struct _Clock:
    int64 hour = -1
    int64 minute = -1
    int64 second = -1
    int64 nanosecond = -1

def _meridiem(list[_Token] tokens, int64 start) -> (int64, int64):
    auto token = _token_at(tokens, start)
    if token.kind == _WORD:
        auto word = str(token.text).lower()
        if (word == "a" or word == "p") and _joined(tokens, start + 1, b"."):
            auto letter = _token_at(tokens, start + 2)
            if letter.kind == _WORD and letter.joined and str(letter.text).lower() == "m":
                auto next = start + 3
                if _joined(tokens, next, b"."):
                    next += 1
                if word == "a":
                    return (0, next)
                return (12, next)
        if word == "am" or word == "a":
            return (0, start + 1)
        if word == "pm" or word == "p":
            return (12, start + 1)
    return (-1, start)

def _clock_fraction(_Token token) -> int64:
    auto value = 0
    auto scale = 100000000
    auto width = len(token.text)
    if width > 9:
        width = 9
    for index in range(width):
        value += (int64(token.text[index]) - _ZERO) * scale
        scale //= 10
    return value

def _read_clock(
    list[_Token] tokens,
    int64 start,
    int64 date_fields,
    bool fuzzy,
) -> (_Clock, int64):
    auto token = tokens[start]
    auto width = len(token.text)
    auto next = start + 1
    _Clock clock = _Clock()
    if _joined(tokens, next, b":"):
        clock.hour = _small_number(token)
        auto minute = _token_at(tokens, next + 1)
        if not minute.joined:
            raise ParserError("Expected minutes after colon")
        clock.minute = _small_number(minute)
        next += 2
        if _joined(tokens, next, b":"):
            auto second = _token_at(tokens, next + 1)
            if not second.joined:
                raise ParserError("Expected seconds after colon")
            clock.second = _small_number(second)
            clock.nanosecond = 0
            next += 2
        auto fraction = _token_at(tokens, next + 1)
        auto comma = len(tokens[next - 1].text) >= 2 and _joined(tokens, next, b",")
        if (_joined(tokens, next, b".") or comma) and fraction.joined and fraction.kind == _DIGITS:
            auto nanos = _clock_fraction(fraction)
            if clock.second == -1:
                clock.second = nanos * 60 // 1000000000
            else:
                clock.nanosecond = nanos // 1000 * 1000
            next += 2
            if _joined(tokens, next, b".") and _token_at(tokens, next + 1).kind == _DIGITS:
                raise ParserError("Multiple clock fraction separators")
    elif date_fields == 3 and (width == 4 or width == 6):
        clock.hour = _number(token.text, 0, 2)
        clock.minute = _number(token.text, 2, 2)
        if width == 6:
            clock.second = _number(token.text, 4, 2)
            clock.nanosecond = 0
    elif date_fields == 3 and width <= 2:
        clock.hour = _small_number(token)

    auto meridiem, after = _meridiem(tokens, next)
    if meridiem != -1:
        if clock.hour == -1 and width <= 2:
            auto hour = _small_number(token)
            if hour <= 12 or not fuzzy:
                clock.hour = hour
        if clock.hour != -1:
            if clock.hour <= 12:
                clock.hour = clock.hour % 12 + meridiem
                next = after
            elif not fuzzy and next == start + 1:
                next = after
    return (clock, next)

def _read_offset(list[_Token] tokens, int64 start, bool reverse_sign) -> (int64, int64):
    auto sign = tokens[start].text
    auto number = _token_at(tokens, start + 1)
    if not number.joined or number.kind != _DIGITS:
        raise ParserError("Expected digits in UTC offset")
    auto next = start + 2
    auto width = len(number.text)
    auto hour = 0
    auto minute = 0
    if width == 4:
        hour = _number(number.text, 0, 2)
        minute = _number(number.text, 2, 2)
    elif width <= 2:
        hour = _small_number(number)
        if _joined(tokens, next, b":"):
            auto field = _token_at(tokens, next + 1)
            if not field.joined or len(field.text) > 2:
                raise ParserError("Invalid UTC offset minutes")
            minute = _small_number(field)
            next += 2
    else:
        raise ParserError("Invalid UTC offset")
    if hour > 23 or minute > 59:
        raise ParserError("UTC offset is out of range")
    auto offset = hour * 60 + minute
    if (sign == b"-") != reverse_sign:
        offset = -offset
    return (offset, next)

value struct _ZoneSuffix:
    str name = ""
    int64 offset = _NO_OFFSET

def _zone_alias(_Token token) -> str:
    if token.kind != _WORD or len(token.text) > 5:
        return ""
    for c in token.text:
        if c < 65 or c > 90:
            return ""
    return str(token.text)

def _is_sign(_Token token) -> bool:
    return token.text == b"+" or token.text == b"-"

def _read_zone_suffix(list[_Token] tokens, int64 start) -> (_ZoneSuffix, int64):
    auto token = _token_at(tokens, start)
    auto name = _zone_alias(token)
    if token.text == b"z":
        name = "Z"
    auto word = name.lower()
    if _month_name(word) != 0 or _weekday_name(word) != -1 or word in ["am", "pm", "a", "p"]:
        name = ""

    auto next = start
    auto offset = _NO_OFFSET
    bool reverse = False
    if name != "":
        next += 1
        auto universal = name == "UTC" or name == "GMT" or name == "Z"
        if universal:
            offset = 0
        auto sign = _token_at(tokens, next)
        if sign.joined and _is_sign(sign):
            reverse = True
            if universal:
                name = ""
        elif name == "Z":
            name = "UTC"

    if reverse or name == "":
        while _is_sign(_token_at(tokens, next)):
            auto minutes, end = _read_offset(tokens, next, reverse)
            offset = minutes * 60
            next = end
            reverse = False
        if offset != _NO_OFFSET and _token_at(tokens, next).text == b"(":
            auto bracketed = _zone_alias(_token_at(tokens, next + 1))
            if len(bracketed) >= 3 and _token_at(tokens, next + 2).text == b")":
                name = bracketed
                next += 3

    if offset == 0 and name == "":
        name = "UTC"
    return (_ZoneSuffix(name, offset), next)

def _choose_zone(
    _ZoneSuffix suffix,
    bool ignoretz,
    Optional[dict[str, TimeZone]] tzinfos,
    Optional[fn(Optional[str], Optional[int64]) -> Optional[TimeZone]] tzresolver,
) -> (Optional[TimeZone], bool):
    if ignoretz:
        return (None, False)
    if tzresolver.is_some():
        if tzinfos.is_some():
            raise ParserError("tzinfos and tzresolver are mutually exclusive")
        Optional[str] name = None
        Optional[int64] seconds = None
        if suffix.name != "":
            name = suffix.name
        if suffix.offset != _NO_OFFSET:
            seconds = suffix.offset
        auto resolve = tzresolver.unwrap()
        return (resolve(name, seconds), True)
    if tzinfos.is_some() and suffix.name != "":
        auto zones = tzinfos.unwrap()
        if suffix.name in zones:
            Optional[TimeZone] zone = zones[suffix.name]
            return (zone, False)
    if suffix.offset != _NO_OFFSET:
        Optional[TimeZone] zone = datetime.fixed_offset(suffix.offset // 60)
        return (zone, False)
    return (None, False)

def _resolved_year(_CivilDate date, int64 default_year) -> int64:
    if date.year == -1:
        return default_year
    auto year = date.year
    if not date.full_year and year < 100:
        auto current = datetime.date_today().year
        year += current // 100 * 100
        if year >= current + 50:
            year -= 100
        elif year < current - 50:
            year += 100
    return year

def _build_result(
    _CivilDate date,
    _Clock clock,
    int64 weekday,
    Optional[TimeZone] zone,
    str zone_name,
    bool drop_default_zone,
    DateTime base,
) -> DateTime:
    auto year = _resolved_year(date, base.year)
    _check_year(year)
    auto month = date.month
    if month == -1:
        month = base.month
    auto day = date.day
    if day == -1:
        auto last = _month_end(year, month)
        day = base.day
        if day > last:
            day = last
    auto civil = _calendar_date(year, month, day)
    if weekday != -1 and date.day == -1:
        auto shift = (weekday - datetime.date_weekday(civil) + 7) % 7
        civil = _shift_date(civil, shift)

    auto hour = clock.hour
    auto minute = clock.minute
    auto second = clock.second
    auto nanos = clock.nanosecond
    if hour == -1:
        hour = base.hour
    if minute == -1:
        minute = base.minute
    if second == -1:
        second = base.second
    if nanos == -1:
        nanos = base.nanosecond
    if hour > 23 or minute > 59 or second > 59:
        raise ParserError("Clock time is out of range")
    if zone.is_some():
        auto selected = zone.unwrap()
        auto aware = datetime.resolve(
            selected,
            civil.year,
            civil.month,
            civil.day,
            hour,
            minute,
            second,
            nanosecond=nanos,
        )
        if zone_name != "" and datetime.is_ambiguous(aware):
            auto earlier_name = datetime.zone_abbreviation(aware)
            if earlier_name.is_none() or earlier_name.unwrap() != zone_name:
                auto later = datetime.resolve(
                    selected,
                    civil.year,
                    civil.month,
                    civil.day,
                    hour,
                    minute,
                    second,
                    fold=1,
                    nanosecond=nanos,
                )
                auto later_name = datetime.zone_abbreviation(later)
                if later_name.is_some() and later_name.unwrap() == zone_name:
                    return later
        return aware
    if drop_default_zone:
        auto naive = datetime.combine(civil, datetime.time(hour, minute, second))
        return datetime.replace(naive, nanosecond=nanos)
    return datetime.replace(
        base,
        year=civil.year,
        month=civil.month,
        day=civil.day,
        hour=hour,
        minute=minute,
        second=second,
        nanosecond=nanos,
    )

def parse(
    str s,
    bool dayfirst = False,
    bool yearfirst = False,
    bool fuzzy = False,
    Optional[DateTime] default = None,
    bool ignoretz = False,
    Optional[dict[str, TimeZone]] tzinfos = None,
    Optional[fn(Optional[str], Optional[int64]) -> Optional[TimeZone]] tzresolver = None,
) -> DateTime:
    """Parse an English calendar date or clock time into a core DateTime.

    Dayfirst and yearfirst guide numeric date ordering. Missing fields come
    from default or local midnight today. Fuzzy mode skips unrecognized
    text. Apply UTC markers and numeric offsets unless ignoretz is set.
    Supply tzinfos for case-sensitive timezone aliases or tzresolver to
    resolve a name and offset in seconds. A resolver may return None to
    produce a naive datetime. Invalid input raises ParserError.
    """
    if s is None:
        raise ParserError("Expected a date string")
    auto tokens = _lex(bytes(s))
    list[_DateField] fields = []
    _Clock clock = _Clock()
    auto weekday = -1
    auto suffix = _ZoneSuffix()
    auto zone_start = -1
    auto index = 0
    while index < len(tokens):
        if index == zone_start:
            auto parsed_zone, next = _read_zone_suffix(tokens, index)
            suffix = parsed_zone
            index = next
            if index == len(tokens):
                break
        auto token = tokens[index]
        if token.kind == _DIGITS:
            auto width = len(token.text)
            if len(fields) == 0 and (width == 8 or width == 12 or width == 14):
                fields.append(_DateField(_number(token.text, 0, 4), False, True))
                fields.append(_DateField(_number(token.text, 4, 2), True, False))
                fields.append(_DateField(_number(token.text, 6, 2), False, False))
                if width >= 12:
                    if clock.hour != -1:
                        raise ParserError("Multiple clock times")
                    clock.hour = _number(token.text, 8, 2)
                    clock.minute = _number(token.text, 10, 2)
                    zone_start = index + 1
                    if width == 14:
                        clock.second = _number(token.text, 12, 2)
                index += 1
                continue
            auto parsed, next = _read_clock(tokens, index, len(fields), fuzzy)
            if parsed.hour != -1:
                if clock.hour != -1:
                    raise ParserError("Multiple clock times")
                clock = parsed
                zone_start = next
                index = next
                continue
            if len(fields) == 0 and width == 6:
                for start in range(0, 6, 2):
                    fields.append(
                        _DateField(_number(token.text, start, 2), False, False),
                    )
            else:
                fields.append(
                    _DateField(
                        _small_number(token),
                        False,
                        _long_date_field(tokens, index),
                    ),
                )
        elif token.kind == _WORD:
            auto word = str(token.text).lower()
            auto month = _month_name(word)
            auto weekday_number = _weekday_name(word)
            if month != 0:
                fields.append(_DateField(month, True, False))
            elif weekday_number != -1:
                weekday = weekday_number
            elif not _separator(token) and not fuzzy:
                raise ParserError("Unrecognized word in date string")
        elif not _separator(token) and not fuzzy:
            raise ParserError("Unexpected character in date string")
        if len(fields) > 3:
            raise ParserError("Too many calendar fields")
        index += 1

    if len(fields) == 0 and weekday == -1 and clock.hour == -1:
        raise ParserError("No date or time fields")
    auto date = _resolve_calendar(fields, dayfirst, yearfirst)
    auto base = datetime.combine(datetime.date_today(), datetime.time(0, 0, 0))
    if default.is_some():
        base = default.unwrap()
    auto zone, drop_default_zone = _choose_zone(suffix, ignoretz, tzinfos, tzresolver)
    return _build_result(
        date,
        clock,
        weekday,
        zone,
        suffix.name,
        drop_default_zone,
        base,
    )
