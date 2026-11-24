import datetime

def _probe_resolver(Optional[str] name, Optional[int64] offset) -> Optional[TimeZone]:
    if name.is_some() and name.unwrap() == "EST" and offset.is_none():
        return datetime.zone("America/New_York")
    return None

def _probe_callback(
    Optional[fn(Optional[str], Optional[int64]) -> Optional[TimeZone]] source,
) -> (Optional[TimeZone], bool):
    Optional[str] name = None
    str abbreviation = "EST"
    name = abbreviation
    Optional[int64] seconds = None
    auto resolver = source.unwrap()
    return (resolver(name, seconds), True)

@test
def optional_timezone_callback_probe():
    auto zone, called = _probe_callback(_probe_resolver)
    assert called and zone.is_some()
    auto selected = zone.unwrap()
    assert selected.name == "America/New_York"
    auto early = datetime.resolve(selected, 2024, 11, 3, 1, 30, 0, nanosecond=123456789)
    assert datetime.is_ambiguous(early)
    assert datetime.zone_abbreviation(early).unwrap() == "EDT"
    auto late = datetime.resolve(
        selected,
        2024,
        11,
        3,
        1,
        30,
        0,
        fold=1,
        nanosecond=123456789,
    )
    assert datetime.zone_abbreviation(late).unwrap() == "EST"
    assert late.nanosecond == 123456789
