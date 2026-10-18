import 'package:apurse/core/database/database_helper.dart';
import 'package:apurse/features/account/domain/account_repository.dart';
import 'package:apurse/features/bill/domain/bill.dart';
import 'package:apurse/features/bill/domain/bill_repository.dart';
import 'package:apurse/features/budget/domain/budget_repository.dart';
import 'package:apurse/features/category/domain/category.dart';
import 'package:apurse/features/category/domain/category_repository.dart';
import 'package:apurse/features/statistics/presentation/statistics_screen.dart';
import 'package:apurse/features/transaction/domain/transaction.dart';
import 'package:apurse/features/transaction/domain/transaction_repository.dart';
import 'package:apurse/shared/providers/selected_month_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

void main() {
  final txRepo = TransactionRepository();
  final budgetRepo = BudgetRepository();
  final accountRepo = AccountRepository();
  final categoryRepo = CategoryRepository();
  final billRepo = BillRepository();
  var seq = 0;

  Future<Transaction> addTx(
    double amount, {
    String type = 'expense',
    String categoryId = 'ec001',
    DateTime? date,
    String? accountId,
  }) async {
    final now = DateTime.now();
    final tx = Transaction(
      id: 'tx${seq++}',
      amount: amount,
      type: type,
      categoryId: categoryId,
      date: date ?? DateTime(2026, 10, 5),
      accountId: accountId,
      createdAt: now,
      updatedAt: now,
    );
    await txRepo.insert(tx);
    return tx;
  }

  setUp(() async {
    await useFreshDatabase();
  });

  tearDown(() async {
    await DatabaseHelper.instance.resetForTesting();
  });

  test('fresh install seeds categories (incl. both 其他) and accounts', () async {
    final cats = await categoryRepo.getAll();
    expect(cats.length, 27);
    expect((await categoryRepo.fallbackFor('expense'))?.name, '其他');
    expect((await categoryRepo.fallbackFor('income'))?.name, '其他');
    expect((await accountRepo.getAll()).map((a) => a.id), ['acc001', 'acc002', 'acc003']);
  });

  test('amounts are stored as integer cents and sum exactly', () async {
    await addTx(0.1);
    await addTx(0.2);
    expect(await txRepo.sumByMonth(2026, 10, 'expense'), 0.3);

    final rows = await DatabaseHelper.instance
        .rawQuery('SELECT amount, typeof(amount) AS t FROM transactions ORDER BY amount');
    expect(rows.map((r) => r['amount']), [10, 20]);
    expect(rows.map((r) => r['t']), ['integer', 'integer']);
  });

  group('budgets', () {
    test('a budget created mid-month counts earlier spending', () async {
      await addTx(120);
      await addTx(30.5);
      await addTx(99, categoryId: 'ec002'); // other category
      await addTx(500, date: DateTime(2026, 9, 30)); // other month

      await budgetRepo.upsert(categoryId: 'ec001', year: 2026, month: 10, amount: 200);
      final budgets = await budgetRepo.getByMonth(2026, 10);
      expect(budgets.single.spent, 150.5);
      expect(budgets.single.remaining, 49.5);
    });

    test('spent follows edits and deletes without any recalculation step', () async {
      await budgetRepo.upsert(categoryId: 'ec001', year: 2026, month: 10, amount: 100);
      final tx = await addTx(40);
      await txRepo.update(tx.copyWith(categoryId: 'ec002'));
      expect((await budgetRepo.getByMonth(2026, 10)).single.spent, 0);

      await txRepo.update(tx.copyWith(categoryId: 'ec001', amount: 70));
      expect((await budgetRepo.getByMonth(2026, 10)).single.spent, 70);

      await txRepo.delete(tx.id);
      expect((await budgetRepo.getByMonth(2026, 10)).single.spent, 0);
    });

    test('saving a second budget for the same category/month updates it', () async {
      expect(await budgetRepo.upsert(categoryId: 'ec001', year: 2026, month: 10, amount: 100), true);
      expect(await budgetRepo.upsert(categoryId: 'ec001', year: 2026, month: 10, amount: 300), false);
      final budgets = await budgetRepo.getByMonth(2026, 10);
      expect(budgets.length, 1);
      expect(budgets.single.amount, 300);
    });
  });

  group('bills', () {
    test('a recurring bill marked paid is unpaid again next month', () async {
      final now = DateTime.now();
      await billRepo.insert(Bill(
        id: 'rent',
        name: '房租',
        amount: 3000,
        categoryId: 'ec008',
        dueDay: 1,
        isRecurring: true,
        paid: false,
        createdAt: now,
        updatedAt: now,
      ));
      await billRepo.markPaid('rent', date: DateTime(2026, 10, 2));
      final bill = (await billRepo.getAll()).single;
      expect(bill.lastPaidPeriod, '2026-10');
      expect(bill.isPaidOn(DateTime(2026, 10, 31)), true);
      expect(bill.isPaidOn(DateTime(2026, 11, 1)), false);

      await billRepo.markUnpaid('rent');
      expect((await billRepo.getAll()).single.isPaidOn(DateTime(2026, 10, 31)), false);
    });
  });

  group('accounts', () {
    test('balance = initial balance + income − expenses on the account', () async {
      final acc = (await accountRepo.getById('acc001'))!;
      await accountRepo.update(acc.copyWith(initialBalance: 100));
      await addTx(5000, type: 'income', categoryId: 'ic001', accountId: 'acc001');
      await addTx(24.61, accountId: 'acc001');
      await addTx(10, accountId: 'acc002');
      await addTx(999); // no account

      final balances = {
        for (final b in await accountRepo.getAllWithBalances()) b.account.id: b.balance,
      };
      expect(balances['acc001'], 5075.39);
      expect(balances['acc002'], -10);
      expect(balances['acc003'], 0);
    });

    test('deleting an account keeps its records, unlinked', () async {
      final tx = await addTx(10, accountId: 'acc002');
      await accountRepo.delete('acc002');
      final kept = await txRepo.getById(tx.id);
      expect(kept, isNotNull);
      expect(kept!.accountId, isNull);
    });
  });

  group('categories', () {
    Future<Category> addCustom() async {
      final now = DateTime.now();
      final cat = Category(
        id: 'custom1',
        name: '咖啡',
        iconCodePoint: 0,
        colorValue: 0xFF795548,
        type: 'expense',
        sortOrder: 99,
        isDefault: false,
        createdAt: now,
        updatedAt: now,
      );
      await categoryRepo.insert(cat);
      return cat;
    }

    test('deleting a category moves its records and bills to 其他', () async {
      final coffee = await addCustom();
      await addTx(18, categoryId: coffee.id);
      await addTx(22, categoryId: coffee.id);
      await budgetRepo.upsert(categoryId: coffee.id, year: 2026, month: 10, amount: 300);
      final now = DateTime.now();
      await billRepo.insert(Bill(
        id: 'sub', name: '咖啡月卡', amount: 99, categoryId: coffee.id, dueDay: 3,
        isRecurring: true, paid: false, createdAt: now, updatedAt: now,
      ));

      expect(await txRepo.countByCategory(coffee.id), 2);
      expect(await categoryRepo.deleteAndReassign(coffee), 2);

      expect(await txRepo.countByCategory(coffee.id), 0);
      expect(await txRepo.countByCategory('ec016'), 2);
      expect((await billRepo.getAll()).single.categoryId, 'ec016');
      expect(await budgetRepo.getByMonth(2026, 10), isEmpty);
      expect((await categoryRepo.getAll()).any((c) => c.id == coffee.id), false);
    });

    test('statistics breakdown still adds up to the month total', () async {
      final coffee = await addCustom();
      await addTx(18, categoryId: coffee.id);
      await addTx(50);
      await categoryRepo.deleteAndReassign(coffee);

      final container = ProviderContainer(overrides: [
        selectedMonthProvider.overrideWith((ref) => DateTime(2026, 10)),
      ]);
      addTearDown(container.dispose);
      final breakdown = await container.read(categoryBreakdownProvider.future);
      final total = breakdown.fold<double>(0, (s, b) => s + b.amount);
      expect(total, await txRepo.sumByMonth(2026, 10, 'expense'));
      expect(total, 68);
    });

    test('foreign keys reject records pointing at a missing category', () async {
      await expectLater(addTx(1, categoryId: 'does-not-exist'), throwsA(anything));
    });
  });
}
