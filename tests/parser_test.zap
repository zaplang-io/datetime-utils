import datetime
import datetime_utils.parser as parser

def _reject_iso(str value):
    bool caught = False
    try:
        parser.isoparse(value)
    except parser.ParserError:
        caught = True
    assert caught

@test
def parser_iso_dateutil_vectors():
    auto rows = fs.read_file("tests/data/isoparse-vectors.txt").strip().split("\n")
    assert len(rows) == 132
    for row in rows:
        auto fields = row.split("|")
        assert len(fields) == 2
        auto parsed = parser.isoparse(s=fields[0])
        assert datetime.isoformat(parsed) == fields[1], row

@test
def parser_iso_week_year_cycle():
    auto rows = fs.read_file("tests/data/isoparse-week-cycle.txt").strip().split("\n")
    assert len(rows) == 400
    for index in range(len(rows)):
        auto year = str(2000 + index)
        auto fields = rows[index].split("|")
        assert len(fields) == 3
        auto first = parser.isoparse(year + "-W01-1")
        auto last = parser.isoparse(year + "-W" + fields[0] + "-7")
        assert datetime.isoformat(first) == fields[1] + "T00:00:00", year
        assert datetime.isoformat(last) == fields[2] + "T00:00:00", year
        if fields[0] == "52":
            _reject_iso(year + "-W53-1")

@test
def parser_iso_invalid_dates():
    for value in ["", "1", "12", "123", "0000", "10000-01-01", "-001-01-01", "2024-", "2024-1", "202402", "2024-13", "2024-00", "2024-02-00", "2024-02-30", "1900-02-29", "2023-02-29", "2024-04-31", "2024-0101", "202401-01", "2024-W00", "2024-W54", "2021-W53", "2020-W53-0", "2020-W53-8", "2020-W537", "2020W53-7", "2020-w53-7", "9999-W52-6", "2023-366", "2024-000", "2024-367", "2024-00a", "2024T12:00", "2024-02T12:00", "2020-W01T12:00", "2024-02-29Z", " 2024-02-29", "2024-02-29 ", "2024-02-29\x00", "２０２４-02-29"]:
        _reject_iso(value)
    _reject_iso(None)

@test
def parser_iso_invalid_times_and_zones():
    for suffix in ["", "1", "25", "12:", "12:3", "12:60", "12:34:", "12:34:5", "12:34:60", "1234:56", "12:3456", "12.5", "12:30,5", "12:30:00.", "12:30:00,", "12:30:00.1.2", "12:30:00.1x", "12:30:00.١", "12:30:00.000000x", "24:01", "24:00:01", "24:00:00.000001", "24:00:00.0000001", "12Zx", "12ZZ", "12+24", "12-2400", "12+00:60", "12+12:34:56", "12+1", "12+123", "12+12:3", "12+12-34", "12+05:", "12+00-00", "12UTC", "12:00\x00", "12:00\n", "12:00+00:00 "]:
        _reject_iso("2024-02-29T" + suffix)
    _reject_iso("9999-12-31T24:00:00Z")
    _reject_iso("2024-02-29/12:00")
    _reject_iso("2024-02-29  12:00")

@test
def parser_iso_awareness_and_precision():
    auto naive = parser.isoparse("1969-12-31T23:59:59.000001999")
    assert not naive.is_aware and naive.nanosecond == 1000
    auto offset = parser.isoparse("1970-01-01T01:00:00.123456789+01")
    assert offset.is_aware and offset.offset == 3600 and offset.nanosecond == 123456000
    assert datetime.to_timestamp(offset) == 0
    for value in ["2024-01-01T10Z", "2024-01-01T10z", "2024-01-01T10+00", "2024-01-01T10-00:00"]:
        auto utc = parser.isoparse(value)
        assert utc.is_aware and utc.offset == 0

@test
def parser_heuristic_dateutil_vectors():
    auto base = parser.isoparse("2004-01-31T01:02:03.456789")
    auto rows = fs.read_file("tests/data/parse-vectors.txt").strip().split("\n")
    assert len(rows) == 363
    for row in rows:
        auto fields = row.split("|")
        assert len(fields) == 3
        auto flags = fields[0]
        auto parsed = parser.parse(
            s=fields[1],
            dayfirst=flags[0] == chr(49),
            yearfirst=flags[1] == chr(49),
            fuzzy=flags[2] == chr(49),
            default=base,
            ignoretz=flags[3] == chr(49),
        )
        assert datetime.isoformat(parsed) == fields[2], row + " got " + datetime.isoformat(parsed)

@test
def parser_heuristic_ambiguity():
    auto mdy = parser.parse("01/02/03")
    auto dmy = parser.parse("01/02/03", dayfirst=True)
    auto ymd = parser.parse("01/02/03", yearfirst=True)
    auto ydm = parser.parse("01/02/03", yearfirst=True, dayfirst=True)
    assert mdy.year % 100 == 3 and mdy.month == 1 and mdy.day == 2
    assert dmy.year == mdy.year and dmy.month == 2 and dmy.day == 1
    assert ymd.year % 100 == 1 and ymd.month == 2 and ymd.day == 3
    assert ydm.year == ymd.year and ydm.month == 3 and ydm.day == 2
    auto named = parser.parse("01/Feb/03", yearfirst=True)
    assert named.year == ymd.year and named.month == 2 and named.day == 3
    named = parser.parse("01/Feb/03", dayfirst=True)
    assert named.year == mdy.year and named.month == 2 and named.day == 1
    auto inferred = parser.parse("13/02/03", yearfirst=True)
    assert inferred.year % 100 == 13 and inferred.month == 2 and inferred.day == 3
    auto compact = parser.parse("010203", dayfirst=True, yearfirst=True)
    assert compact == ydm

@test
def parser_heuristic_year_window():
    auto current = datetime.date_today().year
    auto lower = current - 50
    auto upper = current + 49
    auto base = parser.isoparse("2000-12-31")
    for suffix in range(100):
        auto spelling = str(suffix)
        if suffix < 10:
            spelling = "0" + spelling
        auto result = parser.parse(spelling + " Jan 15", default=base, yearfirst=True)
        assert result.year >= lower and result.year <= upper
        assert result.year % 100 == suffix and result.month == 1 and result.day == 15

@test
def parser_heuristic_default():
    auto before = datetime.date_today()
    auto parsed = parser.parse("01:02")
    auto after = datetime.date_today()
    assert datetime.to_date(parsed) == before or datetime.to_date(parsed) == after
    assert parsed.hour == 1 and parsed.minute == 2 and parsed.second == 0
    assert parsed.nanosecond == 0 and not parsed.is_aware

    auto fixed = parser.isoparse("2024-01-31T01:02:03+01:30")
    auto exact = datetime.replace(fixed, nanosecond=456789123)
    auto inherited = parser.parse("February 12:30", default=exact)
    assert inherited.year == 2024 and inherited.month == 2 and inherited.day == 29
    assert inherited.hour == 12 and inherited.minute == 30 and inherited.second == 3
    assert inherited.is_aware and inherited.offset == 5400
    assert inherited.nanosecond == 456789123

    auto ignored = parser.parse("12:30:04Z", default=exact, ignoretz=True)
    assert ignored.is_aware and ignored.offset == 5400 and ignored.nanosecond == 0
    auto replaced = parser.parse("12:30Z", default=exact)
    assert replaced.is_aware and replaced.offset == 0 and replaced.nanosecond == 456789123
    assert replaced.hour == 12 and replaced.minute == 30 and replaced.second == 3

    auto zone = datetime.zone("America/New_York")
    auto winter = datetime.resolve(zone, 2024, 1, 31, 12, 0, 0)
    auto summer = parser.parse("July", default=winter)
    assert summer.is_aware and summer.zone_id == winter.zone_id
    assert summer.offset == -14400 and summer.day == 31 and summer.hour == 12

def _reject_heuristic(str value, bool fuzzy = False):
    bool caught = False
    try:
        parser.parse(value, fuzzy=fuzzy)
    except parser.ParserError:
        caught = True
    assert caught, value

@test
def parser_heuristic_invalid_input():
    for value in ["", "  \t\n", "words only", "!", "2024\x00", "２０２４-02-29", "Feb March", "2024-01-2005", "2024/02/10/05/06", "2024-00-01", "2024-13-01", "2024-01-00", "2024-02-30", "2023-02-29", "1900-02-29", "2024 April 31", "0000-01-01", "10000-01-01", "99999", "12: 30", "12:", "12:30:", "12:30:garbage", "12:60", "24:00", "25:01", "99 PM", "12:30:60", "12:30:59.01.02", "12:30:01 13:30:02", "12:00 +", "12:00 -24", "12:00 +2400", "12:00 +05:60", "12:00 +05:", "12:00 +530", "12:00 +01:30:45", "12:00 +010000", "12:00 +0100 -0300", "12:00 +0100Z", "2024-02-29Z", "Today is January 1, 2047 at 8:21:00AM"]:
        _reject_heuristic(value)
    for value in ["just prose!", "tomorrow perhaps", "on Feb 30, 2004", "at 12:61 noon", "it is 12:00+24 now", "before 12:30:garbage", "word\x00 2004"]:
        _reject_heuristic(value, fuzzy=True)
    _reject_heuristic(None)
