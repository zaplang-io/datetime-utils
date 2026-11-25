import datetime
import datetime_utils.parser as parser
import datetime_utils.relativedelta as rd
import datetime_utils.rrule as recurrence

@test
def rrulestr_dateutil_reference_sequences():
    auto rows = fs.read_file("tests/data/rrulestr-vectors.txt").strip().split("\n")
    assert len(rows) == 50
    for row in rows:
        auto fields = row.split("|")
        auto rule = recurrence.rrulestr("DTSTART:" + fields[0] + "\nRRULE:" + fields[1])
        auto expected = fields[2].split(",")
        auto index = 0
        for occurrence in rule:
            assert index < len(expected), row
            auto actual = datetime.isoformat(occurrence)
            assert actual == expected[index], row + " got " + actual
            index += 1
        if fields[2] == "-":
            assert index == 0, row
        else:
            assert index == len(expected), row

@test
def rrulestr_constructed_rule_and_start_override():
    auto start = parser.isoparse("2024-01-01T09:30:00")
    auto typed = recurrence.RRule(
        recurrence.MONTHLY,
        start,
        interval=2,
        count=10,
        byweekday=[rd.MO, rd.FR(-1)],
        byhour=[9, 15],
        bysetpos=[1, -1],
    )
    auto text = recurrence.rrulestr(
        "count=10;freq=monthly;interval=2;byday=mo,-1fr;byhour=15,9;bysetpos=1,-1",
        dtstart=start,
    )
    auto cursor = text.__iter__()
    for value in typed:
        assert datetime.equal(value, cursor.__next__())
    assert text.count() == 10

    auto override = recurrence.rrulestr(
        "RRULE:FREQ=DAILY;COUNT=1\nDTSTART;VALUE=DATE:20240229",
        dtstart=start,
    )
    assert datetime.isoformat(override.after(start).unwrap()) == "2024-02-29T00:00:00"

@test
def rrulestr_multiline_inclusions_and_exclusions():
    auto text = "DTSTART:20240101T090000\nRRULE:FREQ=DAILY;COUNT=5\nRRULE:FREQ=DAILY;INTERVAL=2;COUNT=4\n"
    text += "RDATE:20240109T090000,20240103T090000,20231231T090000\n"
    text += "EXRULE:FREQ=DAILY;COUNT=2\nEXDATE:20240107T090000,20231231T090000"
    auto rule = recurrence.rrulestr(text)
    auto expected = [3, 4, 5, 9]
    auto n = 0
    for value in rule:
        assert value.year == 2024 and value.month == 1 and value.hour == 9
        assert value.day == expected[n]
        n += 1
    assert n == 4

    auto none = recurrence.rrulestr(
        "DTSTART:20240101T090000\nRRULE:FREQ=DAILY;COUNT=2\nEXRULE:FREQ=DAILY;COUNT=2",
    )
    assert none.count() == 0

@test
def rrulestr_local_tzid_and_utc_cutoff():
    auto text = "DTSTART;TZID=\"America/New_York\":20240309T090000\r\n"
    text += "RRULE:FREQ=DAILY;UNTIL=20240312T130000Z\r\n"
    text += "EXDATE:20240310T130000Z\r\nRDATE;VALUE=DATE-TIME;TZID=America/New_York:20240308T090000\r\n"
    auto rule = recurrence.rrulestr(text)
    auto days = [8, 9, 11, 12]
    auto offsets = [-18000, -18000, -14400, -14400]
    auto n = 0
    for value in rule:
        assert value.is_aware and value.zone_id >= 0
        assert value.year == 2024 and value.month == 3 and value.hour == 9
        assert value.day == days[n] and value.offset == offsets[n]
        n += 1
    assert n == 4

    auto fold = recurrence.rrulestr(
        "RDATE;TZID=America/New_York:20241103T013000\nEXDATE:20241103T063000Z",
    )
    auto first = fold.after(parser.isoparse("2024-11-03T00:00:00Z")).unwrap()
    assert first.offset == -14400 and fold.count() == 1

@test
def rrulestr_unfolds_and_accepts_date_values():
    auto folded = recurrence.rrulestr(
        "DTSTART;VALUE=DATE:20240101\r\nRRULE:FREQ=DAILY;CO\r\n\tUNT=2\r\n" + "RDATE;VALUE=DATE:20240108,\r\n 20240109\r\nEXDATE;VALUE=DATE:20240101",
        unfold=True,
    )
    auto day = [2, 8, 9]
    auto n = 0
    for value in folded:
        assert value.day == day[n] and value.hour == 0 and not value.is_aware
        n += 1
    assert n == 3
    auto only = recurrence.rrulestr("RDATE:19000101,20000101\nEXDATE:19000101")
    assert only.count() == 1
    auto empty = recurrence.rrulestr("EXDATE:20240101")
    assert empty.count() == 0

def _reject_rrule_text(str text, bool unfold = False):
    bool caught = False
    try:
        recurrence.rrulestr(text, unfold=unfold)
    except parser.ParserError:
        caught = True
    assert caught, text

@test
def rrulestr_rejects_malformed_rules_and_properties():
    for text in ["", "\n\t", "DTSTART:20240229", "DTSTART:20240230\nRRULE:FREQ=DAILY", "DTSTART:20240229\nDTSTART:20240301\nRRULE:FREQ=DAILY", "RRULE:", "RRULE:COUNT=2", "RRULE:FREQ=", "RRULE:FREQ=DAILY=MONTHLY", "FREQ=FORTNIGHTLY", "RRULE:FREQ=DAILY;freq=MONTHLY", "RRULE:FREQ=DAILY;COUNT=1;COUNT=2", "RRULE:FREQ=DAILY;COUNT=2;", "RRULE:FREQ=DAILY;BOGUS=1", "RRULE;VALUE=TEXT:FREQ=DAILY", "X-RULE:FREQ=DAILY", "FREQ=DAILY\nFREQ=MONTHLY", "RDATE", "EXDATE:20240101,", "RDATE;VALUE=PERIOD:20240101T000000Z/20240101T010000Z", "RDATE;VALUE=DATE:20240101T090000", "RDATE;VALUE=DATE-TIME:20240101", "RDATE;TZID=America/New_York:20240101", "RDATE;TZID=America/New_York:20240101T090000Z", "RDATE;TZID=Invalid/Zone:20240101T090000", "RDATE;TZID=America/New_York;TZID=America/Chicago:20240101T090000", "RDATE;BAD=value:20240101", "RDATE:2024-01-01", "RDATE:20240101T240000", "RDATE:20240101T235960", "RDATE:20240101T090000+02:00", "RDATE:2024W011", "RRULE:FREQ=DAILY;CO\r\n UNT=2"]:
        _reject_rrule_text(text)
    _reject_rrule_text(None)
    _reject_rrule_text(" RRULE:FREQ=DAILY", unfold=True)

@test
def rrulestr_rejects_invalid_selector_combinations():
    for text in ["FREQ=DAILY;COUNT=-1", "FREQ=DAILY;INTERVAL=0", "FREQ=DAILY;COUNT=9223372036854775808", "FREQ=DAILY;INTERVAL=-9223372036854775809", "FREQ=DAILY;COUNT=٢", "FREQ=DAILY;COUNT=1;UNTIL=20240102", "FREQ=DAILY;BYDAY=-1MO", "FREQ=WEEKLY;WKST=1MO", "FREQ=WEEKLY;WKST=XX", "FREQ=WEEKLY;BYMONTHDAY=1", "FREQ=DAILY;BYYEARDAY=1", "FREQ=YEARLY;BYDAY=0MO", "FREQ=YEARLY;BYDAY=54MO", "FREQ=YEARLY;BYDAY=+MO", "FREQ=YEARLY;BYDAY=T", "FREQ=YEARLY;BYWEEKNO=1;BYDAY=-1MO", "FREQ=DAILY;BYSETPOS=1", "FREQ=DAILY;BYDAY=MO;BYSETPOS=0", "FREQ=DAILY;BYMONTH=0", "FREQ=DAILY;BYMONTH=1,,2", "FREQ=DAILY;BYHOUR=24", "FREQ=DAILY;BYMINUTE=60", "FREQ=DAILY;BYSECOND=60", "DTSTART;TZID=America/New_York:20240101T000000\nRRULE:FREQ=DAILY;UNTIL=20240103T000000"]:
        _reject_rrule_text(text)
