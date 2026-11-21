import datetime
import datetime_utils.relativedelta as rd

def _check_calendar():
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

def _check_dst():
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

def _check_overflow():
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

def main():
    _check_calendar()
    _check_dst()
    _check_overflow()

    # A full 400-year Gregorian cycle at every possible month-end day.
    for year in range(1700, 2100):
        for month in range(1, 13):
            for day in range(28, 32):
                auto next = datetime.add(
                    datetime.combine(
                        datetime.date(year, month, 1),
                        datetime.time(0, 0, 0),
                    ),
                    time.seconds(86400 * (day - 1)),
                )
                if next.month == month:
                    for shift in [-13, -1, 1, 13]:
                        print(datetime.isoformat(next + rd.RelativeDelta(months=shift)))
                    for shift in [-4, -1, 1, 4]:
                        print(datetime.isoformat(next + rd.RelativeDelta(years=shift)))
