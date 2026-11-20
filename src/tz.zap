import datetime

const TimeZone UTC = TimeZone(name="UTC", offset=0, fixed=True)

def tzlocal() -> TimeZone:
    "Return the host's configured zone using core's IANA zone discovery."
    return datetime.local_zone()

def tzutc() -> TimeZone:
    "Return the UTC time zone."
    return UTC

def tzoffset(str name, int64 offset) -> TimeZone:
    """Return a named fixed offset in seconds east of UTC.

    Offsets must be strictly between -86400 and 86400 seconds.
    """
    if offset <= -86400 or offset >= 86400:
        raise "ValueError: UTC offset must be less than 24 hours in magnitude"
    return TimeZone(name=name, offset=offset, fixed=True)

def _wall_time(DateTime dt, Optional[TimeZone] tz) -> DateTime:
    if tz.is_some():
        return datetime.resolve(
            tz.unwrap(),
            dt.year,
            dt.month,
            dt.day,
            dt.hour,
            dt.minute,
            dt.second,
        )
    if not dt.is_aware:
        raise "ValueError: Datetime is naive and no time zone provided."
    return dt

def datetime_exists(DateTime dt, Optional[TimeZone] tz = None) -> bool:
    """Return whether the wall time exists in its own zone or the supplied zone.

    Passing a zone reinterprets the wall-clock fields in that zone. A naive
    datetime requires an explicit zone.
    """
    return not datetime.is_imaginary(_wall_time(dt, tz))

def datetime_ambiguous(DateTime dt, Optional[TimeZone] tz = None) -> bool:
    """Return whether the wall time occurs twice in its own or the supplied zone.

    Passing a zone reinterprets the wall-clock fields in that zone. A naive
    datetime requires an explicit zone.
    """
    return datetime.is_ambiguous(_wall_time(dt, tz))

def resolve_imaginary(DateTime dt) -> DateTime:
    """Advance a nonexistent wall time by its zone's transition offset change.

    Return existing and naive times unchanged.
    """
    return datetime.resolve_imaginary(dt)
