import datetime
import time
import datetime_utils.tz as tz
import datetime_utils.utils as utils

def _assert_midnight(DateTime dt):
    assert dt.hour == 0 and dt.minute == 0 and dt.second == 0 and dt.nanosecond == 0

def _assert_today_in_zone(TimeZone zone):
    auto before = datetime.to_date(datetime.astimezone(datetime.now(), zone))
    auto result = utils.today(tzinfo=zone)
    auto after = datetime.to_date(datetime.astimezone(datetime.now(), zone))
    auto day = datetime.to_date(result)
    assert day == before or day == after
    _assert_midnight(result)
    assert result.is_aware
    auto expected = datetime.resolve(zone, day.year, day.month, day.day, 0, 0, 0)
    assert datetime.isoformat(result) == datetime.isoformat(expected)
    assert result.zone_id == expected.zone_id

@test
def utilities_today_local_and_explicit_zones():
    auto before = datetime.date_today()
    auto omitted = utils.today()
    auto explicit = utils.today(tzinfo=None)
    auto after = datetime.date_today()
    for result in [omitted, explicit]:
        _assert_midnight(result)
        assert not result.is_aware
        auto day = datetime.to_date(result)
        assert day == before or day == after
    _assert_today_in_zone(tz.UTC)
    _assert_today_in_zone(tz.gettz("America/New_York"))
    _assert_today_in_zone(tz.gettz("Pacific/Kiritimati"))
    _assert_today_in_zone(tz.tzoffset("west", -43200))

@test
def utilities_default_tzinfo_preserves_wall_clock_and_precision():
    auto naive = datetime.parse("2014-01-01T12:30:00.123456789")
    auto est = tz.tzoffset("EST", -18000)
    auto fixed = utils.default_tzinfo(dt=naive, tzinfo=est)
    assert datetime.isoformat(fixed) == "2014-01-01T12:30:00.123456789-05:00"
    assert datetime.isoformat(utils.default_tzinfo(naive, None)) == datetime.isoformat(naive)
    assert not utils.default_tzinfo(naive, None).is_aware

    auto ny = tz.gettz("America/New_York")
    auto overlap = datetime.resolve(ny, 2024, 11, 3, 1, 30, 0, fold=1)
    auto preserved = utils.default_tzinfo(overlap, tz.UTC)
    assert datetime.equal(preserved, overlap)
    assert preserved.zone_id == overlap.zone_id and preserved.offset == -18000
    auto exact = datetime.rfc3339_parse("2014-01-01T12:30:00.000000001Z")
    assert datetime.isoformat(utils.default_tzinfo(exact, est)) == "2014-01-01T12:30:00.000000001+00:00"

    auto gap = utils.default_tzinfo(datetime.parse("2024-03-10T02:30:00.000000001"), ny)
    assert not tz.datetime_exists(gap)
    assert datetime.isoformat(gap) == "2024-03-10T02:30:00.000000001-05:00"

@test
def utilities_within_delta_inclusive_signed_and_subsecond():
    auto start = datetime.parse("1969-12-31T23:59:59.999999999")
    auto end = datetime.parse("1970-01-01T00:00:00.000000001")
    assert utils.within_delta(dt1=start, dt2=end, delta=time.nanos(2))
    assert utils.within_delta(end, start, time.nanos(2))
    assert utils.within_delta(start, end, time.nanos(-2))
    assert not utils.within_delta(start, end, time.nanos(1))
    assert not utils.within_delta(end, start, time.nanos(-1))
    assert not utils.within_delta(start, end, time.nanos(0))
    assert utils.within_delta(start, start, time.nanos(0))

@test
def utilities_within_delta_duration_boundaries():
    auto epoch = datetime.from_timestamp(0)
    auto whole = datetime.from_timestamp(9223372036)
    auto at_max = datetime.replace(whole, nanosecond=854775807)
    auto after_max = datetime.replace(whole, nanosecond=854775808)
    auto max_delta = time.nanos(9223372036854775807)
    auto min_delta = time.nanos(-9223372036854775807 - 1)
    assert utils.within_delta(epoch, at_max, max_delta)
    assert not utils.within_delta(epoch, after_max, max_delta)
    assert utils.within_delta(epoch, after_max, min_delta)
    assert utils.within_delta(after_max, epoch, min_delta)
    auto beyond = datetime.replace(whole, nanosecond=854775809)
    assert not utils.within_delta(epoch, beyond, min_delta)
    assert not utils.within_delta(datetime.parse("0001-01-01"), datetime.parse("9999-12-31"), min_delta)

@test
def utilities_within_delta_zone_comparison():
    auto ny = tz.gettz("America/New_York")
    auto spring_before = datetime.resolve(ny, 2024, 3, 9, 12, 0, 0)
    auto spring_after = datetime.resolve(ny, 2024, 3, 10, 12, 0, 0)
    assert not utils.within_delta(spring_before, spring_after, time.seconds(23 * 3600))
    assert utils.within_delta(spring_before, spring_after, time.seconds(86400))
    auto utc_after = datetime.astimezone(spring_after, tz.UTC)
    assert utils.within_delta(spring_before, utc_after, time.seconds(23 * 3600))
    assert not utils.within_delta(spring_before, utc_after, time.seconds(23 * 3600 - 1))

    auto early = datetime.resolve(ny, 2024, 11, 3, 1, 30, 0)
    auto late = datetime.resolve(ny, 2024, 11, 3, 1, 30, 0, fold=1)
    assert utils.within_delta(early, late, time.nanos(0))
    assert not utils.within_delta(early, datetime.astimezone(late, tz.UTC), time.nanos(0))

    bool mixed = False
    try:
        utils.within_delta(
            early,
            datetime.parse("2024-11-03T01:30:00"),
            time.seconds(86400),
        )
    except TypeError:
        mixed = True
    assert mixed
