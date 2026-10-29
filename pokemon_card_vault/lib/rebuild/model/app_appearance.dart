/// Stable local preference IDs; no account or marketplace behavior changes.
enum AppAppearance {
  defaultTheme('default'),
  dungeonCrawler('dungeon_crawler');

  const AppAppearance(this.id);
  final String id;
  static AppAppearance fromId(String? id) =>
      values.firstWhere((value) => value.id == id, orElse: () => defaultTheme);
}
