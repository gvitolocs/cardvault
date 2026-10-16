import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// DAO per la cartella privata dell'app: sopravvive ai normali riavvii.
class CacheDirectoryProvider {
  CacheDirectoryProvider({Future<Directory> Function()? loadDirectory})
      : _loadDirectory = loadDirectory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _loadDirectory;

  Future<Directory> directory(String section) async {
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(section)) {
      throw ArgumentError.value(section);
    }
    final root = await _loadDirectory();
    return Directory('${root.path}/rebuild-cache/$section')
        .create(recursive: true);
  }
}
