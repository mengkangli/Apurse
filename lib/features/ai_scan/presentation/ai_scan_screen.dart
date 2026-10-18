import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../category/domain/category.dart';
import '../../category/domain/category_repository.dart';
import '../../transaction/domain/transaction.dart';
import '../../transaction/presentation/add_transaction_screen.dart';
import '../data/ai_scan_service.dart';

class AiScanScreen extends StatefulWidget {
  const AiScanScreen({super.key});

  @override
  State<AiScanScreen> createState() => _AiScanScreenState();
}

class _AiScanScreenState extends State<AiScanScreen> {
  final _manualTextController = TextEditingController();

  Uint8List? _imageBytes;
  String? _imagePath;
  AiScanResult? _scanResult;
  AiScanPipelineStep? _currentStep;
  bool _saving = false;
  String? _error;
  String? _apiKey;
  String _ocrText = '';
  bool _useManualText = false;

  /// The user's categories: sent to the model so it picks from them, and
  /// used to map its answer back to a category id.
  List<Category> _categories = const [];

  @override
  void initState() {
    super.initState();
    _loadApiKey();
    _loadCategories();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSharedImage());
  }

  Future<void> _loadCategories() async {
    final cats = await CategoryRepository().getAll();
    if (mounted) setState(() => _categories = cats);
  }

  List<String> _categoryNames(String type) =>
      _categories.where((c) => c.type == type).map((c) => c.name).toList();

  Future<AiScanResult> _parse(String text, String apiKey) {
    return AiScanService.instance.parseText(
      text: text,
      apiKey: apiKey,
      expenseCategories: _categoryNames('expense'),
      incomeCategories: _categoryNames('income'),
    );
  }

  /// The category the model picked, or null when it named none of ours.
  Category? _matchedCategory(AiScanResult result) => _categories
      .where((c) => c.type == result.type && c.name == result.categoryName)
      .firstOrNull;

  @override
  void dispose() {
    _manualTextController.dispose();
    super.dispose();
  }

  Future<void> _loadApiKey() async {
    final key = await AiScanService.instance.getSavedApiKey();
    if (mounted) setState(() => _apiKey = key?.trim());
  }

  Future<void> _openSettingsForApiKey() async {
    await context.push('/settings');
    if (mounted) await _loadApiKey();
  }

  void _loadSharedImage() {
    final extra = GoRouterState.of(context).extra;
    if (extra is String && extra.isNotEmpty) {
      _pickSharedImage(extra);
    }
  }

  Future<void> _pickSharedImage(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imagePath = filePath;
      _scanResult = null;
      _error = null;
      _ocrText = '';
      _useManualText = false;
    });
    await _runPipeline(bytes, filePath);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;

      final bytes = await picked.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _imagePath = picked.path;
        _scanResult = null;
        _error = null;
        _ocrText = '';
        _useManualText = false;
      });
      await _runPipeline(bytes, picked.path);
    } catch (e) {
      if (mounted) setState(() => _error = '无法获取图片：$e');
    }
  }

  Future<void> _runPipeline(Uint8List bytes, String filePath) async {
    setState(() {
      _currentStep = AiScanPipelineStep.recognizing;
      _error = null;
      _scanResult = null;
      _ocrText = '';
    });

    String ocrText;
    try {
      ocrText = await AiScanService.instance.recognizeText(
        bytes: bytes,
        filePath: filePath,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'OCR 识别失败：$e。请手动输入账单文字';
        _currentStep = null;
      });
      return;
    }

    if (!mounted) return;

    if (ocrText.isEmpty) {
      setState(() {
        _error = 'OCR 未能识别文字，请手动输入账单文字后点击解析';
        _currentStep = null;
      });
      return;
    }

    setState(() => _ocrText = ocrText);

    final apiKey = _apiKey?.trim() ?? '';
    if (apiKey.isEmpty) {
      setState(() {
        _error = 'OCR 已完成，请先在设置中配置 DeepSeek API Key';
        _currentStep = null;
      });
      return;
    }

    setState(() => _currentStep = AiScanPipelineStep.parsing);

    try {
      final result = await _parse(ocrText, apiKey);
      if (!mounted) return;
      setState(() {
        _scanResult = result;
        _currentStep = null;
        if (result.amount <= 0) {
          _error = '未能从文字中识别出有效金额，请检查后重试';
        }
      });
    } on AiScanException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _currentStep = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '解析失败，请检查网络后重试';
        _currentStep = null;
      });
    }
  }

  Future<void> _manualParse() async {
    final text = _manualTextController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请输入账单文字');
      return;
    }

    final apiKey = _apiKey?.trim() ?? '';
    if (apiKey.isEmpty) {
      setState(() => _error = '请先在设置中配置 DeepSeek API Key');
      return;
    }

    setState(() {
      _currentStep = AiScanPipelineStep.parsing;
      _error = null;
      _scanResult = null;
    });

    try {
      final result = await _parse(text, apiKey);
      if (!mounted) return;
      setState(() {
        _scanResult = result;
        _ocrText = text;
        _currentStep = null;
        if (result.amount <= 0) {
          _error = '未能从文字中识别出有效金额，请检查后重试';
        }
      });
    } on AiScanException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _currentStep = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '解析失败，请检查网络后重试';
        _currentStep = null;
      });
    }
  }

  /// Opens the add screen pre-filled with the scan so the user confirms (and
  /// can fix) amount, category, date and account before anything is saved.
  Future<void> _confirm() async {
    final result = _scanResult;
    if (result == null) return;
    setState(() => _saving = true);

    // Unmatched categories go to "其他" rather than silently to whatever
    // category happens to be first.
    final category = _matchedCategory(result) ??
        await CategoryRepository().fallbackFor(result.type);
    if (!mounted) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          draft: TransactionDraft(
            amount: result.amount > 0 ? result.amount : null,
            type: result.type,
            categoryId: category?.id,
            date: result.date,
            note: result.note,
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('智能记账')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildApiKeyBanner(colorScheme),
            AppSpacing.gapLg,
            if (_imageBytes == null) _buildImagePicker(colorScheme),
            if (_imageBytes != null) _buildImagePreview(),
            if (_currentStep == AiScanPipelineStep.recognizing) ...[
              AppSpacing.gapMd,
              const Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(height: 8),
                    Text('OCR 正在识别文字...', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
            if (_ocrText.isNotEmpty &&
                _currentStep != AiScanPipelineStep.recognizing) ...[
              AppSpacing.gapMd,
              _buildOcrTextCard(),
            ],
            if ((_ocrText.isEmpty &&
                    _currentStep != AiScanPipelineStep.recognizing &&
                    _imageBytes != null) ||
                _useManualText ||
                _imageBytes == null) ...[
              AppSpacing.gapMd,
              TextField(
                controller: _manualTextController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '输入账单上的文字内容...\n如：美团支付 付款金额 ¥24.61 2026-05-25',
                ),
              ),
              AppSpacing.gapSm,
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _manualParse,
                  child: const Text('解析文字'),
                ),
              ),
            ],
            if (_ocrText.isNotEmpty &&
                _currentStep == null &&
                !_useManualText &&
                _scanResult == null) ...[
              AppSpacing.gapSm,
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _useManualText = true),
                  child: const Text('OCR 不对？手动输入'),
                ),
              ),
            ],
            if (_currentStep == AiScanPipelineStep.parsing) ...[
              AppSpacing.gapXl,
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('AI 正在解析...'),
                  ],
                ),
              ),
            ],
            if (_error != null &&
                _currentStep != AiScanPipelineStep.parsing) ...[
              AppSpacing.gapMd,
              _buildErrorCard(),
            ],
            if (_scanResult != null && _currentStep == null) ...[
              AppSpacing.gapXl,
              _buildResultCard(colorScheme),
              AppSpacing.gapXl,
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _confirm,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('核对并记账'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeyBanner(ColorScheme colorScheme) {
    final configured = _apiKey != null && _apiKey!.isNotEmpty;
    final accent = configured ? AppColors.income : AppColors.expense;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(
            configured ? Icons.check_circle_outline_rounded : Icons.key_rounded,
            color: accent,
            size: 20,
          ),
          AppSpacing.gapSm,
          Expanded(
            child: Text(
              configured ? 'DeepSeek API Key 已配置' : '请先配置 DeepSeek API Key',
              style: TextStyle(color: colorScheme.onSurface),
            ),
          ),
          TextButton(
            onPressed: _openSettingsForApiKey,
            child: Text(configured ? '管理' : '去设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker(ColorScheme colorScheme) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: colorScheme.outlineVariant, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 48,
            color: colorScheme.primary.withValues(alpha: 0.4),
          ),
          AppSpacing.gapMd,
          Text(
            '拍照或选择图片',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          AppSpacing.gapLg,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: _ImageSourceButton(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: Icons.camera_alt_rounded,
                  label: '拍照',
                ),
              ),
              AppSpacing.gapMd,
              Flexible(
                child: _ImageSourceButton(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: Icons.photo_library_rounded,
                  label: '相册',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: Image.file(
            File(_imagePath!),
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            cacheWidth: 512,
            cacheHeight: 512,
          ),
        ),
        AppSpacing.gapSm,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_rounded, size: 16),
              label: const Text('重拍'),
            ),
            TextButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_rounded, size: 16),
              label: const Text('重选'),
            ),
            if (_ocrText.isNotEmpty &&
                _currentStep == null &&
                _scanResult == null)
              TextButton.icon(
                onPressed: () => _runPipeline(_imageBytes!, _imagePath!),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('解析'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildOcrTextCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.incomeBg,
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.text_snippet,
                size: 16,
                color: AppColors.income,
              ),
              AppSpacing.gapXs,
              Text(
                'OCR 识别文字',
                style: TextStyle(
                  color: AppColors.income,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          AppSpacing.gapXs,
          Text(
            _ocrText,
            style: const TextStyle(fontSize: 13),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.expenseBg,
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.expense, size: 20),
          AppSpacing.gapSm,
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.expense),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(ColorScheme colorScheme) {
    final result = _scanResult!;
    final isIncome = result.type == 'income';
    final accent = isIncome ? AppColors.income : AppColors.expense;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: accent.withValues(alpha: 0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isIncome
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: accent,
                size: 20,
              ),
              AppSpacing.gapSm,
              Text(
                isIncome ? '识别为收入' : '识别为支出',
                style: TextStyle(color: accent, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (result.date != null)
                Text(
                  DateFormat('MM月d日').format(result.date!),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
            ],
          ),
          AppSpacing.gapLg,
          Center(
            child: Text(
              '¥${result.amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
          AppSpacing.gapLg,
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              _chip(
                Icons.category_outlined,
                _matchedCategory(result)?.name ??
                    '${result.categoryName ?? '未识别'} → 其他',
              ),
              _chip(Icons.note_outlined, result.note ?? '无备注'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          AppSpacing.gapXs,
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ImageSourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ImageSourceButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              AppSpacing.gapXs,
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
