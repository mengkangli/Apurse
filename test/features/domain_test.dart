import 'package:flutter_test/flutter_test.dart';
import 'package:apurse/core/database/money.dart';
import 'package:apurse/features/ai_scan/data/ai_scan_service.dart';
import 'package:apurse/features/transaction/domain/transaction.dart';
import 'package:apurse/features/category/domain/category.dart';
import 'package:apurse/features/bill/domain/bill.dart';
import 'package:apurse/features/budget/domain/budget.dart';
import 'package:apurse/features/account/domain/account.dart';
import 'package:apurse/shared/utils/month_utils.dart';

void main() {
  // ─── Money ───
  group('Money', () {
    test('cents conversion rounds instead of truncating', () {
      expect(toCents(24.61), 2461); // 24.61 * 100 == 2460.9999999999995
      expect(toCents(0.1 + 0.2), 30);
      expect(fromCents(2461), 24.61);
      expect(toCentsOrNull(null), isNull);
      expect(fromCentsOrNull(null), isNull);
    });
  });

  // ─── Transaction model ───
  group('Transaction', () {
    test('fromJson / toJson round-trip with amount in cents', () {
      final json = {
        'id': 'tx001',
        'amount': 9990,
        'type': 'expense',
        'category_id': 'ec001',
        'date': '2026-05-30',
        'note': '午餐',
        'account_id': 'acc001',
        'created_at': '2026-05-30T12:00:00',
        'updated_at': '2026-05-30T12:00:00',
      };
      final tx = Transaction.fromJson(json);
      expect(tx.id, 'tx001');
      expect(tx.amount, 99.9);
      expect(tx.isIncome, false);
      expect(tx.categoryId, 'ec001');
      expect(tx.date, DateTime(2026, 5, 30));
      expect(tx.note, '午餐');
      expect(tx.accountId, 'acc001');

      final back = tx.toJson();
      expect(back['amount'], 9990);
      expect(back['amount'], isA<int>());
      expect(back['type'], 'expense');
      expect(back['category_id'], 'ec001');
      expect(back['date'], '2026-05-30');
    });

    test('isIncome returns true for income type', () {
      final tx = Transaction(
        id: 't1',
        amount: 5000,
        type: 'income',
        categoryId: 'ic001',
        date: DateTime(2026, 5, 30),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(tx.isIncome, true);
    });
  });

  // ─── Category model ───
  group('Category', () {
    test('fromJson / toJson round-trip', () {
      final json = {
        'id': 'ec001',
        'name': '餐饮',
        'icon_code': 0xe561,
        'color_value': 0xFFD4914A,
        'type': 'expense',
        'sort_order': 0,
        'is_default': 1,
        'created_at': '2026-01-01T00:00:00',
        'updated_at': '2026-01-01T00:00:00',
      };
      final cat = Category.fromJson(json);
      expect(cat.id, 'ec001');
      expect(cat.name, '餐饮');
      expect(cat.iconCodePoint, 0xe561);
      expect(cat.colorValue, 0xFFD4914A);
      expect(cat.type, 'expense');
      expect(cat.sortOrder, 0);

      final back = cat.toJson();
      expect(back['name'], '餐饮');
      expect(back['type'], 'expense');
    });
  });

  // ─── Account model ───
  group('Account', () {
    test('fromJson parses all fields, initial balance in cents', () {
      final json = {
        'id': 'acc001',
        'name': '微信零钱',
        'type': 'wechat',
        'initial_balance': 123456,
        'icon_code': 0xe3d9,
        'color_value': 0xFF07C160,
        'sort_order': 0,
        'created_at': '2026-01-01T00:00:00',
        'updated_at': '2026-01-01T00:00:00',
      };
      final acc = Account.fromJson(json);
      expect(acc.id, 'acc001');
      expect(acc.name, '微信零钱');
      expect(acc.type, 'wechat');
      expect(acc.initialBalance, 1234.56);
      expect(acc.iconCodePoint, 0xe3d9);
      expect(acc.colorValue, 0xFF07C160);
      expect(acc.toJson()['initial_balance'], 123456);
    });

    test('typeLabel returns Chinese label', () {
      Account make(String type) => Account(id: 'a', name: 'n', type: type, iconCodePoint: 0, colorValue: 0, sortOrder: 0, createdAt: DateTime.now(), updatedAt: DateTime.now());
      expect(make('wechat').typeLabel, '微信');
      expect(make('alipay').typeLabel, '支付宝');
      expect(make('cash').typeLabel, '现金');
      expect(make('unknown').typeLabel, '其他');
    });
  });

  // ─── Bill model ───
  group('Bill', () {
    Bill bill({bool recurring = true, bool paid = false, String? period}) => Bill(
          id: 'b001',
          name: '房租',
          amount: 3000,
          categoryId: 'ec008',
          dueDay: 15,
          isRecurring: recurring,
          paid: paid,
          lastPaidPeriod: period,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('fromJson parses boolean fields as int and amount as cents', () {
      final json = {
        'id': 'b001',
        'name': '房租',
        'amount': 300000,
        'category_id': 'ec008',
        'due_day': 1,
        'is_recurring': 1,
        'is_paid': 0,
        'last_paid_period': null,
        'notification_id': null,
        'created_at': '2026-01-01T00:00:00',
        'updated_at': '2026-01-01T00:00:00',
      };
      final b = Bill.fromJson(json);
      expect(b.name, '房租');
      expect(b.amount, 3000.0);
      expect(b.dueDay, 1);
      expect(b.isRecurring, true);
      expect(b.isPaid, false);
    });

    test('a recurring bill paid in October is unpaid again in November', () {
      final b = bill(paid: true, period: '2026-10');
      expect(b.isPaidOn(DateTime(2026, 10, 20)), true);
      expect(b.isPaidOn(DateTime(2026, 11, 1)), false);
    });

    test('a one-off bill stays paid', () {
      final b = bill(recurring: false, paid: true, period: '2026-10');
      expect(b.isPaidOn(DateTime(2026, 12, 1)), true);
    });

    test('currentDueDate returns correct date', () {
      final due = bill().currentDueDate;
      expect(due.day, 15);
      final now = DateTime.now();
      expect(due.difference(DateTime(now.year, now.month, 1)).inDays >= 0, true);
    });
  });

  // ─── Budget model ───
  group('Budget', () {
    test('fromJson / toJson round-trip; spent is not stored', () {
      final json = {
        'id': 'b001',
        'category_id': 'ec001',
        'amount': 200000,
        'month': 5,
        'year': 2026,
        'created_at': '2026-05-01T00:00:00',
        'updated_at': '2026-05-30T00:00:00',
      };
      final budget = Budget.fromJson(json).copyWith(spent: 500);
      expect(budget.amount, 2000.0);
      expect(budget.month, 5);
      expect(budget.year, 2026);
      expect(budget.percentage, 25.0);
      expect(budget.remaining, 1500.0);

      final back = budget.toJson();
      expect(back['amount'], 200000);
      expect(back.containsKey('spent'), false);
    });

    test('percentage handles zero amount', () {
      final budget = Budget(
        id: 'b1',
        categoryId: 'ec001',
        amount: 0,
        month: 5,
        year: 2026,
        spent: 100,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(budget.percentage, 0.0);
    });
  });

  // ─── Month helpers ───
  group('month_utils', () {
    test('monthKey and monthDateRange', () {
      expect(monthKey(DateTime(2026, 3, 9)), '2026-03');
      expect(monthDateRange(2026, 2), ('2026-02-01', '2026-02-28'));
      expect(monthDateRange(2028, 2), ('2028-02-01', '2028-02-29'));
      expect(monthDateRange(2026, 12), ('2026-12-01', '2026-12-31'));
    });
  });

  // ─── AI scan parsing ───
  group('AiScanResult', () {
    test('negative receipt amount becomes a positive expense', () {
      final r = AiScanResult.fromJson({
        'amount': -24.61,
        'type': 'expense',
        'category': '餐饮',
        'date': '2026-05-25',
        'note': ' 切果达 ',
      });
      expect(r.amount, 24.61);
      expect(r.type, 'expense');
      expect(r.date, DateTime(2026, 5, 25));
      expect(r.note, '切果达');
    });

    test('string amounts and Chinese type labels are understood', () {
      final r = AiScanResult.fromJson({'amount': '¥1,280.50', 'type': '收入'});
      expect(r.amount, 1280.5);
      expect(r.type, 'income');
    });

    test('future dates guessed by the model are dropped', () {
      final r = AiScanResult.fromJson({'amount': 10, 'date': '2099-01-01'});
      expect(r.date, isNull);
    });

    test('prompt lists the user\'s own categories', () {
      final prompt = AiScanService.buildPrompt(
        text: 'x',
        expenseCategories: ['餐饮', '咖啡'],
        incomeCategories: ['工资'],
      );
      expect(prompt, contains('餐饮、咖啡'));
      expect(prompt, contains('工资'));
    });
  });
}
