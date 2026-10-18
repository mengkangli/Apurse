import '../../../core/database/money.dart';

class Account {
  final String id;
  final String name;
  final String type; // 'bank_card' | 'wechat' | 'alipay' | 'cash' | 'other'

  /// Balance when the account was added. The current balance is this plus
  /// the account's income minus its expenses (see `AccountRepository`).
  final double? initialBalance;
  final int iconCodePoint;
  final int colorValue;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.initialBalance,
    required this.iconCodePoint,
    required this.colorValue,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  String get typeLabel {
    return switch (type) {
      'bank_card' => '银行卡',
      'wechat' => '微信',
      'alipay' => '支付宝',
      'cash' => '现金',
      _ => '其他',
    };
  }

  /// Database row. `initial_balance` is stored in integer cents.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'initial_balance': toCentsOrNull(initialBalance),
        'icon_code': iconCodePoint,
        'color_value': colorValue,
        'sort_order': sortOrder,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        initialBalance: fromCentsOrNull(json['initial_balance'] as num?),
        iconCodePoint: json['icon_code'] as int,
        colorValue: json['color_value'] as int,
        sortOrder: json['sort_order'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Account copyWith({
    String? id,
    String? name,
    String? type,
    double? initialBalance,
    int? iconCodePoint,
    int? colorValue,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      initialBalance: initialBalance ?? this.initialBalance,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      colorValue: colorValue ?? this.colorValue,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// An account with its balance computed from transactions.
class AccountBalance {
  final Account account;
  final double balance;

  const AccountBalance({required this.account, required this.balance});
}
