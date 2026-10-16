import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'cache_directory_provider.dart';

class ImageCacheFileSystem implements FileSystem {
  ImageCacheFileSystem({CacheDirectoryProvider? directories})
      : _directories = directories ?? CacheDirectoryProvider();
  final CacheDirectoryProvider _directories;

  @override
  Future<fs.File> createFile(String name) async {
    if (name.contains('/') || name.contains('\\') || name == '..') {
      throw ArgumentError.value(name);
    }
    final directory = await _directories.directory('images');
    return const LocalFileSystem().file('${directory.path}/$name');
  }
}
