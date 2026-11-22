import datetime
import datetime_utils.easter as easter

def _check_invalid(int64 year, int64 method, str expected):
    bool caught = False
    try:
        easter.easter(year, method=method)
    except ValueError as message:
        assert message == expected
        caught = True
    assert caught

@test
def easter_default_and_method_constants():
    assert easter.EASTER_JULIAN == 1
    assert easter.EASTER_ORTHODOX == 2
    assert easter.EASTER_WESTERN == 3

    # Positional and named calls with the default method.
    assert datetime.isoformat(easter.easter(2024)) == "2024-03-31"
    assert datetime.isoformat(easter.easter(year=2025)) == "2025-04-20"
    assert datetime.isoformat(easter.easter(method=easter.EASTER_WESTERN, year=2025)) == "2025-04-20"

@test
def easter_rejects_invalid_inputs():
    # Verify rejection immediately outside each supported range and for
    # genuinely extreme inputs before any arithmetic can run.
    for year in [0, 326, 10000, 9223372036854775807]:
        _check_invalid(
            year,
            easter.EASTER_JULIAN,
            "Julian Easter requires a year from 327 through 9999",
        )
    for method in [easter.EASTER_ORTHODOX, easter.EASTER_WESTERN]:
        for year in [1582, 4100, -9223372036854775807, 9223372036854775807]:
            _check_invalid(
                year,
                method,
                "Gregorian Easter requires a year from 1583 through 4099",
            )
    for method in [-9223372036854775807, -1, 0, 4, 9223372036854775807]:
        _check_invalid(2024, method, "invalid Easter method")

def _check_easter_range(int64 method, int64 first_year, int64 last_year):
    # Each section contains consecutive years, four ASCII digits (MMDD) each.
    auto sections = fs.read_file("tests/data/easter-mmdd.txt").split("\n\n")
    assert len(sections) == 3
    auto dates = sections[method - 1].replace("\n", "")
    assert len(dates) == 4 * (last_year - first_year + 1)
    for year in range(first_year, last_year + 1):
        auto date = easter.easter(year, method=method)
        auto actual = datetime.isoformat(date)
        auto offset = 4 * (year - first_year)
        auto expected = dates[offset:offset + 4]
        assert actual[5:7] == expected[:2] and actual[8:10] == expected[2:], f"Easter method {method}, year {year}"
        assert date.year == year, f"Easter year {year}"

@test
def easter_julian_full_range():
    _check_easter_range(easter.EASTER_JULIAN, 327, 9999)

@test
def easter_orthodox_full_range():
    _check_easter_range(easter.EASTER_ORTHODOX, 1583, 4099)

@test
def easter_western_full_range():
    _check_easter_range(easter.EASTER_WESTERN, 1583, 4099)
