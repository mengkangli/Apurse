import 'package:apurse/core/widgets/app_icon_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every icon the app can store resolves to itself', () {
    for (final icon in [
      ...AppIconData.categoryPalette,
      ...AppIconData.accountIcons,
      ...AppIconData.defaultCategoryIcons.values,
      ...AppIconData.defaultAccountIcons.values,
    ]) {
      expect(AppIconData.fromCodePoint(icon.codePoint), icon);
    }
  });

  test('codes from the old icon picker still render what users picked', () {
    expect(AppIconData.fromCodePoint(0xe553), Icons.savings);
    expect(AppIconData.fromCodePoint(0xe561), Icons.screen_share);
  });

  test('unknown codes fall back to a generic icon', () {
    expect(AppIconData.fromCodePoint(1), Icons.category_rounded);
  });

  test('every built-in category has an icon', () {
    expect(AppIconData.defaultCategoryIcons.length, 27);
  });
}
