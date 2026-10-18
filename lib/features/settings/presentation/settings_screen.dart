import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_radius.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/storage_config.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/providers/theme_mode_provider.dart';
import '../../ai_scan/data/ai_scan_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  StorageMode _mode = StorageMode.local;
  bool _hasApiKey = false;

  @override
  void initState() {
    super.initState();
    _loadMode();
    _loadApiKeyStatus();
  }

  Future<void> _loadMode() async {
    final mode = await StorageConfig.getMode();
    if (mounted) setState(() => _mode = mode);
  }

  Future<void> _loadApiKeyStatus() async {
    final key = await AiScanService.instance.getSavedApiKey();
    if (mounted) setState(() => _hasApiKey = key != null && key.isNotEmpty);
  }

  Future<void> _switchMode(StorageMode mode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换数据存储'),
        content: Text(
          mode == StorageMode.remote
              ? '切换到开发服务器？\n\n请先在电脑上运行 tools/dev_server.py。'
              : '切换到本地存储？\n\n数据将保存在当前设备。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await DatabaseHelper.instance.switchMode(mode);
    if (mounted) {
      setState(() => _mode = mode);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mode == StorageMode.remote ? '已切换到远程数据库' : '已切换到本地存储',
            ),
          ),
        );
      }
    }
  }

  Future<void> _configureApiKey() async {
    final savedKey = await AiScanService.instance.getSavedApiKey();
    if (!mounted) return;

    final controller = TextEditingController(text: savedKey ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('DeepSeek API Key'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'sk-...',
            helperText: '用于智能扫描收据，加密保存在本机',
          ),
        ),
        actions: [
          if (savedKey != null && savedKey.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('清除'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null) return;
    if (result.isEmpty) {
      await AiScanService.instance.clearApiKey();
    } else {
      await AiScanService.instance.saveApiKey(result);
    }
    await _loadApiKeyStatus();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.isEmpty ? '已清除 API Key' : '已保存 API Key')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          const _SectionLabel('外观'),
          AppSpacing.gapSm,
          _ThemeModeCard(
            value: themeMode,
            onChanged: (mode) =>
                ref.read(themeModeProvider.notifier).setMode(mode),
          ),
          // The dev server has no auth, so this switch exists only in debug
          // builds (see StorageConfig.remoteAvailable).
          if (StorageConfig.remoteAvailable) ...[
            AppSpacing.gapXl,
            const _SectionLabel('开发调试'),
            AppSpacing.gapSm,
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: _mode == StorageMode.remote
                      ? Icons.cloud_done_outlined
                      : Icons.phone_android_outlined,
                  iconColor: _mode == StorageMode.remote
                      ? AppColors.expense
                      : AppColors.income,
                  title: '数据库',
                  subtitle: _mode == StorageMode.remote
                      ? '开发服务器（仅调试版）'
                      : '本地存储',
                  onTap: () => _switchMode(
                    _mode == StorageMode.remote
                        ? StorageMode.local
                        : StorageMode.remote,
                  ),
                ),
              ],
            ),
          ],
          AppSpacing.gapXl,
          const _SectionLabel('AI 配置'),
          AppSpacing.gapSm,
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.key_rounded,
                iconColor: AppColors.primary,
                title: 'DeepSeek API Key',
                subtitle: _hasApiKey ? '已配置，用于智能扫描收据' : '未配置，AI 扫描需要先填写',
                onTap: _configureApiKey,
              ),
            ],
          ),
          AppSpacing.gapXl,
          const _SectionLabel('关于'),
          AppSpacing.gapSm,
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                iconColor: colorScheme.primary,
                title: '关于 Apurse',
                subtitle: '版本 1.1.0',
              ),
              const _SettingsTile(
                icon: Icons.favorite_rounded,
                iconColor: AppColors.expense,
                title: '用心记账，好好生活',
                subtitle: 'Made with love',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeModeCard extends StatelessWidget {
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeModeCard({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.allLg,
      ),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_rounded),
            label: Text('跟随系统'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_rounded),
            label: Text('浅色'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_rounded),
            label: Text('深色'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
        showSelectedIcon: false,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: Text(
        text,
        style: AppTypography.labelSmall.copyWith(
          color: cs.onSurfaceVariant,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: AppRadius.allLg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 64),
                child: Divider(height: 1, color: cs.outlineVariant),
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: AppColors.opacityMuted),
                borderRadius: AppRadius.allSm,
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            AppSpacing.gapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.titleSmall),
                  AppSpacing.gapXs,
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: cs.onSurfaceVariant
                    .withValues(alpha: AppColors.opacitySecondary),
              ),
          ],
        ),
      ),
    );
  }
}
