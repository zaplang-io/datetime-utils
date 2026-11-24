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

def _month_mask(list[int64] values) -> int64:
    auto mask = 0
    for value in values:
        if value < 1 or value > 12:
            raise ValueError("bymonth values must be in 1..12")
        mask |= 1 << value
    return mask

def _monthday_mask(list[int64] values) -> int64:
    auto mask = 0
    for value in values:
        if value == 0 or value < -31 or value > 31:
            raise ValueError("bymonthday values must be in -31..-1 or 1..31")
        auto bit = value
        if value < 0:
            bit = 31 - value
        mask |= 1 << bit
    return mask

def _allows_month(int64 months, int64 month) -> bool:
    return months == 0 or months & 1 << month != 0

def _allows_monthday(int64 monthdays, int64 day, int64 last) -> bool:
    return monthdays == 0 or monthdays & (1 << day | 1 << 32 + last - day) != 0

def _can_match_date(int64 months, int64 monthdays) -> bool:
    if monthdays == 0 or months == 0:
        return True
    for month in range(1, 13):
        if _allows_month(months, month):
            # Leap-year lengths give each month its largest possible day range.
            auto last = _month_length(2000, month)
            for day in range(1, last + 1):
                if _allows_monthday(monthdays, day, last):
                    return True
    return False

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
    Optional[list[int64]] bymonth = None
    Optional[list[int64]] bymonthday = None

    def __iter__(self) -> _RuleIterator:
        """Iterate from dtstart, skipping invalid dates and nonexistent local times.

        Count and the inclusive until bound are mutually exclusive. For an
        aware start, the bound must be UTC. Each iteration starts at dtstart.
        Month and signed month-day selectors are lists.
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
        auto yearly = self.freq == YEARLY
        auto period = datetime.to_timestamp(base) + base.offset
        auto end = _LAST_SECOND
        auto unit = 1
        if calendar:
            period = (base.year - 1) * 12 + base.month - 1
            end = _LAST_MONTH
            if yearly:
                period -= base.month - 1
                unit = 12
        else:
            unit = [604800, 86400, 3600, 60, 1][self.freq - WEEKLY]

        if self.until.is_some():
            auto cutoff = self.until.unwrap()
            auto last_wall = datetime.to_timestamp(cutoff)
            # Named or fixed offsets are less than a day in magnitude. Bound
            # the candidate search without rejecting valid zoned wall times.
            if base.is_aware:
                last_wall += 86400
            if last_wall < _LAST_SECOND:
                if calendar:
                    auto last_date = datetime.from_timestamp(last_wall)
                    end = (last_date.year - 1) * 12 + last_date.month - 1
                else:
                    end = last_wall

        auto months = 0
        auto monthdays = 0
        auto expand_days = self.bymonthday.is_some()
        if self.bymonth.is_some():
            months = _month_mask(self.bymonth.unwrap())
        elif yearly and not expand_days:
            months = 1 << base.month
        if expand_days:
            if self.freq == WEEKLY:
                raise ValueError("bymonthday is invalid for weekly recurrence")
            monthdays = _monthday_mask(self.bymonthday.unwrap())
        if not _can_match_date(months, monthdays):
            remaining = 0

        # An interval larger than the remaining range yields at most the anchor.
        auto step = end - period + 1
        if self.interval <= (end - period) // unit:
            step = self.interval * unit
        return _RuleIterator(
            base,
            self.until,
            remaining,
            calendar,
            yearly,
            period,
            end,
            step,
            months,
            monthdays,
            expand_days,
        )

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
    bool yearly
    int64 period
    int64 end
    int64 step
    int64 months
    int64 monthdays
    bool expand_days
    int64 month = 1
    int64 day = 1

    def __iter__(self) -> _RuleIterator:
        return self

    def _advance_month(self):
        self.day = 1
        if self.yearly and self.month < 12:
            self.month += 1
        else:
            self.month = 1
            self.period += self.step

    def _next_calendar(self) -> DateTime:
        while self.period <= self.end:
            auto year = self.period // 12 + 1
            auto month = self.period % 12 + 1
            if self.yearly:
                month = self.month
            if not _allows_month(self.months, month):
                self._advance_month()
                continue
            auto last = _month_length(year, month)
            auto day = self.base.day
            if self.expand_days:
                day = self.day
            if self.expand_days and day < last:
                self.day += 1
            else:
                self._advance_month()
            if day > last or not _allows_monthday(self.monthdays, day, last):
                continue
            if year == self.base.year:
                if month < self.base.month or month == self.base.month and day < self.base.day:
                    continue
            return datetime.replace(
                self.base,
                year=year,
                month=month,
                day=day,
                nanosecond=0,
            )
        raise StopIteration

    def _next_clock(self) -> DateTime:
        while self.period <= self.end:
            auto index = self.period
            auto wall = datetime.from_timestamp(index)
            if not _allows_month(self.months, wall.month) or not _allows_monthday(self.monthdays, wall.day, _month_length(wall.year, wall.month)):
                # Jump to the next candidate on or after midnight without
                # shifting the interval's phase.
                auto seconds_left = 86400 - wall.hour * 3600 - wall.minute * 60 - wall.second
                auto steps = (seconds_left - 1) // self.step + 1
                self.period += steps * self.step
                continue
            self.period += self.step
            return datetime.replace(
                self.base,
                year=wall.year,
                month=wall.month,
                day=wall.day,
                hour=wall.hour,
                minute=wall.minute,
                second=wall.second,
                nanosecond=0,
            )
        raise StopIteration

    def __next__(self) -> DateTime:
        while self.remaining != 0:
            DateTime occurrence = self.base
            if self.calendar:
                occurrence = self._next_calendar()
            else:
                occurrence = self._next_clock()
            if datetime.is_imaginary(occurrence):
                continue
            if self.until.is_some() and datetime.to_timestamp(occurrence) > datetime.to_timestamp(self.until.unwrap()):
                self.remaining = 0
                break
            if self.remaining > 0:
                self.remaining -= 1
            return occurrence
        raise StopIteration
