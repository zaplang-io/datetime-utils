import datetime
import datetime_utils.relativedelta as rd

@test
def relativedelta_calendar_arithmetic():
    auto january = datetime.parse("2024-01-31T12:34:56.123456789")
    assert datetime.isoformat(january + rd.RelativeDelta(months=1)) == "2024-02-29T12:34:56.123456789"
    assert datetime.isoformat(january + rd.RelativeDelta(years=1, months=1)) == "2025-02-28T12:34:56.123456789"
    assert datetime.isoformat(january - rd.RelativeDelta(months=1)) == "2023-12-31T12:34:56.123456789"
    assert datetime.equal(january + rd.RelativeDelta(), january)

    auto year = rd.RelativeDelta(years=1)
    auto quarter = rd.RelativeDelta(months=3)
    auto combined = year + quarter
    assert combined.years == 1 and combined.months == 3
    assert datetime.isoformat(january + combined) == "2025-04-30T12:34:56.123456789"
    assert datetime.equal(january + -combined, january - combined)
    assert datetime.equal(january + quarter * 4, january + year)
    assert datetime.equal(january + quarter * -4, january - year)
    assert datetime.equal(january + quarter * 0, january)

    auto lower = datetime.parse("0001-01-01T00:00:00")
    auto upper = datetime.parse("9999-12-31T00:00:00")
    assert datetime.isoformat(lower + rd.RelativeDelta(years=9998, months=11)) == "9999-12-01T00:00:00"
    assert datetime.isoformat(upper - rd.RelativeDelta(years=9998, months=11)) == "0001-01-31T00:00:00"
    auto fixed = datetime.rfc3339_parse("2024-03-31T03:15:00+05:30")
    assert datetime.isoformat(fixed + rd.RelativeDelta(months=1)) == "2024-04-30T03:15:00+05:30"

@test
def relativedelta_dst_transitions():
    auto ny = datetime.zone("America/New_York")
    auto winter = datetime.resolve(ny, 2024, 2, 10, 12, 15, 0)
    auto noon = winter + rd.RelativeDelta(months=1)
    assert datetime.isoformat(noon) == "2024-03-10T12:15:00-04:00"
    assert datetime.equal(noon - rd.RelativeDelta(months=1), winter)
    auto early = datetime.resolve(ny, 2024, 2, 10, 2, 30, 0)
    auto gap = early + rd.RelativeDelta(months=1)
    assert datetime.is_imaginary(gap)
    assert datetime.isoformat(gap) == "2024-03-10T02:30:00-05:00"
    auto october = datetime.resolve(ny, 2024, 10, 3, 1, 30, 0)
    auto fold = october + rd.RelativeDelta(months=1)
    assert datetime.is_ambiguous(fold)
    assert datetime.isoformat(fold) == "2024-11-03T01:30:00-04:00"

def _check_range(DateTime from_dt, rd.RelativeDelta shift):
    bool caught = False
    try:
        auto result = from_dt + shift
    except ValueError:
        caught = True
    assert caught

@test
def relativedelta_typed_range_and_overflow_errors():
    auto start = datetime.parse("2000-01-01")
    _check_range(start, rd.RelativeDelta(years=9223372036854775807, months=12))
    _check_range(start, rd.RelativeDelta(months=-9223372036854775807 - 1))
    _check_range(datetime.parse("0001-01-01"), rd.RelativeDelta(months=-1))
    _check_range(datetime.parse("9999-12-31"), rd.RelativeDelta(months=1))
    auto largest = rd.RelativeDelta(years=9223372036854775807)
    auto smallest = rd.RelativeDelta(years=-9223372036854775807 - 1)
    auto unit = rd.RelativeDelta(years=1)
    auto negative = rd.RelativeDelta(years=-1)
    assert (unit * smallest.years).years == smallest.years
    assert (negative * largest.years).years == -largest.years
    assert (rd.RelativeDelta(years=-4611686018427387904) * 2).years == smallest.years
    assert (rd.RelativeDelta(years=-3074457345618258602) * 3).years == -9223372036854775806
    bool caught = False
    try:
        auto result = largest + unit
    except ValueError:
        caught = True
    assert caught
    caught = False
    try:
        auto result = -smallest
    except ValueError:
        caught = True
    assert caught
    caught = False
    try:
        auto result = rd.RelativeDelta(years=-3074457345618258603) * 3
    except ValueError:
        caught = True
    assert caught

def _month_length(list[str] lengths, int64 year, int64 month) -> int64:
    auto row = lengths[year - 1696]
    return 28 + "0123".find(row[month - 1:month])

def _assert_date(
    DateTime actual,
    list[str] lengths,
    int64 year,
    int64 month,
    int64 day,
    str context,
):
    auto expected_day = _month_length(lengths, year, month)
    if day < expected_day:
        expected_day = day
    assert actual.year == year and actual.month == month and actual.day == expected_day, context

@test
def relativedelta_full_gregorian_cycle():
    # Each row encodes the twelve Python calendar month lengths for one year.
    auto lengths = fs.read_file("tests/data/gregorian-month-lengths.txt").strip().split(
        "\n",
    )
    assert len(lengths) == 408
    for row in lengths:
        assert len(row) == 12
        for index in range(12):
            assert "0123".find(row[index:index + 1]) >= 0
    auto checked = 0
    for year in range(1700, 2100):
        for month in range(1, 13):
            auto previous_year = year
            auto previous_month = month - 1
            if month == 1:
                previous_month = 12
                previous_year = year - 1
            auto next_year = year
            auto next_month = month + 1
            if month == 12:
                next_month = 1
                next_year = year + 1
            for day in range(28, _month_length(lengths, year, month) + 1):
                auto start = datetime.combine(
                    datetime.date(year, month, day),
                    datetime.time(0, 0, 0),
                )
                auto context = f"RelativeDelta from {year}-{month}-{day}"
                _assert_date(
                    start + rd.RelativeDelta(months=-13),
                    lengths,
                    previous_year - 1,
                    previous_month,
                    day,
                    context + ", -13 months",
                )
                _assert_date(
                    start + rd.RelativeDelta(months=-1),
                    lengths,
                    previous_year,
                    previous_month,
                    day,
                    context + ", -1 month",
                )
                _assert_date(
                    start + rd.RelativeDelta(months=1),
                    lengths,
                    next_year,
                    next_month,
                    day,
                    context + ", +1 month",
                )
                _assert_date(
                    start + rd.RelativeDelta(months=13),
                    lengths,
                    next_year + 1,
                    next_month,
                    day,
                    context + ", +13 months",
                )
                for shift in [-4, -1, 1, 4]:
                    _assert_date(
                        start + rd.RelativeDelta(years=shift),
                        lengths,
                        year + shift,
                        month,
                        day,
                        context + f", {shift} years",
                    )
                checked = checked + 8
    assert checked == 131976

@test
def relativedelta_weekday_matrix():
    auto rows = fs.read_file("tests/data/relativedelta-weekdays.txt").strip().split(
        "\n",
    )
    assert len(rows) == 49
    auto selectors = [rd.MO, rd.TU, rd.WE, rd.TH, rd.FR, rd.SA, rd.SU]
    for start_day in range(7):
        auto start = datetime.combine(
            datetime.date(2024, 12, 23 + start_day),
            datetime.time(12, 34, 56),
        )
        for weekday in range(7):
            auto token = selectors[weekday]
            assert token.weekday == weekday
            auto row = rows[start_day * 7 + weekday].split(" ")
            assert len(row) == 9
            auto bare = start + rd.RelativeDelta(weekday=token)
            assert datetime.isoformat(bare) == row[5] + "T12:34:56"
            for n in range(-4, 5):
                auto actual = start + rd.RelativeDelta(weekday=token(n))
                assert datetime.isoformat(actual) == row[n + 4] + "T12:34:56", f"weekday {weekday}, start day {start_day}, occurrence {n}"

@test
def relativedelta_weekday_calendar_order_and_composition():
    auto january = datetime.parse("2024-01-31T12:15:00.123456789")
    auto next_monday = rd.RelativeDelta(weekday=rd.MO(1))
    auto last_friday = rd.RelativeDelta(weekday=rd.FR(-1))
    auto next_month = rd.RelativeDelta(months=1)
    assert datetime.isoformat(january + rd.RelativeDelta(months=1, weekday=rd.FR(-1))) == "2024-02-23T12:15:00.123456789"
    assert datetime.isoformat(january + (next_monday + next_month)) == "2024-03-04T12:15:00.123456789"
    assert datetime.equal(january + (next_monday + last_friday), january + last_friday)
    assert datetime.equal(january + -last_friday, january + last_friday)
    assert datetime.equal(january + last_friday * 0, january + last_friday)
    assert datetime.equal(january + last_friday * -2, january + last_friday)
    assert datetime.equal(january - last_friday, january + last_friday)
    assert datetime.isoformat(january - rd.RelativeDelta(months=1, weekday=rd.FR(-1))) == "2023-12-29T12:15:00.123456789"

@test
def relativedelta_weekday_zones():
    auto fixed = datetime.rfc3339_parse("2024-03-06T12:15:00.000001+05:30")
    assert datetime.isoformat(fixed + rd.RelativeDelta(weekday=rd.FR(2))) == "2024-03-15T12:15:00.000001+05:30"

    auto ny = datetime.zone("America/New_York")
    auto normal = datetime.resolve(ny, 2024, 3, 4, 12, 15, 0)
    assert datetime.isoformat(normal + rd.RelativeDelta(weekday=rd.SU)) == "2024-03-10T12:15:00-04:00"
    auto pre_gap = datetime.resolve(ny, 2024, 3, 4, 2, 30, 0)
    auto gap = pre_gap + rd.RelativeDelta(weekday=rd.SU)
    assert datetime.is_imaginary(gap)
    assert datetime.isoformat(gap) == "2024-03-10T02:30:00-05:00"
    auto pre_fold = datetime.resolve(ny, 2024, 10, 28, 1, 30, 0)
    auto fold = pre_fold + rd.RelativeDelta(weekday=rd.SU)
    assert datetime.is_ambiguous(fold)
    assert datetime.isoformat(fold) == "2024-11-03T01:30:00-04:00"

@test
def relativedelta_weekday_range_errors():
    auto first = datetime.parse("0001-01-01T00:00:00")
    auto last_monday = first + rd.RelativeDelta(weekday=rd.MO(521723))
    assert datetime.isoformat(last_monday) == "9999-12-27T00:00:00"
    assert datetime.equal(last_monday + rd.RelativeDelta(weekday=rd.MO(-521723)), first)
    _check_range(first, rd.RelativeDelta(weekday=rd.SU(-1)))
    _check_range(datetime.parse("9999-12-31"), rd.RelativeDelta(weekday=rd.MO))
    _check_range(first, rd.RelativeDelta(weekday=rd.MO(521724)))
    _check_range(first, rd.RelativeDelta(weekday=rd.MO(-9223372036854775807 - 1)))
    _check_range(first, rd.RelativeDelta(weekday=rd.Weekday(7, 1)))
    _check_range(first, rd.RelativeDelta(weekday=rd.Weekday(-1, 1)))

@test
def relativedelta_fractional_units_and_normalization():
    auto start = datetime.parse("2024-01-31T11:30:00")
    auto simple = rd.RelativeDelta(days=1.5, hours=2).normalized()
    assert simple.days == 1.0 and simple.hours == 14.0
    assert simple.minutes == 0.0 and simple.seconds == 0.0 and simple.microseconds == 0.0

    auto mixed = rd.RelativeDelta(
        weeks=1.5,
        days=-2.25,
        hours=0.5,
        minutes=15,
        seconds=0.75,
        microseconds=1.5,
    )
    auto normalized = mixed.normalized()
    assert normalized.weeks == 0.0 and normalized.days == 8.0
    assert normalized.hours == 6.0 and normalized.minutes == 45.0
    assert normalized.seconds == 0.0 and normalized.microseconds == 750002.0
    assert datetime.isoformat(start + mixed) == "2024-02-08T18:15:00.750002"
    assert datetime.equal(start + mixed, start + normalized)

    auto negative = rd.RelativeDelta(days=-1.5, hours=-2).normalized()
    assert negative.days == -1.0 and negative.hours == -14.0
    assert datetime.isoformat(start + negative) == "2024-01-29T21:30:00"
    auto cancelled = rd.RelativeDelta(minutes=90.5, seconds=-20.5, microseconds=500000).normalized()
    assert cancelled.hours == 1.0 and cancelled.minutes == 30.0 and cancelled.seconds == 10.0
    assert cancelled.microseconds == 0.0
    auto carried = rd.RelativeDelta(hours=49, seconds=61, microseconds=1250000).normalized()
    assert carried.days == 2.0 and carried.hours == 1.0 and carried.minutes == 1.0
    assert carried.seconds == 2.0 and carried.microseconds == 250000.0
    auto near_day = rd.RelativeDelta(days=0.99999999999999).normalized()
    assert near_day.days == 1.0 and near_day.hours == 0.0
    auto months = rd.RelativeDelta(years=2, months=-25).normalized()
    assert months.years == 0 and months.months == -1

@test
def relativedelta_microsecond_ties_and_nanoseconds():
    auto start = datetime.parse("2024-02-29T23:59:59.999999123")
    assert datetime.equal(start + rd.RelativeDelta(microseconds=0.5), start)
    assert datetime.equal(start + rd.RelativeDelta(microseconds=-0.5), start)
    assert datetime.isoformat(start + rd.RelativeDelta(microseconds=1.5)) == "2024-03-01T00:00:00.000001123"
    assert datetime.isoformat(start + rd.RelativeDelta(microseconds=2.5)) == "2024-03-01T00:00:00.000001123"
    assert datetime.isoformat(start + rd.RelativeDelta(microseconds=-1.5)) == "2024-02-29T23:59:59.999997123"
    assert datetime.equal(
        start - rd.RelativeDelta(microseconds=1.5),
        start + rd.RelativeDelta(microseconds=-1.5),
    )

@test
def relativedelta_leapdays_and_weekday_order():
    auto start = datetime.parse("2024-01-31T11:30:00")
    auto ordered = rd.RelativeDelta(
        months=1,
        weeks=1,
        days=2,
        hours=25,
        weekday=rd.FR(-1),
    )
    assert datetime.isoformat(start + ordered) == "2024-03-08T12:30:00"

    auto leap = rd.RelativeDelta(leapdays=1)
    assert datetime.equal(start + leap, start)
    auto february = datetime.parse("2024-02-29")
    assert datetime.equal(february + leap, february)
    auto march = datetime.parse("2024-03-01")
    assert datetime.isoformat(march + leap) == "2024-03-02T00:00:00"
    assert datetime.equal(march - leap, march + leap)
    assert datetime.equal(march + leap * 0, march + leap)
    assert datetime.isoformat(march + rd.RelativeDelta(leapdays=-1)) == "2024-02-29T00:00:00"
    assert datetime.isoformat(start + rd.RelativeDelta(months=2, leapdays=1)) == "2024-04-01T11:30:00"
    assert datetime.isoformat(start + rd.RelativeDelta(years=1, months=2, leapdays=1)) == "2025-03-31T11:30:00"
    auto combined = leap + rd.RelativeDelta(leapdays=-2, hours=4)
    assert datetime.isoformat(march + combined) == "2024-02-28T04:00:00"
    assert datetime.isoformat(march + (rd.RelativeDelta(weeks=1) + rd.RelativeDelta(days=-7, hours=4))) == "2024-03-01T04:00:00"
    assert datetime.isoformat(march + -rd.RelativeDelta(weeks=1, hours=3)) == "2024-02-22T21:00:00"
    assert datetime.isoformat(march + rd.RelativeDelta(hours=1.5) * 2) == "2024-03-01T03:00:00"

@test
def relativedelta_wall_time_and_wide_day_range():
    auto ny = datetime.zone("America/New_York")
    auto spring = datetime.resolve(ny, 2024, 3, 9, 1, 30, 0)
    auto gap = spring + rd.RelativeDelta(hours=25)
    assert datetime.is_imaginary(gap)
    assert datetime.isoformat(gap) == "2024-03-10T02:30:00-05:00"
    auto autumn = datetime.resolve(ny, 2024, 11, 2, 1, 30, 0)
    auto fold = autumn + rd.RelativeDelta(days=1)
    assert datetime.is_ambiguous(fold)
    assert datetime.isoformat(fold) == "2024-11-03T01:30:00-04:00"

    auto first = datetime.parse("0001-01-01")
    auto last = datetime.parse("9999-12-31")
    auto whole_calendar = rd.RelativeDelta(days=3652058)
    assert datetime.equal(first + whole_calendar, last)
    assert datetime.equal(last - whole_calendar, first)
    _check_range(first, rd.RelativeDelta(days=3652059))
    _check_range(last, rd.RelativeDelta(microseconds=86400000000))
    _check_range(first, rd.RelativeDelta(days=math.inf))
    _check_range(first, rd.RelativeDelta(seconds=math.nan))
    _check_range(first, rd.RelativeDelta(weeks=math.inf, days=-math.inf))

@test
def relativedelta_two_datetime_matrix():
    auto rows = fs.read_file("tests/data/relativedelta-difference.txt").strip().split(
        "\n",
    )
    assert len(rows) == 196
    for row in rows:
        auto fields = row.split("|")
        assert len(fields) == 3
        auto target = datetime.parse(fields[0])
        auto base = datetime.parse(fields[1])
        auto delta = rd.relativedelta(target, base)
        auto units = f"{delta.years},{delta.months},{int64(delta.days)},{int64(delta.hours)},{int64(delta.minutes)},{int64(delta.seconds)},{int64(delta.microseconds)}"
        assert units == fields[2], row
        assert datetime.equal(base + delta, target), row

@test
def relativedelta_two_datetime_named_zones():
    auto ny = datetime.zone("America/New_York")
    auto la = datetime.zone("America/Los_Angeles")
    auto spring = datetime.resolve(ny, 2024, 3, 9, 12, 0, 0)
    auto spring_target = datetime.resolve(ny, 2024, 3, 10, 12, 0, 0)
    auto spring_delta = rd.relativedelta(dt1=spring_target, dt2=spring)
    assert spring_delta.days == 1.0 and spring_delta.hours == 0.0
    assert datetime.equal(spring + spring_delta, spring_target)
    assert datetime.equal(
        spring_target + rd.relativedelta(spring, spring_target),
        spring,
    )

    auto fall = datetime.resolve(ny, 2024, 11, 2, 12, 0, 0)
    auto fall_target = datetime.resolve(ny, 2024, 11, 4, 12, 0, 0)
    auto fall_delta = rd.relativedelta(fall_target, fall)
    assert fall_delta.days == 2.0 and fall_delta.hours == 0.0
    assert datetime.equal(fall + fall_delta, fall_target)

    # Python subtracts instants across distinct timezone objects. Applying
    # that elapsed remainder in New York still uses wall-clock arithmetic.
    auto west = datetime.resolve(la, 2024, 3, 11, 12, 0, 0)
    auto cross_zone = rd.relativedelta(west, spring)
    assert cross_zone.days == 2.0 and cross_zone.hours == 2.0
    assert datetime.isoformat(spring + cross_zone) == "2024-03-11T14:00:00-04:00"

    auto early = datetime.resolve(ny, 2024, 11, 3, 1, 30, 0)
    auto late = datetime.resolve(ny, 2024, 11, 3, 1, 30, 0, fold=1)
    auto fold_delta = rd.relativedelta(late, early)
    assert fold_delta.years == 0 and fold_delta.months == 0
    assert fold_delta.days == 0.0 and fold_delta.hours == 0.0
    assert datetime.equal(early + fold_delta, early)

@test
def relativedelta_two_datetime_fixed_offsets_and_nanoseconds():
    auto base = datetime.rfc3339_parse("2024-01-31T12:00:00-03:00")
    auto target = datetime.rfc3339_parse("2024-02-28T10:00:00+02:00")
    auto delta = rd.relativedelta(target, base)
    assert delta.months == 0 and delta.days == 27.0 and delta.hours == 17.0
    assert datetime.equal(base + delta, target)
    assert datetime.isoformat(base + delta) == "2024-02-28T05:00:00-03:00"

    auto precise_base = datetime.parse("2024-01-31T12:00:00.999999123")
    auto precise_target = datetime.parse("2024-02-29T12:00:01.000001123")
    auto precise = rd.relativedelta(precise_target, precise_base)
    assert precise.months == 1 and precise.microseconds == 2.0
    assert datetime.equal(precise_base + precise, precise_target)

@test
def relativedelta_two_datetime_typed_errors():
    auto naive = datetime.parse("2024-01-01")
    auto aware = datetime.rfc3339_parse("2024-01-01T00:00:00Z")
    bool mixed = False
    try:
        rd.relativedelta(aware, naive)
    except TypeError:
        mixed = True
    assert mixed

    bool fractional = False
    try:
        rd.relativedelta(datetime.parse("2024-01-01T00:00:00.000000001"), naive)
    except ValueError as message:
        fractional = message == "RelativeDelta difference must be a whole number of microseconds"
    assert fractional

    bool invalid = False
    try:
        rd.relativedelta(
            datetime.combine(datetime.date(2023, 2, 29), datetime.time(0, 0, 0)),
            naive,
        )
    except ValueError:
        invalid = True
    assert invalid

@test
def relativedelta_absolute_calendar_and_weekday():
    auto monday = datetime.parse("2018-04-09T13:37:00")
    assert datetime.isoformat(monday + rd.RelativeDelta(day=1, hours=25, weekday=rd.MO(1))) == "2018-04-02T14:37:00"
    auto summer = datetime.parse("2024-06-15T17:20:11.123456")
    auto combined = rd.RelativeDelta(
        year=2023,
        years=1,
        month=1,
        months=1,
        day=31,
        hour=0,
        minute=0,
        second=0,
        microsecond=0,
    )
    assert datetime.isoformat(summer + combined) == "2024-02-29T00:00:00"
    assert datetime.isoformat(summer + rd.RelativeDelta(year=2023, month=3, day=31, months=-1)) == "2023-02-28T17:20:11.123456"
    assert datetime.isoformat(summer + rd.RelativeDelta(month=1, day=100, months=1, weekday=rd.FR(-1))) == "2024-02-23T17:20:11.123456"
    auto leap_sample = datetime.parse("2024-01-31T12:34:56.123456")
    assert datetime.isoformat(leap_sample + rd.RelativeDelta(year=1900, month=2, day=29)) == "1900-02-28T12:34:56.123456"
    assert datetime.isoformat(leap_sample + rd.RelativeDelta(year=2000, month=2, day=29)) == "2000-02-29T12:34:56.123456"
    assert datetime.equal(
        leap_sample + rd.RelativeDelta(year=0, month=0, day=0),
        leap_sample,
    )

@test
def relativedelta_absolute_clock_precision_and_none():
    auto start = datetime.parse("2024-01-31T12:34:56.123456789")
    auto absent = rd.RelativeDelta()
    auto explicit = rd.RelativeDelta(
        year=None,
        month=None,
        day=None,
        hour=None,
        minute=None,
        second=None,
        microsecond=None,
    )
    assert absent.day.is_none() and absent.hour.is_none()
    assert explicit.day.is_none() and explicit.microsecond.is_none()
    assert datetime.equal(start + explicit, start)
    assert datetime.isoformat(start + rd.RelativeDelta(hour=0, minute=0, second=0, microsecond=1, microseconds=2)) == "2024-01-31T00:00:00.000003"
    assert datetime.isoformat(start + rd.RelativeDelta(second=0)) == "2024-01-31T12:34:00.123456789"
    assert datetime.isoformat(start + rd.RelativeDelta(microsecond=0)) == "2024-01-31T12:34:56"

    auto ny = datetime.zone("America/New_York")
    auto before = datetime.resolve(ny, 2024, 3, 9, 12, 15, 0)
    auto gap = before + rd.RelativeDelta(day=10, hour=2, minute=30)
    assert datetime.is_imaginary(gap)
    assert datetime.isoformat(gap) == "2024-03-10T02:30:00-05:00"
    auto fixed = datetime.rfc3339_parse("2024-01-31T12:00:00.123456789+05:30")
    assert datetime.isoformat(fixed + rd.RelativeDelta(month=2, hour=0)) == "2024-02-29T00:00:00.123456789+05:30"

@test
def relativedelta_absolute_composition():
    auto original = rd.RelativeDelta(day=5, hour=7, days=1.5, microsecond=5)
    auto replacement = rd.RelativeDelta(day=None, hour=0, minute=6, microsecond=0)
    auto combined = original + replacement
    assert combined.day.unwrap() == 5 and combined.hour.unwrap() == 0
    assert combined.minute.unwrap() == 6 and combined.microsecond.unwrap() == 0
    auto normalized = combined.normalized()
    assert normalized.day.unwrap() == 5 and normalized.hour.unwrap() == 0
    assert normalized.days == 1.0 and normalized.hours == 12.0
    auto inverted = -combined
    assert inverted.days == -1.5 and inverted.day.unwrap() == 5
    auto scaled = combined * 0
    assert scaled.days == 0.0 and scaled.day.unwrap() == 5 and scaled.hour.unwrap() == 0
    assert original.day.unwrap() == 5 and original.hour.unwrap() == 7
    assert combined.days == 1.5
    auto start = datetime.parse("2024-01-31T08:30:00.123456789")
    assert datetime.isoformat(start + scaled) == "2024-01-05T00:06:00"
    assert datetime.isoformat(start - combined) == "2024-01-03T12:06:00"

@test
def relativedelta_absolute_field_errors():
    auto start = datetime.parse("2024-01-01")
    _check_range(start, rd.RelativeDelta(year=-1))
    _check_range(start, rd.RelativeDelta(year=10000))
    _check_range(start, rd.RelativeDelta(month=13))
    _check_range(start, rd.RelativeDelta(day=-1))
    _check_range(start, rd.RelativeDelta(hour=-1))
    _check_range(start, rd.RelativeDelta(hour=24))
    _check_range(start, rd.RelativeDelta(minute=-1))
    _check_range(start, rd.RelativeDelta(minute=60))
    _check_range(start, rd.RelativeDelta(second=-1))
    _check_range(start, rd.RelativeDelta(second=60))
    _check_range(start, rd.RelativeDelta(microsecond=-1))
    _check_range(start, rd.RelativeDelta(microsecond=1000000))
