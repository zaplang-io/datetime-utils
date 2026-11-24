import datetime

struct _ProbeCursor:
    DateTime seed
    int64 index = 0

    def _make_seed(self) -> DateTime:
        return datetime.combine(datetime.date(2024, 1, 31), datetime.time(0, 0, 0))

    def emit(self) -> DateTime:
        if self.index == 0:
            self.seed = self._make_seed()
        self.index += 1
        return datetime.replace(self.seed, hour=self.index, nanosecond=0)

@test
def returned_datetime_field_reassignment_probe():
    auto cursor = _ProbeCursor(datetime.from_timestamp(0))
    auto first = cursor.emit()
    assert datetime.isoformat(first) == "2024-01-31T01:00:00"
    auto second = cursor.emit()
    assert datetime.isoformat(second) == "2024-01-31T02:00:00"
