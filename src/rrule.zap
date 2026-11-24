"Lazy calendar recurrence rules over core DateTime values."

import datetime

const int64 YEARLY = 0
const int64 MONTHLY = 1
const int64 WEEKLY = 2
const int64 DAILY = 3
const int64 HOURLY = 4
const int64 MINUTELY = 5
const int64 SECONDLY = 6

# The last whole second in year 9999 on the naive Unix timeline.
const int64 _LAST_SECOND = 253402300799
const int64 _LAST_MONTH = 9999 * 12 - 1

def _local_start() -> Optional[DateTime]:
    auto local = datetime.now_local()
    return datetime.from_timestamp(datetime.to_timestamp(local) + local.offset)

def _month_length(int64 year, int64 month) -> int64:
    if month == 2:
        if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0):
            return 29
        return 28
    if month == 4 or month == 6 or month == 9 or month == 11:
        return 30
    return 31

def _query_compare(DateTime left, DateTime right) -> int64:
    if left.is_aware != right.is_aware:
        raise TypeError("Recurrence queries cannot mix naive and aware datetimes")
    auto a = datetime.to_timestamp(left)
    auto b = datetime.to_timestamp(right)
    if left.is_aware and left.zone_id >= 0 and left.zone_id == right.zone_id:
        a += left.offset
        b += right.offset
    if a < b or a == b and left.nanosecond < right.nanosecond:
        return -1
    if a > b or a == b and left.nanosecond > right.nanosecond:
        return 1
    return 0

struct RRule:
    int64 freq
    Optional[DateTime] dtstart = _local_start()
    int64 interval = 1
    Optional[int64] count = None
    Optional[DateTime] until = None

    def __iter__(self) -> _RuleIterator:
        """Iterate from dtstart, skipping invalid dates and nonexistent local times.

        Count and the inclusive until bound are mutually exclusive. For an
        aware start, the bound must be UTC. Each iteration starts at dtstart.
        """
        if self.freq < YEARLY or self.freq > SECONDLY:
            raise ValueError("Invalid recurrence frequency")
        if self.interval < 1:
            raise ValueError("Recurrence interval must be positive")
        if self.count.is_some() and self.until.is_some():
            raise ValueError("Recurrence count and until are mutually exclusive")

        auto start = self.dtstart
        if start.is_none():
            start = _local_start()
        auto base = start.unwrap()
        if base.year < 1 or base.year > 9999:
            raise ValueError("Recurrence start year must be in 1..9999")
        auto remaining = -1
        if self.count.is_some():
            remaining = self.count.unwrap()
            if remaining < 0:
                raise ValueError("Recurrence count must be nonnegative")
        if self.until.is_some():
            auto cutoff = self.until.unwrap()
            if cutoff.is_aware != base.is_aware or cutoff.is_aware and cutoff.offset != 0:
                raise ValueError(
                    "Recurrence until must match start awareness and be UTC if aware",
                )

        auto calendar = self.freq <= MONTHLY
        auto period = datetime.to_timestamp(base) + base.offset
        auto end = _LAST_SECOND
        auto unit = 1
        if calendar:
            period = (base.year - 1) * 12 + base.month - 1
            end = _LAST_MONTH
            if self.freq == YEARLY:
                unit = 12
        else:
            unit = [604800, 86400, 3600, 60, 1][self.freq - WEEKLY]

        # An interval larger than the remaining range yields at most the anchor.
        auto step = end - period + 1
        if self.interval <= (end - period) // unit:
            step = self.interval * unit
        return _RuleIterator(base, self.until, remaining, calendar, period, end, step)

    def before(self, DateTime dt, bool inc = False) -> Optional[DateTime]:
        "Return the last occurrence before dt, including dt when inc is true."
        Optional[DateTime] last = None
        for occurrence in self:
            auto order = _query_compare(occurrence, dt)
            if order > 0 or order == 0 and not inc:
                break
            last = occurrence
        return last

    def after(self, DateTime dt, bool inc = False) -> Optional[DateTime]:
        "Return the first occurrence after dt, including dt when inc is true."
        for occurrence in self:
            auto order = _query_compare(occurrence, dt)
            if order > 0 or order == 0 and inc:
                return occurrence
        return None

    def between(
        self,
        DateTime after,
        DateTime before,
        bool inc = False,
        int64 count = 1,
    ) -> list[DateTime]:
        """Return all occurrences between the bounds in order.

        The inc flag includes both bounds. The legacy count argument is
        retained for compatibility with dateutil.
        """
        list[DateTime] matches = []
        for occurrence in self:
            auto upper = _query_compare(occurrence, before)
            if upper > 0 or upper == 0 and not inc:
                break
            auto lower = _query_compare(occurrence, after)
            if lower > 0 or lower == 0 and inc:
                matches.append(occurrence)
        return matches

    def count(self) -> int64:
        "Count emitted occurrences by traversing the rule from the start."
        auto total = 0
        for occurrence in self:
            total += 1
        return total

struct _RuleIterator:
    DateTime base
    Optional[DateTime] until
    int64 remaining
    bool calendar
    int64 period
    int64 end
    int64 step

    def __iter__(self) -> _RuleIterator:
        return self

    def __next__(self) -> DateTime:
        while self.remaining != 0 and self.period <= self.end:
            auto index = self.period
            self.period += self.step
            auto year = self.base.year
            auto month = self.base.month
            auto day = self.base.day
            auto hour = self.base.hour
            auto minute = self.base.minute
            auto second = self.base.second
            if self.calendar:
                year = index // 12 + 1
                month = index % 12 + 1
                if day > _month_length(year, month):
                    continue
            else:
                auto wall = datetime.from_timestamp(index)
                year = wall.year
                month = wall.month
                day = wall.day
                hour = wall.hour
                minute = wall.minute
                second = wall.second

            auto occurrence = datetime.replace(
                self.base,
                year=year,
                month=month,
                day=day,
                hour=hour,
                minute=minute,
                second=second,
                nanosecond=0,
            )
            if datetime.is_imaginary(occurrence):
                continue
            if self.until.is_some() and datetime.to_timestamp(occurrence) > datetime.to_timestamp(self.until.unwrap()):
                self.remaining = 0
                break
            if self.remaining > 0:
                self.remaining -= 1
            return occurrence
        raise StopIteration
