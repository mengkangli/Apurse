import '../../../core/database/money.dart';

class Transaction {
  final String id;
  final double amount;
  final String type; // 'income' | 'expense'
  final String categoryId;
  final DateTime date;
  final String? note;
  final String? accountId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Transaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.categoryId,
    required this.date,
    this.note,
    this.accountId,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isIncome => type == 'income';

  /// Database row. `amount` is stored in integer cents.
  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': toCents(amount),
        'type': type,
        'category_id': categoryId,
        'date': date.toIso8601String().substring(0, 10),
        'note': note,
        'account_id': accountId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        id: json['id'] as String,
        amount: fromCents(json['amount'] as num),
        type: json['type'] as String,
        categoryId: json['category_id'] as String,
        date: DateTime.parse(json['date'] as String),
        note: json['note'] as String?,
        accountId: json['account_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Transaction copyWith({
    String? id,
    double? amount,
    String? type,
    String? categoryId,
    DateTime? date,
    String? note,
    String? accountId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      note: note ?? this.note,
      accountId: accountId ?? this.accountId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Pre-filled values for a new record, e.g. from AI scan or a quick-add
/// category chip. The add screen shows them for the user to confirm.
class TransactionDraft {
  final double? amount;
  final String? type;
  final String? categoryId;
  final DateTime? date;
  final String? note;

  const TransactionDraft({
    this.amount,
    this.type,
    this.categoryId,
    this.date,
    this.note,
  });
}
