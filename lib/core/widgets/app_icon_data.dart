import 'package:flutter/material.dart';

/// Maps the `icon_code` stored on categories and accounts back to a const
/// [IconData]. Building `IconData(codePoint)` at runtime would defeat icon
/// tree-shaking, so every icon the app can store must be listed here.
class AppIconData {
  const AppIconData._();

  static IconData fromCodePoint(int codePoint) {
    return _byCodePoint[codePoint] ?? Icons.category_rounded;
  }

  /// Icons offered when creating a category.
  static const List<IconData> categoryPalette = [
    Icons.restaurant_rounded,
    Icons.local_cafe_rounded,
    Icons.fastfood_rounded,
    Icons.local_bar_rounded,
    Icons.shopping_bag_rounded,
    Icons.shopping_basket_rounded,
    Icons.checkroom_rounded,
    Icons.directions_bus_rounded,
    Icons.local_taxi_rounded,
    Icons.train_rounded,
    Icons.flight_rounded,
    Icons.local_gas_station_rounded,
    Icons.home_rounded,
    Icons.chair_rounded,
    Icons.bolt_rounded,
    Icons.water_drop_rounded,
    Icons.wifi_rounded,
    Icons.phone_iphone_rounded,
    Icons.devices_rounded,
    Icons.movie_rounded,
    Icons.sports_esports_rounded,
    Icons.music_note_rounded,
    Icons.fitness_center_rounded,
    Icons.spa_rounded,
    Icons.content_cut_rounded,
    Icons.local_hospital_rounded,
    Icons.medication_rounded,
    Icons.school_rounded,
    Icons.menu_book_rounded,
    Icons.child_care_rounded,
    Icons.pets_rounded,
    Icons.card_giftcard_rounded,
    Icons.favorite_rounded,
    Icons.celebration_rounded,
    Icons.hotel_rounded,
    Icons.local_parking_rounded,
    Icons.build_rounded,
    Icons.subscriptions_rounded,
    Icons.receipt_long_rounded,
    Icons.payments_rounded,
    Icons.work_rounded,
    Icons.trending_up_rounded,
    Icons.savings_rounded,
    Icons.redeem_rounded,
    Icons.emoji_events_rounded,
    Icons.storefront_rounded,
    Icons.replay_rounded,
    Icons.more_horiz_rounded,
  ];

  /// Icons for the account types on the add-account screen.
  static const List<IconData> accountIcons = [
    Icons.chat_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.credit_card_rounded,
    Icons.attach_money_rounded,
    Icons.more_horiz_rounded,
  ];

  /// Icons for the built-in categories, by category id.
  static const Map<String, IconData> defaultCategoryIcons = {
    'ic001': Icons.payments_rounded, // 工资
    'ic002': Icons.work_rounded, // 兼职
    'ic003': Icons.trending_up_rounded, // 投资
    'ic004': Icons.redeem_rounded, // 礼金
    'ic005': Icons.replay_rounded, // 退款
    'ic006': Icons.emoji_events_rounded, // 奖金
    'ic007': Icons.savings_rounded, // 理财
    'ic008': Icons.storefront_rounded, // 副业
    'ic009': Icons.more_horiz_rounded, // 其他
    'ec001': Icons.restaurant_rounded, // 餐饮
    'ec002': Icons.directions_bus_rounded, // 交通
    'ec003': Icons.shopping_bag_rounded, // 购物
    'ec004': Icons.movie_rounded, // 娱乐
    'ec005': Icons.receipt_long_rounded, // 账单
    'ec006': Icons.local_hospital_rounded, // 医疗
    'ec007': Icons.school_rounded, // 教育
    'ec008': Icons.home_rounded, // 居住
    'ec009': Icons.shopping_basket_rounded, // 日用
    'ec010': Icons.phone_iphone_rounded, // 通讯
    'ec011': Icons.checkroom_rounded, // 服饰
    'ec012': Icons.devices_rounded, // 数码
    'ec013': Icons.fitness_center_rounded, // 运动
    'ec014': Icons.pets_rounded, // 宠物
    'ec015': Icons.chair_rounded, // 居家
    'ec016': Icons.more_horiz_rounded, // 其他
    'ec017': Icons.subscriptions_rounded, // 订阅
    'ec018': Icons.menu_book_rounded, // 学习
  };

  /// Icons for the seeded accounts, by account id.
  static const Map<String, IconData> defaultAccountIcons = {
    'acc001': Icons.chat_rounded, // 微信零钱
    'acc002': Icons.account_balance_wallet_rounded, // 支付宝余额
    'acc003': Icons.attach_money_rounded, // 现金
  };

  /// Codes written before v1.1. The built-in categories and accounts move
  /// to the icons above in the v5 migration, but categories users created
  /// keep whatever they picked from the old picker, which showed these.
  static const List<IconData> _legacy = [
    Icons.six_k_plus,
    Icons.account_circle,
    Icons.add_box,
    Icons.add_circle_outline,
    Icons.add_road,
    Icons.atm,
    Icons.auto_graph,
    Icons.bathtub,
    Icons.bookmark_add,
    Icons.border_bottom,
    Icons.closed_caption_disabled,
    Icons.directions_walk,
    Icons.electric_scooter,
    Icons.engineering,
    Icons.help_center,
    Icons.hide_image,
    Icons.home_mini,
    Icons.hot_tub,
    Icons.hourglass_bottom,
    Icons.house,
    Icons.houseboat,
    Icons.lock_open,
    Icons.logout,
    Icons.medication,
    Icons.nearby_off,
    Icons.phone_android,
    Icons.restart_alt,
    Icons.roofing,
    Icons.rule_folder,
    Icons.sanitizer,
    Icons.satellite,
    Icons.saved_search,
    Icons.savings,
    Icons.screen_share,
    Icons.sd_card_alert,
    Icons.sentiment_dissatisfied,
    Icons.sentiment_satisfied,
    Icons.sort,
    Icons.sort_by_alpha,
    Icons.swap_vert,
    Icons.add_link_sharp,
    Icons.book_online_sharp,
    Icons.bookmark_remove_sharp,
    Icons.brightness_medium_sharp,
    Icons.browser_not_supported_sharp,
    Icons.data_saver_off_sharp,
    Icons.delete_sharp,
  ];

  static final Map<int, IconData> _byCodePoint = {
    for (final icon in [..._legacy, ...categoryPalette, ...accountIcons])
      icon.codePoint: icon,
  };
}
