import datetime
import datetime_utils.easter as easter

def _check_invalid(int64 year, int64 method, str expected):
    bool caught = False
    try:
        easter.easter(year, method=method)
    except Exception as message:
        assert message == expected
        caught = True
    assert caught

def main():
    assert easter.EASTER_JULIAN == 1
    assert easter.EASTER_ORTHODOX == 2
    assert easter.EASTER_WESTERN == 3

    # Positional and named calls with the default method.
    assert datetime.isoformat(easter.easter(2024)) == "2024-03-31"
    assert datetime.isoformat(easter.easter(year=2025)) == "2025-04-20"
    assert datetime.isoformat(easter.easter(method=easter.EASTER_WESTERN, year=2025)) == "2025-04-20"

    # Verify rejection immediately outside each supported range and for
    # genuinely extreme inputs before any arithmetic can run.
    for year in [0, 326, 10000, 9223372036854775807]:
        _check_invalid(
            year,
            easter.EASTER_JULIAN,
            "ValueError: Julian Easter requires a year from 327 through 9999",
        )
    for method in [easter.EASTER_ORTHODOX, easter.EASTER_WESTERN]:
        for year in [1582, 4100, -9223372036854775807, 9223372036854775807]:
            _check_invalid(
                year,
                method,
                "ValueError: Gregorian Easter requires a year from 1583 through 4099",
            )
    for method in [-9223372036854775807, -1, 0, 4, 9223372036854775807]:
        _check_invalid(2024, method, "ValueError: invalid Easter method")

    # Each method's entire documented range, in method and then year order.
    for year in range(327, 10000):
        print(datetime.isoformat(easter.easter(year, method=easter.EASTER_JULIAN)))
    for year in range(1583, 4100):
        print(datetime.isoformat(easter.easter(year, method=easter.EASTER_ORTHODOX)))
    for year in range(1583, 4100):
        print(datetime.isoformat(easter.easter(year, method=easter.EASTER_WESTERN)))
