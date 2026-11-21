import datetime
import datetime_utils.tz as tz

def _check_gap(DateTime gap, str shifted):
    assert not tz.datetime_exists(gap)
    assert not tz.datetime_ambiguous(gap)
    auto resolved = tz.resolve_imaginary(gap)
    assert datetime.isoformat(resolved) == shifted
    assert tz.datetime_exists(resolved)
    assert not tz.datetime_ambiguous(resolved)
    assert datetime.equal(tz.resolve_imaginary(resolved), resolved)

def _check_fold(DateTime early, DateTime late, int64 separation):
    assert tz.datetime_exists(early)
    assert tz.datetime_exists(late)
    assert tz.datetime_ambiguous(early)
    assert tz.datetime_ambiguous(late)
    assert datetime.to_timestamp(late) - datetime.to_timestamp(early) == separation
    assert datetime.equal(tz.resolve_imaginary(early), early)

def _check_naive(DateTime naive):
    bool exists_raised = False
    try:
        tz.datetime_exists(naive)
    except Exception as message:
        assert message == "ValueError: Datetime is naive and no time zone provided."
        exists_raised = True
    assert exists_raised
    bool ambiguous_raised = False
    try:
        tz.datetime_ambiguous(naive, tz=None)
    except Exception as message:
        assert message == "ValueError: Datetime is naive and no time zone provided."
        ambiguous_raised = True
    assert ambiguous_raised
    assert not tz.resolve_imaginary(naive).is_aware
    assert datetime.isoformat(tz.resolve_imaginary(naive)) == datetime.isoformat(naive)

def _check_local_zone():
    # The test runner sets TZ to America/New_York.
    for zone in [tz.tzlocal(), tz.gettz(), tz.gettz(None), tz.gettz(name=""), tz.gettz("US/Eastern")]:
        auto winter = datetime.astimezone(
            datetime.rfc3339_parse("2024-01-15T12:00:00Z"),
            zone,
        )
        auto summer = datetime.astimezone(
            datetime.rfc3339_parse("2024-07-15T12:00:00Z"),
            zone,
        )
        assert winter.offset == -18000
        assert summer.offset == -14400
        assert not tz.datetime_exists(datetime.resolve(zone, 2024, 3, 10, 2, 30, 0))
        assert tz.datetime_ambiguous(datetime.resolve(zone, 2024, 11, 3, 1, 30, 0))

def _check_named_zone():
    auto utc = tz.gettz(name="Etc/UTC")
    assert datetime.astimezone(datetime.from_timestamp(0), utc).offset == 0
    for name in ["No/Such_Zone", "america/new_york", "America/New_York\x00suffix", "\x00UTC"]:
        bool caught = False
        try:
            tz.gettz(name)
        except Exception as message:
            assert message.startswith("unknown time zone:")
            caught = True
        assert caught

def _check_fixed_offsets():
    auto utc = tz.tzutc()
    auto utc_constant = tz.UTC
    assert utc.name == "UTC" and utc.offset == 0 and utc.fixed
    assert utc_constant.name == "UTC" and utc_constant.offset == 0 and utc_constant.fixed
    auto epoch = datetime.from_timestamp(0)
    assert datetime.isoformat(datetime.astimezone(epoch, utc_constant)) == "1970-01-01T00:00:00+00:00"
    for offset in [-86399, -19800, -1, 0, 1, 19801, 86399]:
        auto fixed_zone = tz.tzoffset(name="test offset", offset=offset)
        assert fixed_zone.name == "test offset" and fixed_zone.fixed
        assert fixed_zone.offset == offset
        auto at_epoch = datetime.astimezone(epoch, fixed_zone)
        assert at_epoch.offset == offset
        assert datetime.to_timestamp(at_epoch) == 0
        assert tz.datetime_exists(at_epoch)
        assert not tz.datetime_ambiguous(at_epoch)
        assert datetime.equal(tz.resolve_imaginary(at_epoch), at_epoch)
    assert datetime.isoformat(datetime.astimezone(epoch, tz.tzoffset("", -1))) == "1969-12-31T23:59:59-00:00:01"
    assert datetime.isoformat(datetime.astimezone(epoch, tz.tzoffset("", 19801))) == "1970-01-01T05:30:01+05:30:01"
    for offset in [-9223372036854775807, -86400, 86400, 9223372036854775807]:
        bool caught = False
        try:
            tz.tzoffset("invalid", offset)
        except Exception as message:
            assert message == "ValueError: UTC offset must be less than 24 hours in magnitude"
            caught = True
        assert caught

def main():
    _check_local_zone()
    _check_fixed_offsets()
    _check_named_zone()
    auto ny = tz.gettz("America/New_York")
    auto lord_howe = tz.gettz("Australia/Lord_Howe")

    # Spring boundaries, including the last skipped and the first valid second.
    assert tz.datetime_exists(datetime.resolve(ny, 2024, 3, 10, 1, 59, 59))
    assert not tz.datetime_exists(datetime.resolve(ny, 2024, 3, 10, 2, 0, 0))
    assert not tz.datetime_exists(datetime.resolve(ny, 2024, 3, 10, 2, 59, 59))
    assert tz.datetime_exists(datetime.resolve(ny, 2024, 3, 10, 3, 0, 0))
    _check_gap(datetime.resolve(ny, 2024, 3, 10, 2, 30, 0), "2024-03-10T03:30:00-04:00")
    _check_gap(datetime.resolve(ny, 1965, 4, 25, 2, 30, 0), "1965-04-25T03:30:00-04:00")
    _check_gap(datetime.resolve(ny, 2099, 3, 8, 2, 30, 0), "2099-03-08T03:30:00-04:00")
    _check_gap(
        datetime.resolve(lord_howe, 2024, 10, 6, 2, 15, 0),
        "2024-10-06T02:45:00+11:00",
    )

    # Fall boundaries and both folds, also for a half-hour transition.
    assert not tz.datetime_ambiguous(datetime.resolve(ny, 2024, 11, 3, 0, 59, 59))
    assert tz.datetime_ambiguous(datetime.resolve(ny, 2024, 11, 3, 1, 0, 0))
    assert tz.datetime_ambiguous(datetime.resolve(ny, 2024, 11, 3, 1, 59, 59))
    assert not tz.datetime_ambiguous(datetime.resolve(ny, 2024, 11, 3, 2, 0, 0))
    auto ny_early = datetime.resolve(ny, 2024, 11, 3, 1, 30, 0)
    auto ny_late = datetime.resolve(ny, 2024, 11, 3, 1, 30, 0, fold=1)
    _check_fold(ny_early, ny_late, 3600)
    auto lh_early = datetime.resolve(lord_howe, 2024, 4, 7, 1, 45, 0)
    auto lh_late = datetime.resolve(lord_howe, 2024, 4, 7, 1, 45, 0, fold=1)
    _check_fold(lh_early, lh_late, 1800)

    # A UTC override supplies a zone for naive input and supersedes New York.
    auto spring = datetime.parse("2024-03-10T02:30:00")
    auto utc_override = Optional.Some(tz.tzutc())
    assert tz.datetime_exists(spring, tz=utc_override)
    assert not tz.datetime_ambiguous(spring, tz=utc_override)
    auto ny_gap = datetime.resolve(ny, 2024, 3, 10, 2, 30, 0)
    assert tz.datetime_exists(ny_gap, tz=utc_override)
    assert not tz.datetime_ambiguous(ny_early, tz=utc_override)
    assert not tz.datetime_exists(ny_gap, tz=None)
    assert tz.datetime_ambiguous(ny_early, tz=None)
    auto ny_override = Optional.Some(datetime.zone("America/New_York"))
    assert not tz.datetime_exists(spring, tz=ny_override)
    auto naive_fall = datetime.parse("2024-11-03T01:30:00")
    assert tz.datetime_exists(naive_fall, tz=ny_override)
    assert tz.datetime_ambiguous(naive_fall, tz=ny_override)
    _check_naive(spring)
    # A real later fold must retain its original instant and offset.
    assert datetime.equal(tz.resolve_imaginary(ny_late), ny_late)
    assert datetime.equal(tz.resolve_imaginary(lh_late), lh_late)
    print("Timezone tests passed")
