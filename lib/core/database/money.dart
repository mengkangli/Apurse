/// Money is stored as integer cents (分) so that sums in SQL are exact.
///
/// Domain models keep `double` yuan for display and input; convert only at
/// the row boundary (`toJson` / `fromJson`) and when reading SQL aggregates.
int toCents(double yuan) => (yuan * 100).round();

double fromCents(num cents) => cents / 100;

/// Nullable variant for optional amounts such as an account's opening balance.
int? toCentsOrNull(double? yuan) => yuan == null ? null : toCents(yuan);

double? fromCentsOrNull(num? cents) => cents == null ? null : fromCents(cents);
