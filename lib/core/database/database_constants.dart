class DatabaseConstants {
  DatabaseConstants._();

  static const String databaseName = 'apurse.db';

  /// v5: money as integer cents, budgets.spent dropped (derived from
  /// transactions), bills.last_paid_period, accounts.initial_balance,
  /// foreign keys enforced.
  static const int databaseVersion = 5;

  static const String tableCategories = 'categories';
  static const String tableTransactions = 'transactions';
  static const String tableBudgets = 'budgets';
  static const String tableBills = 'bills';
  static const String tableAccounts = 'accounts';

  /// Default "其他" categories. Records from a deleted category move here.
  static const String fallbackExpenseCategoryId = 'ec016';
  static const String fallbackIncomeCategoryId = 'ic009';

  // Common columns
  static const String colId = 'id';
  static const String colCreatedAt = 'created_at';
  static const String colUpdatedAt = 'updated_at';

  // Categories
  static const String colCatName = 'name';
  static const String colCatIconCode = 'icon_code';
  static const String colCatColorValue = 'color_value';
  static const String colCatType = 'type';
  static const String colCatSortOrder = 'sort_order';
  static const String colCatIsDefault = 'is_default';

  // Transactions
  static const String colTxAmount = 'amount';
  static const String colTxType = 'type';
  static const String colTxCategoryId = 'category_id';
  static const String colTxDate = 'date';
  static const String colTxNote = 'note';
  static const String colTxAccountId = 'account_id';

  // Accounts
  static const String colAccName = 'name';
  static const String colAccType = 'type';
  static const String colAccInitialBalance = 'initial_balance';
  static const String colAccIconCode = 'icon_code';
  static const String colAccColorValue = 'color_value';
  static const String colAccSortOrder = 'sort_order';

  // Budgets
  static const String colBudCategoryId = 'category_id';
  static const String colBudAmount = 'amount';
  static const String colBudMonth = 'month';
  static const String colBudYear = 'year';

  // Bills
  static const String colBillName = 'name';
  static const String colBillAmount = 'amount';
  static const String colBillCategoryId = 'category_id';
  static const String colBillDueDay = 'due_day';
  static const String colBillIsRecurring = 'is_recurring';
  static const String colBillIsPaid = 'is_paid';
  static const String colBillLastPaidPeriod = 'last_paid_period';
  static const String colBillNotificationId = 'notification_id';
}
