import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radius.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_icon_data.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/account.dart';
import '../domain/account_repository.dart';
import 'add_account_screen.dart';

class AccountListScreen extends StatefulWidget {
  const AccountListScreen({super.key});

  @override
  State<AccountListScreen> createState() => _AccountListScreenState();
}

class _AccountListScreenState extends State<AccountListScreen> {
  List<AccountBalance> _accounts = [];
  bool _loading = true;

  static final _money = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final accounts = await AccountRepository().getAllWithBalances();
      if (mounted) {
        setState(() {
          _accounts = accounts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open({Account? account}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddAccountScreen(account: account)),
    );
    if (result == true) _load();
  }

  String _format(double v) => '${v < 0 ? '-' : ''}¥${_money.format(v.abs())}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账户'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '添加账户',
            onPressed: () => _open(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
              ? EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: '暂无账户',
                  subtitle: '添加微信、支付宝或银行卡，记账时选择账户即可自动算余额',
                  actionLabel: '添加账户',
                  onAction: () => _open(),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
                    children: [
                      _TotalCard(
                        total: _accounts.fold(0.0, (s, a) => s + a.balance),
                        count: _accounts.length,
                        format: _format,
                      ),
                      AppSpacing.gapLg,
                      for (final item in _accounts) ...[
                        _AccountTile(
                          item: item,
                          format: _format,
                          onTap: () => _open(account: item.account),
                        ),
                        AppSpacing.gapSm,
                      ],
                      AppSpacing.gapSm,
                      Text(
                        '余额 = 初始余额 + 该账户的收入 − 支出',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final double total;
  final int count;
  final String Function(double) format;

  const _TotalCard({
    required this.total,
    required this.count,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.secondary, Color(0xFF3D5A73)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.allXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '总资产 · $count 个账户',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white.withValues(alpha: AppColors.opacityProminent),
              letterSpacing: 1.2,
            ),
          ),
          AppSpacing.gapSm,
          Text(
            format(total),
            style: AppTypography.displayLarge.copyWith(
              color: Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final AccountBalance item;
  final String Function(double) format;
  final VoidCallback onTap;

  const _AccountTile({
    required this.item,
    required this.format,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final account = item.account;
    final accent = Color(account.colorValue);
    return Material(
      color: cs.surface,
      borderRadius: AppRadius.allLg,
      child: InkWell(
        borderRadius: AppRadius.allLg,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.allLg,
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: AppColors.opacityMuted),
                  borderRadius: AppRadius.allMd,
                ),
                child: Icon(AppIconData.fromCodePoint(account.iconCodePoint),
                    color: accent, size: 22),
              ),
              AppSpacing.gapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.name, style: AppTypography.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      account.typeLabel,
                      style: AppTypography.bodySmall
                          .copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                format(item.balance),
                style: AppTypography.numericMedium.copyWith(
                  color: item.balance < 0 ? AppColors.expense : cs.onSurface,
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant
                      .withValues(alpha: AppColors.opacitySecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
