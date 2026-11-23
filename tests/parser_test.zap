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
