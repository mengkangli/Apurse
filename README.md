# Apurse

<img width="3738" height="874" alt="streamer" src="https://github.com/user-attachments/assets/d07b76f3-7303-4579-834a-40a52a8b94f7" />

A personal finance tracker (记账 app) built with Flutter. Everything is stored
on the device; the only network call is the optional AI receipt scan.

## Features

- **Record income and expenses** with a keypad-first entry screen, categories,
  dates, notes and an account (WeChat, Alipay, bank card, cash…). Tap any record
  to edit it.
- **AI receipt scan** — take or pick a screenshot of a payment receipt; ML Kit
  reads the text on-device, DeepSeek turns it into amount / category / date /
  note, and you confirm on the normal entry screen before it's saved. Images can
  also be shared into the app from other apps.
- **Accounts** — each account's balance is its opening balance plus the income
  and expenses recorded against it.
- **Monthly budgets** per category, with progress computed from that month's
  spending (including spending recorded before the budget was created).
- **Recurring bills** with due dates; marking one paid covers the current month
  and it comes back next month.
- **Statistics** — category breakdown and daily trend charts.
- **CSV export** (opens correctly in Excel), light / dark theme.

## Architecture

```
lib/
  core/        database, router, theme, shared widgets
  features/    one folder per feature: domain/ (models, repositories) + presentation/ (screens)
  shared/      Riverpod providers and small utilities used across features
tools/         dev-only scripts (see below)
test/          unit, repository and migration tests
```

- **State**: Riverpod (`FutureProvider`s keyed on the selected month; a
  `transactionChangeProvider` counter refreshes dependent views after writes).
- **Navigation**: go_router with a `StatefulShellRoute` for the four tabs.
- **Storage**: `DatabaseHelper` is the single data API with three backends —
  sqflite on mobile/desktop, JSON tables in SharedPreferences on web, and a
  debug-only HTTP dev server.

### Data model (schema v5)

| Table | Notes |
| --- | --- |
| `categories` | 27 defaults (`is_default = 1`, can't be deleted) plus user categories. Deleting a user category moves its records and bills to the default 「其他」 category of the same type. |
| `transactions` | `amount` in **integer cents**; `category_id` → categories, `account_id` → accounts (`ON DELETE SET NULL`). |
| `accounts` | `initial_balance` in cents; the current balance is derived. |
| `budgets` | One per category per month (`UNIQUE(category_id, month, year)`); amount in cents. Spending is summed from transactions when budgets load, never stored. |
| `bills` | `last_paid_period` (`yyyy-MM`) decides whether a recurring bill is paid this month. |

Money is stored as integer cents so totals are exact; models expose `double`
yuan and convert in `toJson` / `fromJson` (`lib/core/database/money.dart`).
Foreign keys are enforced (`PRAGMA foreign_keys = ON`). The v4 → v5 migration
in `database_helper.dart` rebuilds the money tables, converts amounts, and
re-homes records whose category had been deleted.

## Getting started

```bash
flutter pub get
flutter run
```

To use AI scan, get a key at <https://platform.deepseek.com/api_keys> and enter
it under **我的 → 设置 → DeepSeek API Key**. It's kept in the platform keystore
(Keychain / Android Keystore / Windows Credential Manager).

### Tests

```bash
flutter test
```

Repository and migration tests run against a real SQLite database through
`sqflite_common_ffi`.

> **Windows**: keep the project in a short path (e.g. `C:\dev\apurse`). Flutter's
> generated iOS plugin package and native-asset builds exceed the 260-character
> path limit in deeply nested folders.

### Dev tools

- `tools/dev_server.py` — local Flask server backing the "remote" storage mode
  (debug builds only, under 设置 → 开发调试). Listens on 127.0.0.1, no auth;
  don't expose it. `pip install flask && python tools/dev_server.py`
- `tools/try_prompt.py` — run the AI-scan prompt against DeepSeek from the
  command line. Reads `DEEPSEEK_API_KEY` from `.env` (copy `.env.example`).
  Don't commit real receipts — they contain order numbers and payment details.
