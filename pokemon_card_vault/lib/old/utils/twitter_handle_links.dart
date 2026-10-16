class TwitterHandleLink {
  const TwitterHandleLink({
    required this.text,
    required this.handle,
    required this.start,
    required this.end,
  });

  final String text;
  final String handle;
  final int start;
  final int end;

  Uri get uri => Uri.https('x.com', '/$handle');
}

final RegExp _twitterHandlePattern = RegExp(r'@([A-Za-z0-9_]{1,15})');

List<TwitterHandleLink> findTwitterHandleLinks(String text) {
  final links = <TwitterHandleLink>[];
  for (final match in _twitterHandlePattern.allMatches(text)) {
    final handle = match.group(1);
    if (handle == null ||
        !_hasTwitterHandleStartBoundary(text, match.start) ||
        !_hasTwitterHandleEndBoundary(text, match.end)) {
      continue;
    }
    links.add(
      TwitterHandleLink(
        text: match.group(0)!,
        handle: handle,
        start: match.start,
        end: match.end,
      ),
    );
  }
  return links;
}

bool _hasTwitterHandleStartBoundary(String text, int start) {
  if (start == 0) {
    return true;
  }
  final previous = text.codeUnitAt(start - 1);
  return !_isTwitterHandleChar(previous) &&
      previous != 0x40 && // @
      previous != 0x2B && // +
      previous != 0x2D && // -
      previous != 0x2E; // .
}

bool _hasTwitterHandleEndBoundary(String text, int end) {
  return end >= text.length || !_isTwitterHandleChar(text.codeUnitAt(end));
}

bool _isTwitterHandleChar(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      codeUnit == 0x5F ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A);
}
