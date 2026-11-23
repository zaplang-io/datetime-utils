"Convenience functions for core DateTime and TimeZone values."

import datetime

const int64 _NANOS_PER_SECOND = 1000000000
const int64 _MAX_INT64 = 9223372036854775807

def today(Optional[TimeZone] tzinfo = None) -> DateTime:
    "Return midnight today in the given zone, or naive local midnight."
    if tzinfo.is_none():
        return datetime.combine(datetime.date_today(), datetime.time(0, 0, 0))
    auto zone = tzinfo.unwrap()
    auto now = datetime.astimezone(datetime.now(), zone)
    return datetime.resolve(zone, now.year, now.month, now.day, 0, 0, 0)

def default_tzinfo(DateTime dt, Optional[TimeZone] tzinfo) -> DateTime:
    "Attach the given zone to a naive datetime while preserving its wall time."
    if dt.is_aware or tzinfo.is_none():
        return dt
    auto localized = datetime.resolve(
        tzinfo.unwrap(),
        dt.year,
        dt.month,
        dt.day,
        dt.hour,
        dt.minute,
        dt.second,
    )
    return datetime.replace(localized, nanosecond=dt.nanosecond)

def within_delta(DateTime dt1, DateTime dt2, Duration delta) -> bool:
    """Return whether two datetimes differ by at most the magnitude of delta.

    Use wall-clock difference in a shared named zone, and elapsed time across
    zones. Mixed naive and aware values raise TypeError.
    """
    if dt1.is_aware != dt2.is_aware:
        raise TypeError("within_delta cannot mix naive and aware datetimes")

    auto later = datetime.to_timestamp(dt1)
    auto earlier = datetime.to_timestamp(dt2)
    if dt1.is_aware and dt1.zone_id >= 0 and dt1.zone_id == dt2.zone_id:
        later = later + dt1.offset
        earlier = earlier + dt2.offset

    auto nanos = dt1.nanosecond - dt2.nanosecond
    if later < earlier or later == earlier and nanos < 0:
        auto first = later
        later = earlier
        earlier = first
        nanos = -nanos

    # Compare seconds and nanoseconds separately to cover dates farther apart
    # than Duration can represent.
    if earlier < 0 and later > _MAX_INT64 + earlier:
        return False
    auto seconds = later - earlier
    if nanos < 0:
        seconds = seconds - 1
        nanos = nanos + _NANOS_PER_SECOND

    auto limit_seconds = delta.nanos // _NANOS_PER_SECOND
    auto limit_nanos = delta.nanos % _NANOS_PER_SECOND
    if delta.nanos < 0:
        # Avoid taking abs(INT64_MIN).
        limit_seconds = -limit_seconds
        if limit_nanos != 0:
            limit_seconds = limit_seconds - 1
            limit_nanos = _NANOS_PER_SECOND - limit_nanos
    return seconds < limit_seconds or seconds == limit_seconds and nanos <= limit_nanos
