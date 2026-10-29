import 'package:flutter/material.dart';
import '../model/app_appearance.dart';
import 'default/default_theme.dart';
import 'dungeon_crawler/dungeon_crawler_theme.dart';

abstract final class AppStyle {
  static ThemeData forAppearance(AppAppearance appearance) =>
      switch (appearance) {
        AppAppearance.defaultTheme => DefaultTheme.build(),
        AppAppearance.dungeonCrawler => DungeonCrawlerTheme.build(),
      };
}
