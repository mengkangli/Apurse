import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_spacing.dart';
import '../../account/domain/account_repository.dart';
import '../../transaction/domain/transaction_repository.dart';
import '../../category/domain/category_repository.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  DateTime _startDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _endDate = DateTime.now();
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('导出数据'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date range
            Text('导出范围', style: Theme.of(context).textTheme.titleMedium),
            AppSpacing.gapMd,
            Row(
              children: [
                Expanded(
                  child: _dateTile(
                    context,
                    '开始日期',
                    _startDate,
                    (d) => setState(() => _startDate = d),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Text('—', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ),
                Expanded(
                  child: _dateTile(
                    context,
                    '结束日期',
                    _endDate,
                    (d) => setState(() => _endDate = d),
                  ),
                ),
              ],
            ),
            AppSpacing.gapXl,

            // Export button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _exporting ? null : _doExport,
                child: _exporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('导出'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateTile(
    BuildContext context,
    String label,
    DateTime date,
    ValueChanged<DateTime> onPicked,
  ) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            AppSpacing.gapXs,
            Text(
              DateFormat('yyyy/MM/dd').format(date),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }

  /// Spreadsheet apps run cells starting with = + - @ as formulas; a note
  /// like "=HYPERLINK(...)" must stay text.
  static String _cell(String text) =>
      RegExp(r'^[=+\-@\t\r]').hasMatch(text) ? "'$text" : text;

  Future<void> _doExport() async {
    if (_startDate.isAfter(_endDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开始日期不能晚于结束日期')),
      );
      return;
    }

    setState(() => _exporting = true);

    try {
      final txRepo = TransactionRepository();
      final catRepo = CategoryRepository();
      final all = await txRepo.getAll();
      final categories = await catRepo.getAll();
      final accounts = await AccountRepository().getAll();

      final filtered = all.where((tx) {
        return !tx.date.isBefore(_startDate) && !tx.date.isAfter(_endDate);
      }).toList();

      if (filtered.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('所选日期范围内没有数据')),
          );
        }
        return;
      }

      filtered.sort((a, b) => b.date.compareTo(a.date));

      final catMap = <String, String>{};
      for (final cat in categories) {
        catMap[cat.id] = cat.name;
      }

      final accountMap = {for (final a in accounts) a.id: a.name};

      final rows = <List<String>>[
        ['日期', '类型', '分类', '金额', '账户', '备注'],
        ...filtered.map((tx) => [
              DateFormat('yyyy-MM-dd').format(tx.date),
              tx.isIncome ? '收入' : '支出',
              _cell(catMap[tx.categoryId] ?? '未知'),
              tx.amount.toStringAsFixed(2),
              _cell(accountMap[tx.accountId] ?? ''),
              _cell(tx.note ?? ''),
            ]),
      ];

      // BOM so Excel opens the UTF-8 file with Chinese text intact.
      final csv = '﻿${const ListToCsvConverter().convert(rows)}';

      final dir = await getTemporaryDirectory();
      final timeStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/apurse_export_$timeStr.csv');
      await file.writeAsString(csv);

      try {
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Apurse账单导出 $timeStr',
        );
      } catch (_) {
        // User cancelled share — file was written successfully, not an error
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
