import 'package:flutter/widgets.dart';
import '../../../controller/collection_artwork_controller.dart';

/// Optional composition dependency: standalone album widgets retain their
/// original behavior. This scope does not perform network/storage operations.
class CollectionArtworkScope extends InheritedWidget {
  const CollectionArtworkScope(
      {super.key,
      required this.controller,
      required this.languageFor,
      required super.child});
  final CollectionArtworkController controller;
  final String Function(String cardId) languageFor;
  static CollectionArtworkScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CollectionArtworkScope>();
  @override
  bool updateShouldNotify(CollectionArtworkScope oldWidget) => true;
}
