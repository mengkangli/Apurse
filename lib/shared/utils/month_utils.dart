bool isCurrentOrFutureMonth(DateTime month) {
  final now = DateTime.now();
  final current = DateTime(now.year, now.month);
  final normalized = DateTime(month.year, month.month);
  return !normalized.isBefore(current);
}

DateTime clampToCurrentMonth(DateTime month) {
  final now = DateTime.now();
  final current = DateTime(now.year, now.month);
  final normalized = DateTime(month.year, month.month);
  return normalized.isAfter(current) ? current : normalized;
}

/// `"yyyy-MM"` for [date]'s month, e.g. `"2026-10"`.
String monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

/// First and last day of a month as the `"yyyy-MM-dd"` strings stored in
/// `transactions.date`, for `date >= ? AND date <= ?` queries.
(String, String) monthDateRange(int year, int month) {
  final prefix = monthKey(DateTime(year, month));
  final lastDay = DateTime(year, month + 1, 0).day;
  return ('$prefix-01', '$prefix-${lastDay.toString().padLeft(2, '0')}');
}
