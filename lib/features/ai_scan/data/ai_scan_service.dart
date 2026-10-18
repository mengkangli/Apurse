import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum AiScanPipelineStep { recognizing, parsing, completed }

class AiScanResult {
  final double amount;
  final String type;
  final String? categoryName;
  final DateTime? date;
  final String? note;

  const AiScanResult({
    required this.amount,
    required this.type,
    this.categoryName,
    this.date,
    this.note,
  });

  factory AiScanResult.fromJson(Map<String, dynamic> json) {
    // Receipts show payments as "-24.61"; the sign is carried by `type`.
    final rawAmount = json['amount'];
    final amount = rawAmount is num
        ? rawAmount.toDouble().abs()
        : double.tryParse('$rawAmount'.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
    final typeRaw = (json['type'] as String? ?? 'expense').toLowerCase();
    final type =
        typeRaw.contains('income') || typeRaw.contains('收入') ? 'income' : 'expense';

    DateTime? date;
    final rawDate = json['date'];
    if (rawDate is String) {
      date = DateTime.tryParse(rawDate);
      // A model guessing the year can produce far-future dates.
      if (date != null && date.isAfter(DateTime.now().add(const Duration(days: 1)))) {
        date = null;
      }
    }

    final note = (json['note'] as String?)?.trim();
    return AiScanResult(
      amount: double.parse(amount.toStringAsFixed(2)),
      type: type,
      categoryName: (json['category'] as String?)?.trim(),
      date: date,
      note: note == null || note.isEmpty ? null : note,
    );
  }
}

class AiScanPipelineResult {
  final String ocrText;
  final AiScanResult scanResult;

  const AiScanPipelineResult({required this.ocrText, required this.scanResult});
}

class AiScanException implements Exception {
  final String message;
  final AiScanPipelineStep? step;
  final int? httpStatusCode;

  const AiScanException(this.message, {this.step, this.httpStatusCode});

  @override
  String toString() => message;
}

class AiScanService {
  static final AiScanService instance = AiScanService._();
  AiScanService._();

  static const String _baseUrl = 'https://api.deepseek.com/chat/completions';
  static const String _apiKeyStorageKey = 'deepseek_api_key';
  static const Duration _timeout = Duration(seconds: 30);

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── API Key persistence ──
  //
  // The key lives in the platform keystore (Keychain / Android Keystore /
  // Windows Credential Manager). Versions before 1.1 kept it in plain
  // SharedPreferences; it's moved over on first read.

  Future<String?> getSavedApiKey() async {
    String? key;
    try {
      key = await _secureStorage.read(key: _apiKeyStorageKey);
    } catch (_) {
      // Keystore unavailable or corrupted; fall through to the legacy copy.
    }
    if (key != null && key.isNotEmpty) return key;

    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_apiKeyStorageKey);
    if (legacy == null || legacy.isEmpty) return null;
    try {
      await _secureStorage.write(key: _apiKeyStorageKey, value: legacy);
      await prefs.remove(_apiKeyStorageKey);
    } catch (_) {
      // Keep the legacy copy until it can be moved.
    }
    return legacy;
  }

  Future<void> saveApiKey(String key) async {
    await _secureStorage.write(key: _apiKeyStorageKey, value: key);
  }

  Future<void> clearApiKey() async {
    await _secureStorage.delete(key: _apiKeyStorageKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyStorageKey);
  }

  // ── OCR ──

  Future<String> recognizeText({
    required Uint8List bytes,
    required String filePath,
  }) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      final recognizedText = await textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } finally {
      textRecognizer.close();
    }
  }

  // ── DeepSeek API ──

  /// The prompt sent for [text]. The category lists are the user's own, so
  /// custom categories can be matched too.
  static String buildPrompt({
    required String text,
    required List<String> expenseCategories,
    required List<String> incomeCategories,
  }) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return '从以下账单文字中提取记账信息，返回JSON：\n\n$text\n\n'
        '格式：{"amount":正数,"type":"expense或income","category":"分类","date":"YYYY-MM-DD","note":"备注"}\n'
        '规则：\n'
        '- 付款、消费 → expense；收款、退款、工资 → income。amount 一律为正数。\n'
        '- 支出分类只能从这些里选：${expenseCategories.join('、')}\n'
        '- 收入分类只能从这些里选：${incomeCategories.join('、')}\n'
        '- 都不合适时填"其他"。\n'
        '- 账单上没有日期时 date 填 null。今天是 $today。\n'
        '- note 写商户名或商品，不超过 20 个字，不要包含订单号。';
  }

  Future<AiScanResult> parseText({
    required String text,
    required String apiKey,
    required List<String> expenseCategories,
    required List<String> incomeCategories,
  }) async {
    final body = jsonEncode({
      'model': 'deepseek-chat',
      'messages': [
        {
          'role': 'system',
          'content': '你是精确的记账助手。只返回JSON，不返回其他内容。',
        },
        {
          'role': 'user',
          'content': buildPrompt(
            text: text,
            expenseCategories: expenseCategories,
            incomeCategories: incomeCategories,
          ),
        },
      ],
      'temperature': 0.1,
      'max_tokens': 256,
      'response_format': {'type': 'json_object'},
    });

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: body,
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const AiScanException('AI 解析超时，请检查网络后重试',
          step: AiScanPipelineStep.parsing);
    } catch (_) {
      throw const AiScanException('网络连接失败，请检查网络后重试',
          step: AiScanPipelineStep.parsing);
    }

    if (response.statusCode != 200) {
      throw _errorForStatus(response.statusCode);
    }

    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final content = (data['choices'] as List).first['message']['content'] as String;
      final result = jsonDecode(content) as Map<String, dynamic>;
      return AiScanResult.fromJson(result);
    } catch (_) {
      throw const AiScanException('AI 返回的格式无法识别，请重试或手动输入',
          step: AiScanPipelineStep.parsing);
    }
  }

  // ── Pipeline: OCR → DeepSeek ──

  Future<AiScanPipelineResult> scanImage({
    required Uint8List bytes,
    required String filePath,
    required String apiKey,
    required List<String> expenseCategories,
    required List<String> incomeCategories,
    void Function(AiScanPipelineStep)? onProgress,
  }) async {
    onProgress?.call(AiScanPipelineStep.recognizing);

    final ocrText = await recognizeText(bytes: bytes, filePath: filePath);

    if (ocrText.isEmpty) {
      throw const AiScanException(
        'OCR 未能识别文字，请手动输入账单文字后点击解析',
        step: AiScanPipelineStep.recognizing,
      );
    }

    onProgress?.call(AiScanPipelineStep.parsing);

    final result = await parseText(
      text: ocrText,
      apiKey: apiKey,
      expenseCategories: expenseCategories,
      incomeCategories: incomeCategories,
    );
    onProgress?.call(AiScanPipelineStep.completed);
    return AiScanPipelineResult(ocrText: ocrText, scanResult: result);
  }

  AiScanException _errorForStatus(int status) {
    return switch (status) {
      401 => const AiScanException('API Key 无效，请检查后重试', httpStatusCode: 401),
      402 => const AiScanException('DeepSeek 账户余额不足', httpStatusCode: 402),
      429 => const AiScanException('请求过于频繁，请稍后再试', httpStatusCode: 429),
      >= 500 => AiScanException('DeepSeek 服务异常，请稍后再试', httpStatusCode: status),
      _ => AiScanException('解析失败（HTTP $status），请稍后重试', httpStatusCode: status),
    };
  }
}
