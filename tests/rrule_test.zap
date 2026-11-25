import datetime
import datetime_utils.parser as parser
import datetime_utils.relativedelta as rd
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

def _month_vector_option(str field) -> Optional[list[int64]]:
    if field == "-":
        return None
    list[int64] values = []
    if field != "_":
        for value in field.split(","):
            values.append(int(value))
    return values

@test
def rrule_month_filter_dateutil_vectors():
    auto rows = fs.read_file("tests/data/rrule-month-vectors.txt").strip().split("\n")
    assert len(rows) == 184
    for row in rows:
        auto fields = row.split("|")
        auto rule = recurrence.RRule(
            freq=int(fields[0]),
            dtstart=parser.isoparse(fields[1]),
            interval=int(fields[2]),
            count=4,
            bymonth=_month_vector_option(fields[3]),
            bymonthday=_month_vector_option(fields[4]),
        )
        auto expected = fields[5].split(",")
        auto index = 0
        for occurrence in rule:
            assert index < len(expected), row
            assert datetime.isoformat(occurrence) == expected[index], row
            index += 1
        if fields[5] == "-":
            assert index == 0, row
        else:
            assert index == len(expected), row

@test
def rrule_month_filter_bounds_and_impossible_days():
    auto start = parser.isoparse("2024-01-01T07:00:00")
    auto until = parser.isoparse("2024-02-29T07:00:00")
    auto leapday = recurrence.RRule(
        recurrence.SECONDLY,
        start,
        interval=3600,
        until=until,
        bymonth=[2],
        bymonthday=[29, -1],
    )
    assert leapday.count() == 8
    assert datetime.isoformat(leapday.before(until, inc=True).unwrap()) == "2024-02-29T07:00:00"

    auto before_feb = recurrence.RRule(
        recurrence.SECONDLY,
        start,
        until=parser.isoparse("2024-01-31T23:59:59"),
        bymonth=[2],
    )
    assert before_feb.count() == 0

    auto invalid_february = recurrence.RRule(
        recurrence.SECONDLY,
        start,
        count=1,
        bymonth=[2],
        bymonthday=[30, 31, -30, -31],
    )
    assert invalid_february.count() == 0

    auto exhausted = recurrence.RRule(
        recurrence.YEARLY,
        parser.isoparse("9999-04-01"),
        count=10,
        interval=9223372036854775807,
        bymonth=[1, 10, 12],
        bymonthday=[1, -1],
    )
    assert exhausted.count() == 4

@test
def rrule_month_filter_snapshot_and_dst():
    auto ny = tz.gettz("America/New_York")
    auto start = datetime.resolve(ny, 2024, 3, 1, 2, 30, 0)
    list[int64] days = [10, 11, 12]
    auto rule = recurrence.RRule(
        recurrence.MONTHLY,
        start,
        count=2,
        bymonth=[3],
        bymonthday=days,
    )
    auto iter = rule.__iter__()
    days.append(1)
    auto first = iter.__next__()
    auto second = iter.__next__()
    assert first.day == 11 and second.day == 12
    assert first.hour == 2 and first.minute == 30 and first.offset == -14400
    assert not datetime.is_imaginary(first) and not datetime.is_imaginary(second)
    assert rule.after(start, inc=True).unwrap().day == 1

@test
def rrule_month_filter_validates_arguments():
    auto start = parser.isoparse("2024-01-01")
    _reject_rule(recurrence.RRule(recurrence.YEARLY, start, bymonth=[0]))
    _reject_rule(recurrence.RRule(recurrence.YEARLY, start, bymonth=[13]))
    _reject_rule(recurrence.RRule(recurrence.YEARLY, start, bymonth=[-1]))
    _reject_rule(recurrence.RRule(recurrence.MONTHLY, start, bymonthday=[0]))
    _reject_rule(recurrence.RRule(recurrence.MONTHLY, start, bymonthday=[32]))
    _reject_rule(recurrence.RRule(recurrence.MONTHLY, start, bymonthday=[-32]))
    _reject_rule(recurrence.RRule(recurrence.WEEKLY, start, bymonthday=[1]))

def _weekday_vector_option(str field) -> list[rd.Weekday]:
    list[rd.Weekday] values = []
    if field != "_":
        for value in field.split(","):
            auto parts = value.split(":")
            values.append(rd.Weekday(int(parts[0]), int(parts[1])))
    return values

@test
def rrule_weekday_dateutil_vectors():
    auto rows = fs.read_file("tests/data/rrule-weekday-vectors.txt").strip().split("\n")
    assert len(rows) == 167
    for row in rows:
        auto fields = row.split("|")
        Optional[int64] limit = 6
        Optional[DateTime] cutoff = None
        if fields[7] != "-":
            limit = None
            cutoff = parser.isoparse(fields[7])
        auto rule = recurrence.RRule(
            freq=int(fields[0]),
            dtstart=parser.isoparse(fields[1]),
            interval=int(fields[2]),
            count=limit,
            until=cutoff,
            wkst=rd.Weekday(int(fields[3]), 0),
            bymonth=_month_vector_option(fields[4]),
            bymonthday=_month_vector_option(fields[5]),
            byweekday=_weekday_vector_option(fields[6]),
        )
        auto expected = fields[8].split(",")
        auto n = 0
        for occurrence in rule:
            assert n < len(expected), row
            assert datetime.isoformat(occurrence) == expected[n], row + " got " + datetime.isoformat(occurrence)
            n += 1
        if fields[8] == "-":
            assert n == 0, row
        else:
            assert n == len(expected), row

@test
def rrule_weekday_combines_plain_and_ordinal_selectors():
    auto start = parser.isoparse("2024-02-01")
    auto rule = recurrence.RRule(
        recurrence.MONTHLY,
        start,
        byweekday=[rd.FR, rd.MO(1), rd.FR(1), rd.MO(1)],
        until=parser.isoparse("2024-02-29"),
    )
    auto n = 0
    for occurrence in rule:
        assert occurrence.day == [2, 5, 9, 16, 23][n]
        n += 1
    assert n == 5

@test
def rrule_weekday_wkst_and_partial_week_bounds():
    auto start = parser.isoparse("1997-08-05T09:00:00")
    auto end = parser.isoparse("1997-08-24T09:00:00")
    auto monday = recurrence.RRule(
        recurrence.WEEKLY,
        start,
        interval=2,
        until=end,
        byweekday=[rd.SU, rd.TU],
    )
    auto sunday = recurrence.RRule(
        recurrence.WEEKLY,
        start,
        interval=2,
        until=end,
        wkst=rd.SU,
        byweekday=[rd.SU, rd.TU],
    )
    auto n = 0
    for occurrence in monday:
        assert occurrence.day == [5, 10, 19, 24][n]
        n += 1
    assert n == 4
    n = 0
    for occurrence in sunday:
        assert occurrence.day == [5, 17, 19][n]
        n += 1
    assert n == 3

@test
def rrule_weekday_snapshot_and_dst():
    auto zone = tz.gettz("America/New_York")
    auto start = datetime.resolve(zone, 2024, 3, 3, 2, 30, 0)
    list[rd.Weekday] days = [rd.SU]
    auto rule = recurrence.RRule(recurrence.WEEKLY, start, count=3, byweekday=days)
    auto cursor = rule.__iter__()
    days.append(rd.MO)
    assert cursor.__next__().day == 3
    auto next = cursor.__next__()
    assert next.day == 17 and next.hour == 2 and next.offset == -14400
    assert cursor.__next__().day == 24
    assert rule.after(start).unwrap().day == 4

@test
def rrule_weekday_validates_arguments():
    auto start = parser.isoparse("2024-01-01")
    _reject_rule(
        recurrence.RRule(recurrence.YEARLY, start, byweekday=[rd.Weekday(7, 0)]),
    )
    _reject_rule(
        recurrence.RRule(recurrence.YEARLY, start, byweekday=[rd.Weekday(-1, 0)]),
    )
    _reject_rule(recurrence.RRule(recurrence.MONTHLY, start, byweekday=[rd.FR(54)]))
    _reject_rule(recurrence.RRule(recurrence.MONTHLY, start, byweekday=[rd.FR(-54)]))
    for freq in range(recurrence.WEEKLY, recurrence.SECONDLY + 1):
        _reject_rule(recurrence.RRule(freq, start, byweekday=[rd.FR(1)]))
    _reject_rule(recurrence.RRule(recurrence.WEEKLY, start, wkst=rd.MO(-1)))
    _reject_rule(recurrence.RRule(recurrence.WEEKLY, start, wkst=rd.Weekday(7, 0)))

@test
def rrule_clock_dateutil_vectors():
    auto rows = fs.read_file("tests/data/rrule-clock-vectors.txt").strip().split("\n")
    assert len(rows) == 135
    for row in rows:
        auto fields = row.split("|")
        auto rule = recurrence.RRule(
            freq=int(fields[0]),
            dtstart=parser.isoparse(fields[1]),
            interval=int(fields[2]),
            count=5,
            byhour=_month_vector_option(fields[3]),
            byminute=_month_vector_option(fields[4]),
            bysecond=_month_vector_option(fields[5]),
        )
        auto expected = fields[6].split(",")
        auto n = 0
        for occurrence in rule:
            assert n < len(expected), row
            auto actual = datetime.isoformat(occurrence)
            assert actual == expected[n], row + " got " + actual
            n += 1
        if fields[6] == "-":
            assert n == 0, row
        else:
            assert n == len(expected), row

@test
def rrule_clock_clips_within_periods():
    auto daily = recurrence.RRule(
        recurrence.DAILY,
        parser.isoparse("2024-02-01T10:20:30.123456"),
        until=parser.isoparse("2024-02-01T11:00:00"),
        byhour=[9, 10, 11],
        byminute=[0, 20],
        bysecond=[0, 30],
    )
    auto n = 0
    for occurrence in daily:
        assert datetime.isoformat(occurrence) == ["2024-02-01T10:20:30", "2024-02-01T11:00:00"][n]
        n += 1
    assert n == 2

    auto hourly = recurrence.RRule(
        recurrence.HOURLY,
        parser.isoparse("2024-02-01T10:30:00"),
        until=parser.isoparse("2024-02-01T11:00:00"),
        byminute=[0, 15, 45],
    )
    n = 0
    for occurrence in hourly:
        assert datetime.isoformat(occurrence) == ["2024-02-01T10:45:00", "2024-02-01T11:00:00"][n]
        n += 1
    assert n == 2

    auto cutoff = parser.isoparse("2024-02-01T11:00:00")
    auto minutely = recurrence.RRule(
        recurrence.MINUTELY,
        parser.isoparse("2024-02-01T10:59:45"),
        until=cutoff,
        bysecond=[0, 30],
    )
    assert minutely.count() == 1
    assert datetime.equal(minutely.before(cutoff, inc=True).unwrap(), cutoff)

@test
def rrule_clock_combines_date_filters_and_snapshots_choices():
    auto start = parser.isoparse("2024-02-07T10:20:30")
    list[int64] hours = [20, 10, 20]
    auto rule = recurrence.RRule(
        recurrence.WEEKLY,
        start,
        count=4,
        wkst=rd.SU,
        bymonth=[2],
        byweekday=[rd.TU, rd.WE],
        byhour=hours,
        byminute=[0, 40],
    )
    auto cursor = rule.__iter__()
    hours.append(12)
    auto expected = [
        "2024-02-07T10:40:30",
        "2024-02-07T20:00:30",
        "2024-02-07T20:40:30",
        "2024-02-13T10:00:30",
    ]
    auto n = 0
    for occurrence in cursor:
        assert datetime.isoformat(occurrence) == expected[n]
        n += 1
    assert n == 4
    assert datetime.isoformat(rule.after(parser.isoparse("2024-02-07T10:41:00")).unwrap()) == "2024-02-07T12:00:30"

@test
def rrule_clock_gap_and_fold_with_expansion():
    auto ny = tz.gettz("America/New_York")
    auto gap_start = datetime.resolve(ny, 2024, 3, 10, 1, 50, 0)
    auto gap_rule = recurrence.RRule(
        recurrence.HOURLY,
        gap_start,
        until=parser.isoparse("2024-03-10T07:00:00Z"),
        byminute=[0, 50],
    )
    auto n = 0
    for occurrence in gap_rule:
        assert occurrence.hour == [1, 3][n]
        assert occurrence.minute == [50, 0][n]
        assert occurrence.offset == [-18000, -14400][n]
        assert not datetime.is_imaginary(occurrence)
        n += 1
    assert n == 2

    auto fold_start = datetime.resolve(ny, 2024, 11, 3, 0, 0, 0)
    auto fold_rule = recurrence.RRule(
        recurrence.DAILY,
        fold_start,
        count=2,
        byhour=[1, 2],
        byminute=[30],
    )
    n = 0
    for occurrence in fold_rule:
        assert occurrence.hour == n + 1
        assert occurrence.offset == [-14400, -18000][n]
        n += 1
    assert n == 2

@test
def rrule_clock_empty_and_unreachable_phase():
    auto start = parser.isoparse("1969-12-30T10:20:30")
    assert recurrence.RRule(recurrence.HOURLY, start, interval=24, byhour=[11]).count() == 0
    assert recurrence.RRule(recurrence.MINUTELY, start, interval=60, byminute=[21]).count() == 0
    assert recurrence.RRule(recurrence.SECONDLY, start, interval=120, byminute=[21], bysecond=[30]).count() == 0
    assert recurrence.RRule(recurrence.SECONDLY, start, interval=2, bysecond=[31]).count() == 0

    auto interval = recurrence.RRule(
        recurrence.SECONDLY,
        start,
        interval=2,
        count=3,
        bysecond=[31, 32],
    )
    assert interval.count() == 3
    assert interval.after(start).unwrap().second == 32

    list[int64] no_times = []
    for freq in range(7):
        assert recurrence.RRule(freq, start, byhour=no_times).count() == 0
        assert recurrence.RRule(freq, start, byminute=no_times).count() == 0
        assert recurrence.RRule(freq, start, bysecond=no_times).count() == 0

@test
def rrule_clock_validates_options():
    auto start = parser.isoparse("2024-01-01")
    _reject_rule(recurrence.RRule(recurrence.YEARLY, start, byhour=[-1]))
    _reject_rule(recurrence.RRule(recurrence.MONTHLY, start, byhour=[0, 24]))
    _reject_rule(recurrence.RRule(recurrence.WEEKLY, start, byminute=[-1]))
    _reject_rule(recurrence.RRule(recurrence.DAILY, start, byminute=[59, 60]))
    _reject_rule(recurrence.RRule(recurrence.HOURLY, start, bysecond=[-1]))
    _reject_rule(recurrence.RRule(recurrence.MINUTELY, start, bysecond=[59, 60]))

@test
def rrule_year_day_and_easter_dateutil_vectors():
    auto rows = fs.read_file("tests/data/rrule-year-day-vectors.txt").strip().split(
        "\n",
    )
    assert len(rows) == 150
    for row in rows:
        auto fields = row.split("|")
        auto rule = recurrence.RRule(
            freq=int(fields[0]),
            dtstart=parser.isoparse(fields[1]),
            interval=int(fields[2]),
            count=5,
            byyearday=_month_vector_option(fields[3]),
            byeaster=_month_vector_option(fields[4]),
            bymonth=_month_vector_option(fields[5]),
        )
        auto expected = fields[6].split(",")
        auto n = 0
        for occurrence in rule:
            assert n < len(expected), row
            auto actual = datetime.isoformat(occurrence)
            assert actual == expected[n], row + " got " + actual
            n += 1
        if fields[6] == "-":
            assert n == 0, row
        else:
            assert n == len(expected), row

@test
def rrule_signed_year_days_and_century_leaps():
    auto start = parser.isoparse("2096-01-01")
    auto end = parser.isoparse("2104-12-31")
    auto selected = recurrence.RRule(
        recurrence.YEARLY,
        start,
        until=end,
        byyearday=[-366, 366],
    )
    auto dates = selected.between(start, end, inc=True)
    assert len(dates) == 4
    assert datetime.isoformat(dates[0]) == "2096-01-01T00:00:00"
    assert datetime.isoformat(dates[1]) == "2096-12-31T00:00:00"
    assert datetime.isoformat(dates[2]) == "2104-01-01T00:00:00"
    assert datetime.isoformat(dates[3]) == "2104-12-31T00:00:00"

    auto leap_day = recurrence.RRule(
        recurrence.YEARLY,
        start,
        until=end,
        byyearday=[60, -307, 60],
        bymonth=[2],
        bymonthday=[29],
    )
    assert leap_day.count() == 2
    assert leap_day.after(start).unwrap().day == 29
    assert leap_day.before(end).unwrap().year == 2104

@test
def rrule_easter_offsets_cross_years_and_keep_yearly_phase():
    auto dec = parser.isoparse("2023-12-01")
    auto dec31 = parser.isoparse("2023-12-31")
    auto negative = recurrence.RRule(
        recurrence.YEARLY,
        dec,
        until=dec31,
        byeaster=[-91],
    )
    assert negative.count() == 1
    assert datetime.equal(negative.after(dec).unwrap(), dec31)

    auto start = parser.isoparse("2024-01-01")
    auto cutoff = parser.isoparse("2026-01-01")
    auto positive = recurrence.RRule(
        recurrence.YEARLY,
        start,
        until=cutoff,
        byeaster=[276, 276],
    )
    auto dates = positive.between(start, cutoff, inc=True)
    assert len(dates) == 2
    assert datetime.isoformat(dates[0]) == "2024-01-10T00:00:00"
    assert datetime.isoformat(dates[1]) == "2025-01-01T00:00:00"
    auto phase = recurrence.RRule(
        recurrence.YEARLY,
        start,
        interval=2,
        until=cutoff,
        byeaster=[276],
    )
    assert phase.count() == 1
    assert datetime.equal(phase.after(start).unwrap(), dates[0])

@test
def rrule_easter_anchor_bounds_and_impossible_offsets():
    auto first = recurrence.RRule(
        recurrence.YEARLY,
        parser.isoparse("1582-01-01"),
        count=1,
        byeaster=[0],
    )
    assert datetime.isoformat(first.after(parser.isoparse("1582-01-01")).unwrap()) == "1583-04-10T00:00:00"
    auto last = recurrence.RRule(
        recurrence.YEARLY,
        parser.isoparse("4099-01-01"),
        count=2,
        byeaster=[0],
    )
    assert last.count() == 1
    assert datetime.isoformat(last.before(parser.isoparse("4101-01-01")).unwrap()) == "4099-04-19T00:00:00"
    auto shifted_last = recurrence.RRule(
        recurrence.DAILY,
        parser.isoparse("4100-01-01"),
        until=parser.isoparse("4100-01-31"),
        byeaster=[276],
    )
    assert shifted_last.count() == 1
    assert shifted_last.after(parser.isoparse("4100-01-01")).unwrap().day == 20

    auto impossible = recurrence.RRule(
        recurrence.SECONDLY,
        parser.isoparse("2024-01-01"),
        count=1,
        byeaster=[9223372036854775807, -9223372036854775807 - 1],
    )
    assert impossible.count() == 0

@test
def rrule_easter_retains_wall_clock_and_snapshots_offsets():
    auto ny = tz.gettz("America/New_York")
    auto start = datetime.resolve(ny, 2024, 3, 1, 10, 15, 20)
    list[int64] offsets = [0, 1]
    auto rule = recurrence.RRule(
        recurrence.YEARLY,
        start,
        count=4,
        byeaster=offsets,
        byhour=[9, 10],
    )
    auto cursor = rule.__iter__()
    offsets.append(-2)
    auto first = cursor.__next__()
    assert datetime.isoformat(first) == "2024-03-31T09:15:20-04:00"
    assert datetime.isoformat(cursor.__next__()) == "2024-03-31T10:15:20-04:00"
    assert datetime.isoformat(cursor.__next__()) == "2024-04-01T09:15:20-04:00"
    assert datetime.isoformat(cursor.__next__()) == "2024-04-01T10:15:20-04:00"
    assert rule.after(start).unwrap().day == 29

@test
def rrule_year_day_validates_options():
    auto start = parser.isoparse("2024-01-01")
    for invalid in [0, -367, 367]:
        _reject_rule(recurrence.RRule(recurrence.YEARLY, start, byyearday=[1, invalid]))
    for freq in range(recurrence.MONTHLY, recurrence.DAILY + 1):
        _reject_rule(recurrence.RRule(freq, start, byyearday=[1]))
