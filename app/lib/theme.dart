import 'package:flutter/material.dart';

/// 配色与原型图完全一致，改动前请同步 `原型图.html` 的 :root 变量。
class AppColors {
  static const ink = Color(0xFF26231F);
  static const ink2 = Color(0xFF6E6960);
  static const ink3 = Color(0xFFA29C93);
  static const line = Color(0xFFEAE6DF);
  static const soft = Color(0xFFF6F4F0);
  static const tile = Color(0xFFF2F2F0);

  /// 浅色衣物用的深一档底色，见设计文档 5.5。
  static const tileDeep = Color(0xFFDCDCD8);
  static const accent = Color(0xFF8C6A4F);

  /// 变化量的方向色：减绿、增红。见设计文档 P7。
  static const down = Color(0xFF4C7A55);
  static const up = Color(0xFFA8574B);
}

class AppTheme {
  /// [fontFamily] 平时留空，用系统默认字体。
  /// 只有 golden 测试会传一个值：`flutter test` 带 `--use-test-fonts`，
  /// 默认家族是 Ahem（全是方块），必须在 Theme 里显式指定真实字体。
  /// 注意每个显式写死的 TextStyle 都要带上它，否则那部分文字还是方块。
  static ThemeData build({String? fontFamily}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        primary: AppColors.ink,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      fontFamily: fontFamily,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
        fontFamily: fontFamily,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: fontFamily),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
          letterSpacing: 0.2,
          fontFamily: fontFamily,
        ),
        iconTheme: const IconThemeData(color: AppColors.ink, size: 22),
      ),
      dividerColor: AppColors.line,
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            fontFamily: fontFamily,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(46),
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            fontFamily: fontFamily,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: TextStyle(fontFamily: fontFamily),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontFamily: fontFamily,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.soft,
        hintStyle: TextStyle(
          color: AppColors.ink3,
          fontSize: 15,
          fontFamily: fontFamily,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
        ),
      ),
    );
  }

  /// 正文用：小标签
  static const label = TextStyle(
    fontSize: 11,
    color: AppColors.ink3,
    height: 1.3,
  );

  /// 正文用：次要说明
  static const hint = TextStyle(
    fontSize: 12,
    color: AppColors.ink3,
    height: 1.5,
  );

  static const body = TextStyle(
    fontSize: 14,
    color: AppColors.ink,
    height: 1.5,
  );
}
