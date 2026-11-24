import datetime
import datetime_utils.parser as parser
import datetime_utils.rrule as recurrence
import datetime_utils.tz as tz

@test
def rrule_base_dateutil_vectors():
    auto rows = fs.read_file("tests/data/rrule-base-vectors.txt").strip().split("\n")
    assert len(rows) == 168
    for row in rows:
        auto fields = row.split("|")
        auto start = parser.isoparse(fields[1])
        auto rule = recurrence.RRule(
            freq=int64(fields[0]),
            dtstart=start,
            interval=int64(fields[2]),
            count=6,
        )
        auto expected = fields[3].split(",")
        auto index = 0
        for occurrence in rule:
            assert index < len(expected), row
            assert datetime.isoformat(occurrence) == expected[index], row
            index += 1
        assert index == len(expected), row

@test
def rrule_is_lazy_and_reusable():
    auto start = parser.isoparse("2024-12-31T23:59:58.123456")
    auto rule = recurrence.RRule(recurrence.SECONDLY, start)
    auto left = rule.__iter__()
    auto right = rule.__iter__()
    assert datetime.isoformat(left.__next__()) == "2024-12-31T23:59:58"
    assert datetime.isoformat(left.__next__()) == "2024-12-31T23:59:59"
    assert datetime.isoformat(right.__next__()) == "2024-12-31T23:59:58"
    auto n = 0
    for occurrence in rule:
        n += 1
        if n == 3:
            assert datetime.isoformat(occurrence) == "2025-01-01T00:00:00"
            break
    assert n == 3

@test
def rrule_until_and_empty_sets():
    auto start = parser.isoparse("2024-02-27T01:05:06")
    auto end = parser.isoparse("2024-02-29T01:05:06")
    auto rule = recurrence.RRule(recurrence.DAILY, start, until=end)
    auto n = 0
    for occurrence in rule:
        assert occurrence.day == 27 + n
        assert occurrence.hour == 1 and occurrence.minute == 5 and occurrence.second == 6
        n += 1
    assert n == 3

    auto empty = recurrence.RRule(recurrence.DAILY, end, until=start)
    for occurrence in empty:
        assert False, "until earlier than dtstart must yield no occurrence"
    empty = recurrence.RRule(recurrence.DAILY, start, count=0)
    for occurrence in empty:
        assert False, "count zero must yield no occurrence"
    auto exhausted = empty.__iter__()
    bool caught = False
    try:
        exhausted.__next__()
    except StopIteration:
        caught = True
    assert caught

@test
def rrule_dst_and_utc_until():
    auto ny = tz.gettz("America/New_York")
    auto start = datetime.resolve(ny, 2024, 3, 10, 0, 30, 0)
    auto until = parser.isoparse("2024-03-10T07:30:00Z")
    auto n = 0
    for occurrence in recurrence.RRule(recurrence.HOURLY, start, until=until):
        assert occurrence.hour == [0, 1, 3][n]
        assert occurrence.offset == [-18000, -18000, -14400][n]
        assert occurrence.zone_id == start.zone_id and occurrence.minute == 30
        assert not datetime.is_imaginary(occurrence)
        n += 1
    assert n == 3

    n = 0
    for occurrence in recurrence.RRule(recurrence.HOURLY, start, count=4):
        assert occurrence.hour == [0, 1, 3, 4][n]
        n += 1
    assert n == 4

    auto fall = datetime.resolve(ny, 2024, 11, 3, 0, 30, 0)
    n = 0
    for occurrence in recurrence.RRule(recurrence.HOURLY, fall, count=4):
        assert occurrence.hour == n
        assert occurrence.offset == [-14400, -14400, -18000, -18000][n]
        n += 1
    assert n == 4

    auto fixed = parser.isoparse("2024-12-31T23:59:59+05:45")
    auto fixed_until = parser.isoparse("2024-12-31T18:15:00Z")
    n = 0
    for occurrence in recurrence.RRule(recurrence.SECONDLY, fixed, until=fixed_until):
        assert occurrence.offset == 20700
        assert datetime.to_timestamp(occurrence) == datetime.to_timestamp(fixed) + n
        n += 1
    assert n == 2

@test
def rrule_largest_intervals_and_calendar_boundary():
    auto end = parser.isoparse("9999-12-31T23:59:59")
    auto beginning = parser.isoparse("0001-01-01")
    for freq in range(7):
        auto n = 0
        for occurrence in recurrence.RRule(freq, end):
            assert datetime.isoformat(occurrence) == "9999-12-31T23:59:59"
            n += 1
        assert n == 1
        n = 0
        for occurrence in recurrence.RRule(freq, beginning, interval=9223372036854775807):
            assert datetime.isoformat(occurrence) == "0001-01-01T00:00:00"
            n += 1
        assert n == 1

def _reject_rule(recurrence.RRule rule):
    bool caught = False
    try:
        rule.__iter__()
    except ValueError:
        caught = True
    assert caught

@test
def rrule_invalid_options():
    auto naive = parser.isoparse("2024-01-01")
    auto utc = parser.isoparse("2024-01-02T00:00:00Z")
    auto offset = parser.isoparse("2024-01-02T00:00:00+02:00")
    _reject_rule(recurrence.RRule(-1, naive))
    _reject_rule(recurrence.RRule(7, naive))
    _reject_rule(recurrence.RRule(recurrence.DAILY, naive, interval=0))
    _reject_rule(recurrence.RRule(recurrence.DAILY, naive, interval=-1))
    _reject_rule(recurrence.RRule(recurrence.DAILY, naive, count=-1))
    _reject_rule(recurrence.RRule(recurrence.DAILY, naive, until=utc))
    _reject_rule(recurrence.RRule(recurrence.DAILY, utc, until=naive))
    _reject_rule(recurrence.RRule(recurrence.DAILY, utc, until=offset))
    _reject_rule(recurrence.RRule(recurrence.DAILY, naive, count=1, until=naive))

@test
def rrule_default_start_is_local():
    auto before = datetime.now_local()
    auto rule = recurrence.RRule(recurrence.SECONDLY, count=1)
    auto after = datetime.now_local()
    auto it = rule.__iter__()
    auto value = it.__next__()
    assert not value.is_aware and value.nanosecond == 0
    auto wall = datetime.to_timestamp(value)
    assert wall >= datetime.to_timestamp(before) + before.offset
    assert wall <= datetime.to_timestamp(after) + after.offset
    auto again = rule.__iter__()
    assert again.__next__() == value
