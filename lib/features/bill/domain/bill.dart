import '../../../core/database/money.dart';
import '../../../shared/utils/month_utils.dart';

class Bill {
  final String id;
  final String name;
  final double amount;
  final String categoryId;
  final int dueDay;
  final bool isRecurring;

  /// Raw `is_paid` flag. Only one-off bills use it directly; a recurring
  /// bill is paid only for the month in [lastPaidPeriod].
  final bool paid;

  /// `"yyyy-MM"` of the month the bill was last marked paid.
  final String? lastPaidPeriod;
  final int? notificationId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Bill({
    required this.id,
    required this.name,
    required this.amount,
    required this.categoryId,
    required this.dueDay,
    required this.isRecurring,
    required this.paid,
    this.lastPaidPeriod,
    this.notificationId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPaid => isPaidOn(DateTime.now());

  /// Whether the bill counts as paid on [date]: one-off bills stay paid,
  /// recurring bills reset when a new month starts.
  bool isPaidOn(DateTime date) =>
      isRecurring ? lastPaidPeriod == monthKey(date) : paid;

  /// The actual due date this month (or next month if passed), clamped to valid days.
  DateTime get currentDueDate {
    final now = DateTime.now();
    int day = dueDay.clamp(1, _daysInMonth(now.year, now.month));
    DateTime due = DateTime(now.year, now.month, day);
    // If we're past the due date this month, look at next month
    if (now.day > day) {
      int nextMonth = now.month == 12 ? 1 : now.month + 1;
      int nextYear = now.month == 12 ? now.year + 1 : now.year;
      int clampedDay = dueDay.clamp(1, _daysInMonth(nextYear, nextMonth));
      due = DateTime(nextYear, nextMonth, clampedDay);
    }
    return due;
  }

  /// The bill's due date relative to the current date, for display purposes.
  DateTime get _displayDueDate {
    final now = DateTime.now();
    int day = dueDay.clamp(1, _daysInMonth(now.year, now.month));
    return DateTime(now.year, now.month, day);
  }

  static int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  bool get isOverdue {
    if (isPaid) return false;
    final now = DateOnly.today();
    final due = DateOnly(_displayDueDate.year, _displayDueDate.month, _displayDueDate.day);
    return now.isAfter(due);
  }

  int get daysUntilDue {
    if (isPaid) return 999;
    final now = DateOnly.today();
    final due = DateOnly(_displayDueDate.year, _displayDueDate.month, _displayDueDate.day);
    return due.difference(now);
  }

  /// Database row. `amount` is stored in integer cents.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': toCents(amount),
        'category_id': categoryId,
        'due_day': dueDay,
        'is_recurring': isRecurring ? 1 : 0,
        'is_paid': paid ? 1 : 0,
        'last_paid_period': lastPaidPeriod,
        'notification_id': notificationId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Bill.fromJson(Map<String, dynamic> json) => Bill(
        id: json['id'] as String,
        name: json['name'] as String,
        amount: fromCents(json['amount'] as num),
        categoryId: json['category_id'] as String,
        dueDay: json['due_day'] as int,
        isRecurring: (json['is_recurring'] as int) == 1,
        paid: (json['is_paid'] as int) == 1,
        lastPaidPeriod: json['last_paid_period'] as String?,
        notificationId: json['notification_id'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Bill copyWith({
    String? id,
    String? name,
    double? amount,
    String? categoryId,
    int? dueDay,
    bool? isRecurring,
    bool? paid,
    String? lastPaidPeriod,
    int? notificationId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Bill(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      dueDay: dueDay ?? this.dueDay,
      isRecurring: isRecurring ?? this.isRecurring,
      paid: paid ?? this.paid,
      lastPaidPeriod: lastPaidPeriod ?? this.lastPaidPeriod,
      notificationId: notificationId ?? this.notificationId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Simple date-only value for comparison without time components.
class DateOnly implements Comparable<DateOnly> {
  final int year;
  final int month;
  final int day;

  const DateOnly(this.year, this.month, this.day);

  factory DateOnly.today() {
    final now = DateTime.now();
    return DateOnly(now.year, now.month, now.day);
  }

  factory DateOnly.from(DateTime dt) => DateOnly(dt.year, dt.month, dt.day);

  bool isAfter(DateOnly other) {
    if (year != other.year) return year > other.year;
    if (month != other.month) return month > other.month;
    return day > other.day;
  }

  bool isBefore(DateOnly other) {
    if (year != other.year) return year < other.year;
    if (month != other.month) return month < other.month;
    return day < other.day;
  }

  int difference(DateOnly other) {
    return toDateTime().difference(other.toDateTime()).inDays;
  }

  int daysSince(DateOnly other) {
    return other.toDateTime().difference(toDateTime()).inDays;
  }

  DateTime toDateTime() => DateTime(year, month, day);

  @override
  int compareTo(DateOnly other) {
    if (isAfter(other)) return 1;
    if (isBefore(other)) return -1;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is DateOnly && year == other.year && month == other.month && day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);
}
