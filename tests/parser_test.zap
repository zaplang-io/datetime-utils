import datetime
import datetime_utils.parser as parser
import datetime_utils.tz as tz

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
    assert len(rows) == 367
    auto failures = ""
    for row in rows:
        auto fields = row.split("|")
        assert len(fields) == 3
        auto flags = fields[0]
        try:
            auto parsed = parser.parse(
                s=fields[1],
                dayfirst=flags[0] == chr(49),
                yearfirst=flags[1] == chr(49),
                fuzzy=flags[2] == chr(49),
                default=base,
                ignoretz=flags[3] == chr(49),
            )
            auto actual = datetime.isoformat(parsed)
            if actual != fields[2]:
                failures += "\n" + row + " got " + actual
        except parser.ParserError as error:
            failures += "\n" + row + " raised " + error
    assert failures == "", failures

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
    for value in ["", "  \t\n", "words only", "!", "2024\x00", "２０２４-02-29", "Feb March", "2024-01-2005", "2024/02/10/05/06", "2024-00-01", "2024-13-01", "2024-01-00", "2024-02-30", "2023-02-29", "1900-02-29", "2024 April 31", "0000-01-01", "10000-01-01", "99999", "12: 30", "12:", "12:30:", "12:30:garbage", "12:60", "24:00", "25:01", "99 PM", "12:30:60", "12:30:59.01.02", "12:30:01 13:30:02", "12:00 +", "12:00 -24", "12:00 +2400", "12:00 +05:60", "12:00 +05:", "12:00 +530", "12:00 +01:30:45", "12:00 +010000", "12:00 +0100Z", "2024-02-29Z", "Today is January 1, 2047 at 8:21:00AM"]:
        _reject_heuristic(value)
    for value in ["just prose!", "tomorrow perhaps", "on Feb 30, 2004", "at 12:61 noon", "it is 12:00+24 now", "before 12:30:garbage", "word\x00 2004"]:
        _reject_heuristic(value, fuzzy=True)
    _reject_heuristic(None)

@test
def parser_timezone_alias_map():
    auto chicago = tz.gettz("America/Chicago")
    auto aliases = {
        "BRST": tz.tzoffset("BRST", -7201),
        "CST": chicago,
        "UTC": tz.tzoffset("custom UTC", 30),
    }
    auto fixed = parser.parse("2012-01-19 17:21:00 BRST", tzinfos=aliases)
    assert datetime.isoformat(fixed) == "2012-01-19T17:21:00-02:00:01"
    auto winter = parser.parse("2012-01-19 17:21:00 CST", tzinfos=aliases)
    auto summer = parser.parse("2012-07-19 17:21:00 CST", tzinfos=aliases)
    assert winter.zone_id == summer.zone_id and winter.zone_id >= 0
    assert winter.offset == -21600 and summer.offset == -18000
    assert winter.hour == 17 and summer.hour == 17

    for suffix in ["Z", "z", "UTC", "+00", "-0000"]:
        auto utc = parser.parse("2012-01-19 17:21:00 " + suffix, tzinfos=aliases)
        assert utc.is_aware and utc.offset == 30

    auto labeled = parser.parse("2012-01-19 17:21:00 -0300 (BRST)", tzinfos=aliases)
    assert labeled.offset == fixed.offset
    auto unmapped = parser.parse("2012-01-19 17:21:00 -0300 (XYZ)", tzinfos=aliases)
    assert unmapped.is_aware and unmapped.offset == -10800
    auto unmatched = parser.parse("2012-01-19 17:21:00 XYZ", tzinfos=aliases)
    assert not unmatched.is_aware
    auto fuzzy = parser.parse(
        "Meet on 2012-01-19 at 17:21 CST please!",
        fuzzy=True,
        tzinfos=aliases,
    )
    assert fuzzy.zone_id == winter.zone_id and fuzzy.offset == winter.offset

def _select_parsed_zone(
    Optional[str] name,
    Optional[int64] offset,
) -> Optional[TimeZone]:
    if name.is_some():
        if name.unwrap() == "BRST" and offset.is_some() and offset.unwrap() == -10800:
            return tz.tzoffset("BRST", -7201)
        if name.unwrap() == "CST" and offset.is_none():
            return tz.gettz("America/Chicago")
        if name.unwrap() == "UTC" and offset.is_some() and offset.unwrap() == 0:
            return tz.tzoffset("custom UTC", 30)
    elif offset.is_none():
        return tz.tzoffset("resolver default", 120)
    elif offset.unwrap() == 19800:
        return tz.tzoffset("resolver numeric", 45)
    return None

@test
def parser_timezone_resolver():
    auto labeled = parser.parse(
        "2012-01-19 17:21:00 -0300 (BRST)",
        tzresolver=_select_parsed_zone,
    )
    assert labeled.is_aware and labeled.offset == -7201
    auto reversed = parser.parse(
        "2012-01-19 17:21:00 BRST+3",
        tzresolver=_select_parsed_zone,
    )
    assert reversed.is_aware and reversed.offset == -7201
    auto named = parser.parse("2012-01-19 17:21:00 CST", tzresolver=_select_parsed_zone)
    assert named.zone_id >= 0 and named.offset == -21600
    auto numeric = parser.parse(
        "2012-01-19 17:21:00+05:30",
        tzresolver=_select_parsed_zone,
    )
    assert numeric.is_aware and numeric.offset == 45
    auto utc = parser.parse("2012-01-19 17:21:00Z", tzresolver=_select_parsed_zone)
    assert utc.is_aware and utc.offset == 30
    auto absent = parser.parse("2012-01-19", tzresolver=_select_parsed_zone)
    assert absent.is_aware and absent.offset == 120
    auto base = parser.isoparse("2024-01-31T01:02:03.123456+02:00")
    auto dropped = parser.parse(
        "February 17:21:00 xyz",
        fuzzy=True,
        default=base,
        tzresolver=_select_parsed_zone,
    )
    assert dropped.is_aware and dropped.offset == 120
    dropped = parser.parse(
        "February 17:21+01:00",
        default=base,
        tzresolver=_select_parsed_zone,
    )
    assert not dropped.is_aware
    assert datetime.isoformat(dropped) == "2024-02-29T17:21:03.123456"

def _unused_zone_resolver(
    Optional[str] name,
    Optional[int64] offset,
) -> Optional[TimeZone]:
    assert False, "ignoretz must skip the timezone resolver"
    return None

@test
def parser_timezone_options_ignore_and_errors():
    auto base = parser.isoparse("2024-01-31T01:02:03.123456+02:00")
    auto zones = {"CST": tz.gettz("America/Chicago")}
    for suffix in [" CST", " +0100", " -0300 (CST)", " UTC", "Z", ""]:
        auto ignored = parser.parse(
            "February 17:21" + suffix,
            default=base,
            ignoretz=True,
            tzinfos=zones,
            tzresolver=_unused_zone_resolver,
        )
        assert datetime.isoformat(ignored) == "2024-02-29T17:21:03.123456+02:00"
    bool caught = False
    try:
        parser.parse("February", tzinfos=zones, tzresolver=_select_parsed_zone)
    except parser.ParserError:
        caught = True
    assert caught

    for suffix in [" (CST)", " -0300 (cst)", " -0300 (CST", " -0300 CST", " ABCDEF", " cst"]:
        _reject_heuristic("2012-01-19 17:21:00" + suffix)

def _new_york_fold_zone(
    Optional[str] name,
    Optional[int64] offset,
) -> Optional[TimeZone]:
    if name.is_some() and name.unwrap() == "EST" and offset.is_none():
        return tz.gettz("America/New_York")
    return None

@test
def parser_timezone_fold_aliases():
    auto ny = tz.gettz("America/New_York")
    auto aliases = {"EDT": ny, "EST": ny, "XYZ": ny}
    auto early = parser.parse("2024-11-03 01:30:00.123456 EDT", tzinfos=aliases)
    auto late = parser.parse("2024-11-03 01:30:00.123456 EST", tzinfos=aliases)
    assert early.offset == -14400 and late.offset == -18000
    assert early.nanosecond == 123456000 and late.nanosecond == early.nanosecond
    assert early.zone_id >= 0 and late.zone_id == early.zone_id
    assert datetime.to_timestamp(late) - datetime.to_timestamp(early) == 3600
    assert datetime.zone_abbreviation(early).unwrap() == "EDT"
    assert datetime.zone_abbreviation(late).unwrap() == "EST"

    auto unmatched = parser.parse("2024-11-03 01:30:00.123456 XYZ", tzinfos=aliases)
    assert datetime.to_timestamp(unmatched) == datetime.to_timestamp(early)

    auto base = datetime.replace(parser.isoparse("2024-11-03"), nanosecond=123456789)
    auto inherited = parser.parse(
        "01:30 EST",
        default=base,
        tzresolver=_new_york_fold_zone,
    )
    assert inherited.nanosecond == 123456789 and inherited.offset == late.offset
    assert datetime.to_timestamp(inherited) == datetime.to_timestamp(late)

    auto paris = tz.gettz("Europe/Paris")
    auto europe = {"CEST": paris, "CET": paris}
    auto before = parser.parse("2024-10-27 02:30:00.000001 CEST", tzinfos=europe)
    auto after = parser.parse("2024-10-27 02:30:00.000001 CET", tzinfos=europe)
    assert datetime.isoformat(before) == "2024-10-27T02:30:00.000001+02:00"
    assert datetime.isoformat(after) == "2024-10-27T02:30:00.000001+01:00"

    auto gap = parser.parse("2024-03-10 02:30:00.123456 EST", tzinfos=aliases)
    auto gap_default = datetime.resolve(ny, 2024, 3, 10, 2, 30, 0, nanosecond=123456000)
    assert datetime.is_imaginary(gap)
    assert datetime.isoformat(gap) == datetime.isoformat(gap_default)

    auto ignored = parser.parse(
        "2024-11-03 01:30:00.123456 EST",
        tzinfos=aliases,
        ignoretz=True,
    )
    assert not ignored.is_aware and ignored.nanosecond == 123456000
