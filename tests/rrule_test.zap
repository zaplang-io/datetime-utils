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
            freq=int(fields[0]),
            dtstart=start,
            interval=int(fields[2]),
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

    auto quarter_start = datetime.resolve(ny, 2024, 3, 10, 1, 15, 0)
    auto gap_end = parser.isoparse("2024-03-10T07:00:00Z")
    n = 0
    for occurrence in recurrence.RRule(recurrence.MINUTELY, quarter_start, interval=15, until=gap_end):
        assert occurrence.hour == [1, 1, 1, 3][n]
        assert occurrence.minute == [15, 30, 45, 0][n]
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

def _query_iso(Optional[DateTime] dt) -> str:
    if dt.is_none():
        return "-"
    return datetime.isoformat(dt.unwrap())

@test
def rrule_query_dateutil_vectors():
    auto rows = fs.read_file("tests/data/rrule-query-vectors.txt").strip().split("\n")
    assert len(rows) == 98
    for row in rows:
        auto fields = row.split("|")
        auto target = parser.isoparse(fields[4])
        auto lo = parser.isoparse(fields[5])
        auto hi = parser.isoparse(fields[6])
        auto inc = fields[7] == "1"
        auto rule = recurrence.RRule(
            freq=int(fields[0]),
            dtstart=parser.isoparse(fields[1]),
            interval=int(fields[2]),
            count=int(fields[3]),
        )
        assert rule.count() == int(fields[3]), row
        assert _query_iso(rule.before(dt=target, inc=inc)) == fields[8], row
        assert _query_iso(rule.after(dt=target, inc=inc)) == fields[9], row
        auto between = rule.between(after=lo, before=hi, inc=inc, count=2)
        if fields[10] == "-":
            assert len(between) == 0, row
        else:
            auto expected = fields[10].split(",")
            assert len(between) == len(expected), row
            for i in range(len(between)):
                assert datetime.isoformat(between[i]) == expected[i], row

@test
def rrule_query_empty_and_lazy_rules():
    auto start = parser.isoparse("2024-06-01")
    auto day_two = parser.isoparse("2024-06-02")
    auto day_three = parser.isoparse("2024-06-03")
    auto empty = recurrence.RRule(recurrence.DAILY, start, count=0)
    assert empty.count() == 0
    assert empty.before(start, inc=True).is_none()
    assert empty.after(start, inc=True).is_none()
    assert len(empty.between(start, day_three, inc=True)) == 0

    auto lazy = recurrence.RRule(recurrence.DAILY, start)
    assert lazy.before(start).is_none()
    assert datetime.equal(lazy.before(day_three).unwrap(), day_two)
    assert datetime.equal(lazy.after(start).unwrap(), day_two)
    assert len(lazy.between(after=start, before=day_three, inc=True)) == 3
    assert len(lazy.between(after=day_three, before=start, inc=True)) == 0
    assert datetime.equal(lazy.after(start, inc=True).unwrap(), start)

    auto last_fraction = datetime.replace(day_two, nanosecond=1)
    assert datetime.equal(lazy.before(last_fraction).unwrap(), day_two)
    assert datetime.equal(lazy.after(last_fraction).unwrap(), day_three)
    assert len(lazy.between(after=start, before=last_fraction)) == 1

@test
def rrule_query_fold_and_instant_ordering():
    auto ny = tz.gettz("America/New_York")
    auto start = datetime.resolve(ny, 2024, 11, 3, 0, 30, 0)
    auto rule = recurrence.RRule(recurrence.HOURLY, start, count=4)
    auto fold = datetime.resolve(ny, 2024, 11, 3, 1, 30, 0, fold=1)
    auto as_utc = datetime.astimezone(fold, tz.UTC)
    auto earlier = rule.after(fold, inc=True).unwrap()
    assert earlier.hour == 1 and earlier.offset == -14400
    assert datetime.to_timestamp(fold) - datetime.to_timestamp(earlier) == 3600
    assert datetime.equal(rule.before(fold, inc=True).unwrap(), earlier)
    assert datetime.equal(rule.before(fold).unwrap(), start)
    assert rule.after(fold).unwrap().hour == 2
    assert rule.after(as_utc, inc=True).unwrap().hour == 2
    assert datetime.equal(rule.before(as_utc).unwrap(), earlier)

    auto in_named_zone = rule.between(fold, fold, inc=True)
    assert len(in_named_zone) == 1 and datetime.equal(in_named_zone[0], earlier)
    assert len(rule.between(as_utc, as_utc, inc=True)) == 0
    auto early_utc = datetime.astimezone(earlier, tz.UTC)
    auto in_utc = rule.between(early_utc, early_utc, inc=True)
    assert len(in_utc) == 1 and datetime.equal(in_utc[0], earlier)

@test
def rrule_count_uses_emitted_occurrences():
    auto monthly = recurrence.RRule(
        recurrence.MONTHLY,
        parser.isoparse("2024-01-31"),
        until=parser.isoparse("2024-04-30"),
    )
    assert monthly.count() == 2
    auto year_end = recurrence.RRule(
        recurrence.DAILY,
        parser.isoparse("9999-12-30"),
        count=10,
    )
    assert year_end.count() == 2

    auto ny = tz.gettz("America/New_York")
    auto start = datetime.resolve(ny, 2024, 3, 10, 0, 30, 0)
    auto until = parser.isoparse("2024-03-10T07:30:00Z")
    auto hourly = recurrence.RRule(recurrence.HOURLY, start, until=until)
    assert hourly.count() == 3
    auto hits = hourly.between(start, until, inc=True)
    assert len(hits) == 3 and hits[2].hour == 3

@test
def rrule_queries_reject_mixed_awareness():
    auto naive = parser.isoparse("2024-01-01")
    auto aware = parser.isoparse("2024-01-01T00:00:00Z")
    auto floating = recurrence.RRule(recurrence.DAILY, naive, count=2)
    auto zoned = recurrence.RRule(recurrence.DAILY, aware, count=2)
    auto caught = 0
    try:
        floating.before(aware)
    except TypeError:
        caught += 1
    try:
        zoned.after(naive)
    except TypeError:
        caught += 1
    try:
        zoned.between(after=naive, before=aware, inc=True)
    except TypeError:
        caught += 1
    try:
        floating.between(after=naive, before=aware)
    except TypeError:
        caught += 1
    assert caught == 4
