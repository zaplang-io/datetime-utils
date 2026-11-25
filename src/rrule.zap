"Lazy calendar recurrence rules over core DateTime values."

import datetime
import easter as computus
import math
import parser as date_parser
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

def _query_compare(DateTime left, DateTime right, bool shared_zone_wall_time) -> int64:
    if left.is_aware != right.is_aware:
        raise TypeError("Recurrence queries cannot mix naive and aware datetimes")
    auto a = datetime.to_timestamp(left)
    auto b = datetime.to_timestamp(right)
    if shared_zone_wall_time and left.is_aware and left.zone_id >= 0 and left.zone_id == right.zone_id:
        a += left.offset
        b += right.offset
    if a < b or a == b and left.nanosecond < right.nanosecond:
        return -1
    if a > b or a == b and left.nanosecond > right.nanosecond:
        return 1
    return 0

def _before[T](
    T series,
    DateTime dt,
    bool inc,
    bool shared_zone_wall_time,
) -> Optional[DateTime]:
    Optional[DateTime] last = None
    for occurrence in series:
        auto order = _query_compare(occurrence, dt, shared_zone_wall_time)
        if order > 0 or order == 0 and not inc:
            break
        last = occurrence
    return last

def _after[T](
    T series,
    DateTime dt,
    bool inc,
    bool shared_zone_wall_time,
) -> Optional[DateTime]:
    for occurrence in series:
        auto order = _query_compare(occurrence, dt, shared_zone_wall_time)
        if order > 0 or order == 0 and inc:
            return occurrence
    return None

def _between[T](
    T series,
    DateTime after,
    DateTime before,
    bool inc,
    bool shared_zone_wall_time,
) -> list[DateTime]:
    list[DateTime] matches = []
    for occurrence in series:
        auto upper = _query_compare(occurrence, before, shared_zone_wall_time)
        if upper > 0 or upper == 0 and not inc:
            break
        auto lower = _query_compare(occurrence, after, shared_zone_wall_time)
        if lower > 0 or lower == 0 and inc:
            matches.append(occurrence)
    return matches

def _count[T](T series) -> int64:
    auto total = 0
    for occurrence in series:
        total += 1
    return total

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
        return _before(self, dt, inc, True)

    def after(self, DateTime dt, bool inc = False) -> Optional[DateTime]:
        "Return the first occurrence after dt, including dt when inc is true."
        return _after(self, dt, inc, True)

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
        return _between(self, after, before, inc, True)

    def count(self) -> int64:
        "Count emitted occurrences by traversing the rule from the start."
        return _count(self)

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


def _set_seconds(DateTime date) -> int64:
    return datetime.to_timestamp(date)

def _set_fraction(DateTime date) -> int64:
    return date.nanosecond

struct _SetRuleCursor:
    _RuleIterator cursor
    DateTime current
    bool active = False

    def advance(self):
        try:
            self.current = self.cursor.__next__()
            self.active = True
        except StopIteration:
            self.active = False

struct _SetStream:
    list[_SetRuleCursor] rules
    list[DateTime] dates
    int64 date_index = 0
    # -2 is the initial state, -1 is the explicit date stream.
    int64 source = -2
    bool finished = False

    def take(self) -> DateTime:
        if self.finished:
            raise StopIteration
        if self.source == -2:
            for rule in self.rules:
                rule.advance()
        elif self.source == -1:
            self.date_index += 1
        else:
            self.rules[self.source].advance()

        Optional[DateTime] best = None
        auto source = -1
        if self.date_index < len(self.dates):
            best = self.dates[self.date_index]
        for index in range(len(self.rules)):
            auto rule = self.rules[index]
            if rule.active and (best.is_none() or _query_compare(rule.current, best.unwrap(), False) < 0):
                best = rule.current
                source = index
        if best.is_none():
            self.finished = True
            raise StopIteration
        self.source = source
        return best.unwrap()

def _set_stream(list[RRule] rules, list[DateTime] dates) -> _SetStream:
    list[_SetRuleCursor] cursors = []
    for rule in rules:
        auto cursor = rule.__iter__()
        cursors.append(_SetRuleCursor(cursor, cursor.base))

    auto ordered = dates[:]
    if len(ordered) > 1:
        auto first = ordered[0]
        for date in ordered:
            if date.is_aware != first.is_aware:
                raise TypeError("Recurrence sets cannot mix naive and aware datetimes")
        # Stable passes preserve fractions and the input order of exact ties.
        ordered.sort(key=_set_fraction)
        ordered.sort(key=_set_seconds)
    return _SetStream(cursors, ordered)

struct _RuleSetIterator:
    _SetStream includes
    _SetStream excludes
    Optional[DateTime] previous = None
    Optional[DateTime] exclusion = None
    bool exclusions_finished = False

    def __iter__(self) -> _RuleSetIterator:
        return self

    def _is_excluded(self, DateTime candidate) -> bool:
        while not self.exclusions_finished:
            if self.exclusion.is_some():
                auto order = _query_compare(self.exclusion.unwrap(), candidate, False)
                if order >= 0:
                    return order == 0
            try:
                self.exclusion = self.excludes.take()
            except StopIteration:
                self.exclusions_finished = True
        return False

    def __next__(self) -> DateTime:
        while True:
            auto candidate = self.includes.take()
            if self.previous.is_some() and _query_compare(self.previous.unwrap(), candidate, False) == 0:
                continue
            self.previous = candidate
            if not self._is_excluded(candidate):
                return candidate

struct RRuleSet:
    list[RRule] _rules = []
    list[DateTime] _dates = []
    list[RRule] _excluded_rules = []
    list[DateTime] _excluded_dates = []

    def rrule(self, RRule rule):
        "Include the occurrences of rule."
        self._rules.append(rule)

    def rdate(self, DateTime date):
        "Include an explicit datetime."
        self._dates.append(date)

    def exrule(self, RRule rule):
        "Exclude the occurrences of rule."
        self._excluded_rules.append(rule)

    def exdate(self, DateTime date):
        "Exclude an explicit datetime."
        self._excluded_dates.append(date)

    def __iter__(self) -> _RuleSetIterator:
        "Return a fresh ordered cursor over the included occurrences that survive exclusions."
        auto includes = _set_stream(self._rules, self._dates)
        auto excludes = _set_stream(self._excluded_rules, self._excluded_dates)
        return _RuleSetIterator(includes, excludes)

    def before(self, DateTime dt, bool inc = False) -> Optional[DateTime]:
        "Return the last occurrence before dt, including dt when inc is true."
        return _before(self, dt, inc, False)

    def after(self, DateTime dt, bool inc = False) -> Optional[DateTime]:
        "Return the first occurrence after dt, including dt when inc is true."
        return _after(self, dt, inc, False)

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
        return _between(self, after, before, inc, False)

    def count(self) -> int64:
        "Count emitted occurrences by traversing the set from the start."
        return _count(self)

def _ical_integer(str value) -> int64:
    auto text = bytes(value)
    auto start = 0
    bool negative = False
    if len(text) > 0:
        negative = text[0] == 45
        if negative or text[0] == 43:
            start = 1
    if start == len(text):
        raise date_parser.ParserError("Expected an integer recurrence value")
    auto final_digit = 7
    if negative:
        final_digit = 8
    auto result = 0
    for index in range(start, len(text)):
        auto digit = int64(text[index]) - 48
        if digit < 0 or digit > 9:
            raise date_parser.ParserError("Expected an ASCII recurrence integer")
        if result < -922337203685477580 or result == -922337203685477580 and digit > final_digit:
            raise date_parser.ParserError("Recurrence integer is out of range")
        result = result * 10 - digit
    if negative:
        return result
    return -result

def _ical_integers(str value) -> list[int64]:
    list[int64] values = []
    for item in value.split(","):
        values.append(_ical_integer(item))
    return values

def _ical_weekday(str value, bool allow_ordinal) -> relative.Weekday:
    auto length = len(value)
    if length < 2:
        raise date_parser.ParserError("Invalid recurrence weekday")
    auto spelling = value[length - 2:]
    auto weekday = -1
    auto names = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
    for index in range(len(names)):
        if spelling == names[index]:
            weekday = index
            break
    if weekday == -1:
        raise date_parser.ParserError("Invalid recurrence weekday")
    auto ordinal = 0
    if length > 2:
        if not allow_ordinal:
            raise date_parser.ParserError("WKST requires a plain weekday")
        ordinal = _ical_integer(value[:length - 2])
        if ordinal == 0:
            raise date_parser.ParserError("A BYDAY ordinal cannot be zero")
    return relative.Weekday(weekday, ordinal)

def _ical_weekdays(str value) -> list[relative.Weekday]:
    list[relative.Weekday] values = []
    for item in value.split(","):
        values.append(_ical_weekday(item, True))
    return values

def _ical_frequency(str value) -> int64:
    auto names = [
        "YEARLY",
        "MONTHLY",
        "WEEKLY",
        "DAILY",
        "HOURLY",
        "MINUTELY",
        "SECONDLY",
    ]
    for index in range(len(names)):
        if value == names[index]:
            return index
    raise date_parser.ParserError("Invalid recurrence frequency")

def _ical_datetime(str value, str zone_name, str value_type) -> DateTime:
    auto spelling = value.upper()
    auto length = len(spelling)
    auto date_only = length == 8
    bool utc = False
    if not date_only:
        if length != 15 and length != 16:
            raise date_parser.ParserError(
                "Expected a basic RFC recurrence date or datetime",
            )
        utc = length == 16 and spelling[15:] == "Z"
        if spelling[8:9] != "T" or length == 16 and not utc or spelling[9:11] == "24":
            raise date_parser.ParserError("Invalid RFC recurrence datetime")
    if value_type == "DATE" and not date_only or value_type == "DATE-TIME" and date_only:
        raise date_parser.ParserError(
            "Recurrence value does not match its declared type",
        )
    if zone_name != "" and (date_only or utc):
        raise date_parser.ParserError("TZID requires a local date-time value")

    # Enforce the basic YYYYMMDD and YYYYMMDDTHHMMSS[Z] field layouts.
    auto text = bytes(spelling)
    for index in range(len(text)):
        if not date_only and (index == 8 or index == 15):
            continue
        if text[index] < 48 or text[index] > 57:
            raise date_parser.ParserError("Invalid RFC recurrence date fields")
    auto stamp = date_parser.isoparse(spelling)
    if zone_name == "":
        return stamp
    try:
        auto zone = datetime.zone(zone_name)
        return datetime.resolve(
            zone,
            stamp.year,
            stamp.month,
            stamp.day,
            stamp.hour,
            stamp.minute,
            stamp.second,
        )
    except Exception:
        raise date_parser.ParserError("Invalid recurrence TZID: " + zone_name)

def _ical_rule(str value, Optional[DateTime] start) -> RRule:
    auto rule = RRule(-1, dtstart=start)
    set[str] seen = set[str]()
    for part in value.upper().split(";"):
        auto fields = part.split("=")
        if len(fields) != 2 or fields[0] == "" or fields[1] == "":
            raise date_parser.ParserError("Malformed recurrence rule part")
        auto name = fields[0]
        auto item = fields[1]
        if name in seen:
            raise date_parser.ParserError("Duplicate recurrence rule part: " + name)
        seen.add(name)
        match name:
            case "FREQ":
                rule.freq = _ical_frequency(item)
            case "INTERVAL":
                rule.interval = _ical_integer(item)
            case "COUNT":
                rule.count = _ical_integer(item)
            case "UNTIL":
                rule.until = _ical_datetime(item, "", "")
            case "WKST":
                rule.wkst = _ical_weekday(item, False)
            case "BYMONTH":
                rule.bymonth = _ical_integers(item)
            case "BYMONTHDAY":
                rule.bymonthday = _ical_integers(item)
            case "BYDAY":
                rule.byweekday = _ical_weekdays(item)
            case "BYHOUR":
                rule.byhour = _ical_integers(item)
            case "BYMINUTE":
                rule.byminute = _ical_integers(item)
            case "BYSECOND":
                rule.bysecond = _ical_integers(item)
            case "BYYEARDAY":
                rule.byyearday = _ical_integers(item)
            case "BYEASTER":
                rule.byeaster = _ical_integers(item)
            case "BYWEEKNO":
                rule.byweekno = _ical_integers(item)
            case "BYSETPOS":
                rule.bysetpos = _ical_integers(item)
            case _:
                raise date_parser.ParserError(
                    "Unsupported recurrence rule part: " + name,
                )
    if rule.freq == -1:
        raise date_parser.ParserError("A recurrence rule requires FREQ")
    try:
        rule.__iter__()
    except ValueError as message:
        raise date_parser.ParserError(message)
    return rule

value struct _RecurrenceLine:
    str name
    str value
    str zone_name
    str value_type

def _ical_lines(str value, bool unfold) -> list[str]:
    if value is None:
        raise date_parser.ParserError("Expected recurrence text")
    list[str] lines = []
    for line in value.replace("\r\n", "\n").split("\n"):
        if line.strip() == "":
            continue
        if line.startswith(" ") or line.startswith("\t"):
            if unfold and len(lines) > 0:
                auto previous = len(lines) - 1
                lines[previous] += line[1:]
                continue
            raise date_parser.ParserError("Unexpected folded recurrence line")
        lines.append(line.strip())
    if len(lines) == 0:
        raise date_parser.ParserError("Expected recurrence text")
    return lines

def _ical_record(str line) -> _RecurrenceLine:
    auto parts = line.split(":", 1)
    if len(parts) != 2 or parts[1] == "":
        raise date_parser.ParserError("Malformed recurrence content line")
    auto header = parts[0].split(";")
    auto name = header[0].upper()
    if name not in ["RRULE", "EXRULE", "DTSTART", "RDATE", "EXDATE"]:
        raise date_parser.ParserError("Unsupported recurrence property: " + name)
    if len(header) > 1 and (name == "RRULE" or name == "EXRULE"):
        raise date_parser.ParserError(
            "Recurrence rules do not take property parameters",
        )
    auto zone_name = ""
    auto value_type = ""
    for index in range(1, len(header)):
        auto parameter = header[index].split("=", 1)
        if len(parameter) != 2 or parameter[1] == "":
            raise date_parser.ParserError("Malformed recurrence property parameter")
        auto key = parameter[0].upper()
        auto value = parameter[1]
        if value.startswith('"') and value.endswith('"') and len(value) > 2:
            value = value[1:len(value) - 1]
        if key == "TZID" and zone_name == "":
            zone_name = value
        elif key == "VALUE" and value_type == "":
            value_type = value.upper()
            if value_type != "DATE" and value_type != "DATE-TIME":
                raise date_parser.ParserError(
                    "Unsupported recurrence value type: " + value_type,
                )
        else:
            raise date_parser.ParserError(
                "Duplicate or unsupported recurrence property parameter: " + key,
            )
    return _RecurrenceLine(name, parts[1], zone_name, value_type)

def rrulestr(str s, Optional[DateTime] dtstart = None, bool unfold = False) -> RRuleSet:
    """Parse RFC recurrence text into a rule set, including for a single rule.

    An explicit DTSTART overrides dtstart. If neither is supplied, rules
    use local now. Set unfold to accept continuation lines. Malformed
    recurrence text raises ParserError.
    """
    auto lines = _ical_lines(s, unfold)
    auto result = RRuleSet()
    auto effective_start = dtstart
    if len(lines) == 1 and ":" not in lines[0]:
        if effective_start.is_none():
            effective_start = _local_start()
        result.rrule(_ical_rule(lines[0], effective_start))
        return result

    list[_RecurrenceLine] records = []
    bool has_start = False
    for line in lines:
        auto record = _ical_record(line)
        if record.name == "DTSTART":
            if has_start:
                raise date_parser.ParserError("Duplicate recurrence DTSTART")
            effective_start = _ical_datetime(
                record.value,
                record.zone_name,
                record.value_type,
            )
            has_start = True
        else:
            records.append(record)
    if len(records) == 0:
        raise date_parser.ParserError("Expected a recurrence rule or date")
    if effective_start.is_none():
        effective_start = _local_start()
    for record in records:
        if record.name == "RRULE":
            result.rrule(_ical_rule(record.value, effective_start))
        elif record.name == "EXRULE":
            result.exrule(_ical_rule(record.value, effective_start))
        else:
            for value in record.value.split(","):
                auto date = _ical_datetime(value, record.zone_name, record.value_type)
                if record.name == "RDATE":
                    result.rdate(date)
                else:
                    result.exdate(date)
    return result
