import 'dart:io';
import 'cache_directory_provider.dart';

/// Lettura/scrittura del file JSON; le regole di scadenza restano nel cache layer.
class CacheFileProvider {
  CacheFileProvider({CacheDirectoryProvider? directories})
      : _directories = directories ?? CacheDirectoryProvider();
  final CacheDirectoryProvider _directories;

  Future<File> _file() async {
    final directory = await _directories.directory('metadata');
    return File('${directory.path}/marketplace-home-v1.json');
  }

  Future<String?> read() async {
    final file = await _file();
    return await file.exists() ? file.readAsString() : null;
  }

  Future<void> write(String contents) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(file.path);
  }
}
