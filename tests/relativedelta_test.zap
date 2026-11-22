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
