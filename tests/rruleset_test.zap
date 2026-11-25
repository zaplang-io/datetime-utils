import datetime
import datetime_utils.parser as parser
import datetime_utils.rrule as recurrence
import datetime_utils.tz as tz

@test
def rruleset_dateutil_vectors():
    auto rows = fs.read_file("tests/data/rruleset-vectors.txt").strip().split("\n")
    assert len(rows) == 72
    auto first = parser.isoparse("2024-01-01")
    auto second = parser.isoparse("2024-01-02")
    auto fourth = parser.isoparse("2024-01-04")
    for row in rows:
        auto fields = row.split("|")
        auto rule_set = recurrence.RRuleSet()
        rule_set.rrule(
            recurrence.RRule(
                recurrence.DAILY,
                first,
                interval=int(fields[0]),
                count=10,
            ),
        )
        rule_set.rrule(
            recurrence.RRule(
                recurrence.DAILY,
                second,
                interval=int(fields[1]),
                count=8,
            ),
        )
        rule_set.exrule(
            recurrence.RRule(
                recurrence.DAILY,
                fourth,
                interval=int(fields[2]),
                count=4,
            ),
        )
        if fields[3] == "1":
            for date in ["2024-01-12", "2023-12-31", "2024-01-04T00:00:00.000001", "2024-01-02", "2024-01-02"]:
                rule_set.rdate(parser.isoparse(date))
            for date in ["2024-01-03", "2024-01-12"]:
                rule_set.exdate(parser.isoparse(date))
        auto expected = fields[4].split(",")
        auto n = 0
        for occurrence in rule_set:
            assert n < len(expected), row
            auto actual = datetime.isoformat(occurrence)
            assert actual == expected[n], row + " got " + actual
            n += 1
        if fields[4] == "-":
            assert n == 0, row
        else:
            assert n == len(expected), row

@test
def rruleset_queries_use_merged_occurrences():
    auto rule_set = recurrence.RRuleSet()
    auto first = parser.isoparse("2024-01-01")
    auto second = parser.isoparse("2024-01-02")
    auto third = parser.isoparse("2024-01-03")
    auto fourth = parser.isoparse("2024-01-04")
    rule_set.rrule(recurrence.RRule(recurrence.DAILY, first, count=4))
    rule_set.rdate(fourth)
    rule_set.exdate(second)
    assert rule_set.count() == 3
    assert rule_set.before(first).is_none()
    assert rule_set.after(fourth).is_none()
    assert datetime.equal(rule_set.after(first, inc=True).unwrap(), first)
    assert datetime.equal(rule_set.before(second).unwrap(), first)
    assert datetime.equal(rule_set.after(second).unwrap(), third)
    assert datetime.equal(rule_set.before(fourth).unwrap(), third)
    auto open = rule_set.between(first, fourth, count=1)
    assert len(open) == 1 and datetime.equal(open[0], third)
    auto closed = rule_set.between(after=first, before=fourth, inc=True)
    assert len(closed) == 3 and datetime.equal(closed[2], fourth)
    assert len(rule_set.between(fourth, first, inc=True)) == 0

@test
def rruleset_sorts_explicit_dates_at_full_precision():
    auto rule_set = recurrence.RRuleSet()
    auto far_past = parser.isoparse("0001-01-01T00:00:00.000002")
    auto near_epoch = parser.isoparse("1970-01-01T00:00:00")
    auto far_future = parser.isoparse("9999-12-31T23:59:59.000003")
    auto earlier = datetime.replace(near_epoch, nanosecond=1)
    auto later = datetime.replace(near_epoch, nanosecond=2)
    rule_set.rdate(later)
    rule_set.rdate(far_future)
    rule_set.rdate(earlier)
    rule_set.rdate(far_past)
    rule_set.rdate(near_epoch)
    rule_set.rdate(later)
    rule_set.exdate(near_epoch)
    auto dates = rule_set.between(far_past, far_future, inc=True)
    assert len(dates) == 4
    assert datetime.equal(dates[0], far_past)
    assert datetime.equal(dates[1], earlier)
    assert datetime.equal(dates[2], later)
    assert datetime.equal(dates[3], far_future)

@test
def rruleset_deduplicates_and_excludes_aware_instants():
    auto ny = tz.gettz("America/New_York")
    auto early = datetime.resolve(ny, 2024, 11, 3, 1, 30, 0, fold=0)
    auto late = datetime.resolve(ny, 2024, 11, 3, 1, 30, 0, fold=1)
    auto early_utc = datetime.astimezone(early, tz.UTC)
    auto late_utc = datetime.astimezone(late, tz.UTC)
    auto rule_set = recurrence.RRuleSet()
    rule_set.rdate(late)
    rule_set.rdate(early)
    rule_set.rdate(early_utc)
    rule_set.rrule(recurrence.RRule(recurrence.HOURLY, early, count=1))
    assert rule_set.count() == 2
    auto before = rule_set.before(late_utc).unwrap()
    assert before.zone_id == early.zone_id and before.offset == -14400
    assert rule_set.after(early).unwrap().offset == -18000

    auto other = parser.isoparse("2024-11-03T06:30:00+02:00")
    rule_set.rdate(other)
    assert datetime.equal(rule_set.before(early_utc).unwrap(), other)
    rule_set.exdate(early_utc)
    rule_set.exrule(recurrence.RRule(recurrence.SECONDLY, other, count=1))
    assert rule_set.count() == 1
    assert rule_set.after(early_utc).unwrap().offset == late.offset

@test
def rruleset_iterators_snapshot_and_merge_lazily():
    auto first = parser.isoparse("2024-01-01")
    auto second = parser.isoparse("2024-01-02")
    auto third = parser.isoparse("2024-01-03")
    auto source = recurrence.RRule(recurrence.DAILY, first)
    auto rule_set = recurrence.RRuleSet()
    rule_set.rrule(source)
    rule_set.exdate(second)
    auto left = rule_set.__iter__()
    auto right = rule_set.__iter__()
    source.interval = 2
    rule_set.exdate(third)
    rule_set.rdate(parser.isoparse("2023-12-31"))
    assert datetime.equal(left.__next__(), first)
    assert datetime.equal(left.__next__(), third)
    assert datetime.equal(right.__next__(), first)
    assert datetime.equal(right.__next__(), third)
    auto changed = rule_set.__iter__()
    assert changed.__next__().year == 2023
    assert datetime.equal(changed.__next__(), first)
    assert changed.__next__().day == 5

@test
def rruleset_empty_and_fully_excluded():
    auto first = parser.isoparse("2024-01-01")
    auto rule = recurrence.RRule(recurrence.DAILY, first, count=4)
    auto empty = recurrence.RRuleSet()
    auto other = recurrence.RRuleSet()
    other.rdate(first)
    assert empty.count() == 0 and other.count() == 1
    empty.exrule(rule)
    empty.exdate(first)
    assert empty.count() == 0
    empty.rrule(rule)
    empty.rdate(first)
    assert empty.count() == 0
    assert empty.after(first, inc=True).is_none()
    auto cursor = empty.__iter__()
    auto caught = 0
    for attempt in range(2):
        try:
            cursor.__next__()
        except StopIteration:
            caught += 1
    assert caught == 2

@test
def rruleset_rejects_mixed_awareness():
    auto local = parser.isoparse("2024-01-01")
    auto aware = parser.isoparse("2024-01-01T00:00:00Z")
    auto dates = recurrence.RRuleSet()
    dates.rdate(local)
    dates.rdate(aware)
    auto sources = recurrence.RRuleSet()
    sources.rdate(local)
    sources.rrule(recurrence.RRule(recurrence.DAILY, aware, count=1))
    auto exclusions = recurrence.RRuleSet()
    exclusions.rdate(aware)
    exclusions.exdate(local)
    auto caught = 0
    for rule_set in [dates, sources, exclusions]:
        try:
            rule_set.count()
        except TypeError:
            caught += 1
    assert caught == 3
