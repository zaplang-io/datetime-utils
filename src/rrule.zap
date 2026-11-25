"Lazy calendar recurrence rules over core DateTime values."

import datetime
import easter as computus
import math
import relativedelta as relative

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
const int64 _FIRST_CIVIL_DAY = -719162
const int64 _LAST_CIVIL_DAY = _LAST_SECOND // 86400
const int64 _FIRST_EASTER_YEAR = 1583
const int64 _LAST_EASTER_YEAR = 4099

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

def _year_length(int64 year) -> int64:
    return 337 + _month_length(year, 2)

def _day_number(Date day) -> int64:
    return datetime.to_timestamp(datetime.combine(day, datetime.time(0, 0, 0))) // 86400

def _signed_selector_set(list[int64] values, int64 limit, str name) -> set[int64]:
    set[int64] days = set[int64]()
    for value in values:
        if value == 0 or value < -limit or value > limit:
            raise ValueError(
                name + " values must be in -" + str(limit) + "..-1 or 1.." + str(limit),
            )
        days.add(value)
    return days

value struct _SetPositions:
    set[int64] requested
    int64 leading
    int64 trailing

def _set_positions(Optional[list[int64]] values) -> _SetPositions:
    set[int64] requested = set[int64]()
    auto leading = 0
    auto trailing = 0
    if values.is_some():
        requested = _signed_selector_set(values.unwrap(), 366, "bysetpos")
        for position in requested:
            if position > leading:
                leading = position
            elif -position > trailing:
                trailing = -position
    return _SetPositions(requested, leading, trailing)

def _week_one(int64 january_weekday, int64 week_start) -> int64:
    # January 4 is always in week one. Return that week's start relative to Jan 1.
    return 3 - (january_weekday + 3 - week_start) % 7

def _allows_week_number(
    set[int64] numbers,
    Date date,
    int64 ordinal,
    int64 week_start,
) -> bool:
    auto day = ordinal - 1
    auto january = (datetime.date_weekday(date) - day) % 7
    auto length = _year_length(date.year)
    auto first = _week_one(january, week_start)
    auto next_january = (january + length) % 7
    auto next = length + _week_one(next_january, week_start)
    auto week = (day - first) // 7 + 1
    auto weeks = (next - first) // 7
    if day < first:
        auto previous_length = _year_length(date.year - 1)
        auto previous_january = (january - previous_length) % 7
        auto previous = _week_one(previous_january, week_start) - previous_length
        weeks = (first - previous) // 7
        week = weeks
    elif day >= next:
        auto next_length = _year_length(date.year + 1)
        auto following_january = (next_january + next_length) % 7
        auto following = length + next_length + _week_one(following_january, week_start)
        weeks = (following - next) // 7
        week = 1
    return week in numbers or week - weeks - 1 in numbers

def _easter_days(int64 year, set[int64] offsets) -> set[int64]:
    set[int64] days = set[int64]()
    auto start = _day_number(datetime.date(year, 1, 1))
    auto finish = start + _year_length(year) - 1
    auto first_anchor = _day_number(datetime.date(_FIRST_EASTER_YEAR, 1, 1))
    auto last_anchor = _day_number(datetime.date(_LAST_EASTER_YEAR, 12, 31))
    for offset in offsets:
        # Shift the destination year back to find the possible Easter years.
        auto first_day = start - offset
        auto last_day = finish - offset
        if first_day < first_anchor:
            first_day = first_anchor
        if last_day > last_anchor:
            last_day = last_anchor
        if first_day > last_day:
            continue
        auto first_year = datetime.from_timestamp(first_day * 86400).year
        auto last_year = datetime.from_timestamp(last_day * 86400).year
        for anchor in range(first_year, last_year + 1):
            auto target = _day_number(computus.easter(anchor)) + offset
            if target >= start and target <= finish:
                days.add(target - start + 1)
    return days

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

value struct _WeekdayFilter:
    int64 plain
    list[int64] ordinals
    bool annual

def _weekday_filter(
    list[relative.Weekday] selectors,
    int64 freq,
    bool annual,
) -> _WeekdayFilter:
    auto plain = 0
    list[int64] ordinals = []
    for selector in selectors:
        auto weekday = selector.weekday
        auto ordinal = selector.n
        if weekday < 0 or weekday > 6:
            raise ValueError("byweekday weekdays must be in 0..6")
        if ordinal == 0:
            plain |= 1 << weekday
        else:
            if freq > MONTHLY or ordinal < -53 or ordinal > 53:
                raise ValueError(
                    "byweekday ordinals require yearly or monthly frequency and magnitude 1..53",
                )
            if len(ordinals) == 0:
                ordinals = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            if ordinal > 0:
                ordinals[weekday] = ordinals[weekday] | 1 << ordinal
            else:
                ordinals[weekday + 7] = ordinals[weekday + 7] | 1 << -ordinal
    return _WeekdayFilter(plain, ordinals, annual)

def _allows_weekday(_WeekdayFilter filter, Date day) -> bool:
    if filter.plain == 0 and len(filter.ordinals) == 0:
        return True
    auto weekday = datetime.date_weekday(day)
    if filter.plain & 1 << weekday != 0:
        return True
    if len(filter.ordinals) == 0:
        return False
    auto number = day.day
    auto last = _month_length(day.year, day.month)
    if filter.annual:
        number = datetime.date_day_of_year(day)
        last = _year_length(day.year)
    auto forward = (number - 1) // 7 + 1
    auto backward = (last - number) // 7 + 1
    return filter.ordinals[weekday] & 1 << forward != 0 or filter.ordinals[weekday + 7] & 1 << backward != 0

value struct _ClockChoices:
    int64 fixed_hours
    int64 fixed_minutes
    int64 fixed_seconds
    list[int64] hours
    list[int64] minutes
    list[int64] seconds

def _clock_choice(
    Optional[list[int64]] selectors,
    int64 width,
    int64 fallback,
    bool expand,
    str name,
) -> (int64, list[int64]):
    if selectors.is_none():
        return (0, [fallback])
    auto mask = 0
    for value in selectors.unwrap():
        if value < 0 or value >= width:
            raise ValueError(name + " values must be in 0.." + str(width - 1))
        mask |= 1 << value
    list[int64] values = []
    if mask == 0:
        return (0, values)
    if not expand:
        return (mask, [fallback])
    for value in range(width):
        if mask & 1 << value != 0:
            values.append(value)
    return (0, values)

def _clock_allows(int64 mask, int64 value) -> bool:
    return mask == 0 or mask & 1 << value != 0

def _clock_can_match(_ClockChoices clock, int64 period, int64 step) -> bool:
    if clock.fixed_hours == 0 and clock.fixed_minutes == 0 and clock.fixed_seconds == 0:
        return True
    # The stride visits exactly one residue class of clock times modulo a day.
    auto phase = math.gcd(step, 86400)
    for second in range(period % phase, 86400, phase):
        if _clock_allows(clock.fixed_hours, second // 3600) and _clock_allows(clock.fixed_minutes, second // 60 % 60) and _clock_allows(clock.fixed_seconds, second % 60):
            return True
    return False

def _clock_second(int64 hour, int64 minute, int64 second) -> int64:
    return hour * 3600 + minute * 60 + second

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
    Optional[list[relative.Weekday]] byweekday = None
    Optional[relative.Weekday] wkst = None
    Optional[list[int64]] byhour = None
    Optional[list[int64]] byminute = None
    Optional[list[int64]] bysecond = None
    Optional[list[int64]] byyearday = None
    Optional[list[int64]] byeaster = None
    Optional[list[int64]] byweekno = None
    Optional[list[int64]] bysetpos = None

    def __iter__(self) -> _RuleIterator:
        """Iterate from dtstart, skipping invalid dates and nonexistent local times.

        Count and the inclusive until bound are mutually exclusive. For an
        aware start, the bound must be UTC. Each iteration starts at dtstart.
        Month, signed month-day, and weekday selectors are lists. Weekly
        periods start on Monday unless wkst is supplied. Clock selectors
        expand finer components and limit the cadence at coarser components.
        Set positions select within each period before applying bounds.
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
        auto wall_start = datetime.to_timestamp(base) + base.offset
        auto clock_start = _clock_second(base.hour, base.minute, base.second)
        auto first_day = wall_start - clock_start
        auto period = wall_start
        if self.freq < HOURLY:
            period = first_day
        elif self.freq == HOURLY:
            period -= base.minute * 60 + base.second
        elif self.freq == MINUTELY:
            period -= base.second
        auto weekly = self.freq == WEEKLY and (self.byweekday.is_some() or self.byeaster.is_some())
        auto week_start = 0
        if self.wkst.is_some():
            auto token = self.wkst.unwrap()
            if token.weekday < 0 or token.weekday > 6 or token.n != 0:
                raise ValueError("wkst must be a plain weekday token")
            week_start = token.weekday
        if weekly:
            auto weekday = datetime.date_weekday(datetime.to_date(base))
            period -= (weekday - week_start + 7) % 7 * 86400
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
        auto expand_days = self.bymonthday.is_some() or self.byweekday.is_some() or self.byyearday.is_some() or self.byeaster.is_some() or self.byweekno.is_some()
        if self.bymonth.is_some():
            months = _month_mask(self.bymonth.unwrap())
        elif yearly and not expand_days:
            months = 1 << base.month
        if self.bymonthday.is_some():
            if self.freq == WEEKLY:
                raise ValueError("bymonthday is invalid for weekly recurrence")
            monthdays = _monthday_mask(self.bymonthday.unwrap())
        auto weekdays = _WeekdayFilter(0, [], False)
        if self.byweekday.is_some():
            weekdays = _weekday_filter(
                self.byweekday.unwrap(),
                self.freq,
                yearly and months == 0,
            )
        set[int64] yeardays = set[int64]()
        if self.byyearday.is_some():
            if self.freq >= MONTHLY and self.freq <= DAILY:
                raise ValueError("byyearday requires yearly or sub-day recurrence")
            yeardays = _signed_selector_set(self.byyearday.unwrap(), 366, "byyearday")
        set[int64] week_numbers = set[int64]()
        if self.byweekno.is_some():
            if not yearly:
                raise ValueError("byweekno requires yearly recurrence")
            if len(weekdays.ordinals) > 0:
                raise ValueError("byweekno cannot be combined with ordinal weekdays")
            week_numbers = _signed_selector_set(self.byweekno.unwrap(), 53, "byweekno")
        set[int64] easter_offsets = set[int64]()
        if self.byeaster.is_some():
            auto offsets = self.byeaster.unwrap()
            auto first_easter = _day_number(computus.easter(_FIRST_EASTER_YEAR))
            auto last_easter = _day_number(computus.easter(_LAST_EASTER_YEAR))
            for offset in offsets:
                if offset >= _FIRST_CIVIL_DAY - last_easter and offset <= _LAST_CIVIL_DAY - first_easter:
                    easter_offsets.add(offset)
            if len(offsets) > 0 and len(easter_offsets) == 0:
                remaining = 0
        if not _can_match_date(months, monthdays):
            remaining = 0

        # An interval larger than the remaining range yields at most the anchor.
        auto step = end - period + 1
        if self.interval <= (end - period) // unit:
            step = self.interval * unit
        auto positions = _set_positions(self.bysetpos)
        if len(positions.requested) != 0 and not (expand_days or self.bymonth.is_some() or self.byhour.is_some() or self.byminute.is_some() or self.bysecond.is_some()):
            raise ValueError("bysetpos requires another BY selector")
        auto fixed_hours, hours = _clock_choice(
            self.byhour,
            24,
            base.hour,
            self.freq < HOURLY,
            "byhour",
        )
        auto fixed_minutes, minutes = _clock_choice(
            self.byminute,
            60,
            base.minute,
            self.freq < MINUTELY,
            "byminute",
        )
        auto fixed_seconds, seconds = _clock_choice(
            self.bysecond,
            60,
            base.second,
            self.freq < SECONDLY,
            "bysecond",
        )
        auto clock = _ClockChoices(
            fixed_hours,
            fixed_minutes,
            fixed_seconds,
            hours,
            minutes,
            seconds,
        )
        auto clock_count = len(hours) * len(minutes) * len(seconds)
        if clock_count == 0 or period > end:
            remaining = 0
        elif not calendar and not _clock_can_match(clock, period, step):
            remaining = 0
        return _RuleIterator(
            base=base,
            until=self.until,
            remaining=remaining,
            freq=self.freq,
            yearly=yearly,
            weekly=weekly,
            first_day=first_day,
            clock_start=clock_start,
            period=period,
            end=end,
            step=step,
            months=months,
            monthdays=monthdays,
            expand_days=expand_days,
            weekdays=weekdays,
            yeardays=yeardays,
            week_numbers=week_numbers,
            week_start=week_start,
            easter_offsets=easter_offsets,
            easter_days=set[int64](),
            clock=clock,
            clock_count=clock_count,
            seed=base,
            positions=positions,
            lookahead=base,
            position_buffer=[],
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
    int64 freq
    bool yearly
    bool weekly
    int64 first_day
    int64 clock_start
    int64 period
    int64 end
    int64 step
    int64 months
    int64 monthdays
    bool expand_days
    _WeekdayFilter weekdays
    set[int64] yeardays
    set[int64] week_numbers
    int64 week_start
    set[int64] easter_offsets
    set[int64] easter_days
    _ClockChoices clock
    int64 clock_count
    DateTime seed
    _SetPositions positions
    DateTime lookahead
    list[DateTime] position_buffer
    int64 seed_period = 0
    bool has_lookahead = False
    bool position_source_finished = False
    int64 position_index = 0
    int64 easter_year = 0
    int64 clock_index = 0
    int64 month = 1
    int64 day = 1

    def __iter__(self) -> _RuleIterator:
        return self

    def _has_easter_candidates(self, int64 year) -> bool:
        if len(self.easter_offsets) == 0:
            return True
        if self.easter_year != year:
            self.easter_days = _easter_days(year, self.easter_offsets)
            self.easter_year = year
        return len(self.easter_days) > 0

    def _allows_day(self, Date date, int64 last) -> bool:
        if not _allows_monthday(self.monthdays, date.day, last) or not _allows_weekday(self.weekdays, date):
            return False
        if len(self.yeardays) == 0 and len(self.easter_offsets) == 0 and len(self.week_numbers) == 0:
            return True
        auto ordinal = datetime.date_day_of_year(date)
        if len(self.week_numbers) != 0 and not _allows_week_number(self.week_numbers, date, ordinal, self.week_start):
            return False
        if len(self.yeardays) != 0 and ordinal not in self.yeardays and ordinal - _year_length(date.year) - 1 not in self.yeardays:
            return False
        return len(self.easter_offsets) == 0 or self._has_easter_candidates(date.year) and ordinal in self.easter_days

    def _advance_month(self):
        self.day = 1
        if self.yearly and self.month < 12:
            self.month += 1
        else:
            self.month = 1
            self.period += self.step

    def _next_calendar(self) -> DateTime:
        while self.period <= self.end:
            auto period = self.period
            auto year = period // 12 + 1
            auto month = period % 12 + 1
            if self.yearly:
                month = self.month
            if not _allows_month(self.months, month) or not self._has_easter_candidates(year):
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
            if day > last:
                continue
            if len(self.positions.requested) == 0 and year == self.base.year:
                if month < self.base.month or month == self.base.month and day < self.base.day:
                    continue
            if not self._allows_day(datetime.date(year, month, day), last):
                continue
            self.seed_period = period
            return datetime.combine(
                datetime.date(year, month, day),
                datetime.time(0, 0, 0),
            )
        raise StopIteration

    def _next_week(self) -> DateTime:
        while self.period <= self.end:
            auto period = self.period
            auto index = period + (self.day - 1) * 86400
            if index > _LAST_SECOND or len(self.positions.requested) == 0 and index > self.end:
                break
            if self.day == 7:
                self.day = 1
                self.period += self.step
            else:
                self.day += 1
            if index // 86400 < _FIRST_CIVIL_DAY or len(self.positions.requested) == 0 and index < self.first_day:
                continue
            auto wall = datetime.from_timestamp(index)
            if _allows_month(self.months, wall.month) and self._allows_day(datetime.to_date(wall), _month_length(wall.year, wall.month)):
                self.seed_period = period
                return wall
        raise StopIteration

    def _skip_seconds(self, int64 seconds):
        auto steps = (seconds - 1) // self.step + 1
        self.period += steps * self.step

    def _next_clock(self) -> DateTime:
        while self.period <= self.end:
            auto period = self.period
            auto wall = datetime.from_timestamp(period)
            if not self._has_easter_candidates(wall.year):
                auto days_left = _year_length(wall.year) - datetime.date_day_of_year(datetime.to_date(wall)) + 1
                self._skip_seconds(
                    days_left * 86400 - _clock_second(wall.hour, wall.minute, wall.second),
                )
            elif not _allows_month(self.months, wall.month) or not self._allows_day(datetime.to_date(wall), _month_length(wall.year, wall.month)):
                self._skip_seconds(
                    86400 - _clock_second(wall.hour, wall.minute, wall.second),
                )
            elif not _clock_allows(self.clock.fixed_hours, wall.hour):
                self._skip_seconds(3600 - wall.minute * 60 - wall.second)
            elif not _clock_allows(self.clock.fixed_minutes, wall.minute):
                self._skip_seconds(60 - wall.second)
            else:
                self.period += self.step
                if _clock_allows(self.clock.fixed_seconds, wall.second):
                    self.seed_period = period
                    return wall
        raise StopIteration

    def _next_seed(self) -> DateTime:
        if self.freq <= MONTHLY:
            return self._next_calendar()
        if self.weekly:
            return self._next_week()
        return self._next_clock()

    def _next_candidate(self) -> DateTime:
        while True:
            if self.clock_index == 0:
                self.seed = self._next_seed()
            auto index = self.clock_index
            self.clock_index = (index + 1) % self.clock_count

            auto hour = self.seed.hour
            auto minute = self.seed.minute
            auto second = self.seed.second
            auto second_count = len(self.clock.seconds)
            auto minute_count = len(self.clock.minutes)
            if self.freq < HOURLY:
                hour = self.clock.hours[index // (minute_count * second_count)]
            if self.freq < MINUTELY:
                minute = self.clock.minutes[index // second_count % minute_count]
            if self.freq < SECONDLY:
                second = self.clock.seconds[index % second_count]

            if len(self.positions.requested) == 0 and self.seed.year == self.base.year and self.seed.month == self.base.month and self.seed.day == self.base.day:
                if _clock_second(hour, minute, second) < self.clock_start:
                    continue
            auto occurrence = datetime.replace(
                self.base,
                year=self.seed.year,
                month=self.seed.month,
                day=self.seed.day,
                hour=hour,
                minute=minute,
                second=second,
                nanosecond=0,
            )
            if not datetime.is_imaginary(occurrence):
                return occurrence

    def _skip_position_period(self, int64 period):
        self.clock_index = 0
        if self.period == period:
            self.period += self.step
            self.day = 1
            self.month = 1

    def _fill_positions(self):
        if self.position_source_finished:
            raise StopIteration
        auto candidate = self.lookahead
        if self.has_lookahead:
            self.has_lookahead = False
        else:
            candidate = self._next_candidate()
        auto period = self.seed_period
        list[DateTime] first = []
        list[DateTime] tail = []
        auto count = 0
        while True:
            if count < self.positions.leading:
                first.append(candidate)
            if count < self.positions.trailing:
                tail.append(candidate)
            elif self.positions.trailing != 0:
                tail[count % self.positions.trailing] = candidate
            count += 1
            if self.positions.trailing == 0 and count == self.positions.leading:
                self._skip_position_period(period)
                break
            try:
                candidate = self._next_candidate()
            except StopIteration:
                self.position_source_finished = True
                break
            if self.seed_period != period:
                self.lookahead = candidate
                self.has_lookahead = True
                break

        set[int64] indexes = set[int64]()
        for position in self.positions.requested:
            auto index = position - 1
            if position < 0:
                index = count + position
            if index >= 0 and index < count:
                indexes.add(index)

        list[DateTime] selected = []
        for index in range(len(first)):
            if index in indexes:
                selected.append(first[index])
        auto tail_start = count - len(tail)
        if tail_start < len(first):
            tail_start = len(first)
        for index in range(tail_start, count):
            if index in indexes:
                selected.append(tail[index % self.positions.trailing])
        self.position_buffer = selected
        self.position_index = 0

    def _next_position(self) -> DateTime:
        while self.position_index >= len(self.position_buffer):
            self._fill_positions()
        auto result = self.position_buffer[self.position_index]
        self.position_index += 1
        return result

    def __next__(self) -> DateTime:
        while self.remaining != 0:
            auto occurrence = self.base
            if len(self.positions.requested) == 0:
                occurrence = self._next_candidate()
            else:
                occurrence = self._next_position()
                if datetime.to_timestamp(occurrence) + occurrence.offset < self.first_day + self.clock_start:
                    continue
            if self.until.is_some() and datetime.to_timestamp(occurrence) > datetime.to_timestamp(self.until.unwrap()):
                self.remaining = 0
                break
            if self.remaining > 0:
                self.remaining -= 1
            return occurrence
        raise StopIteration
