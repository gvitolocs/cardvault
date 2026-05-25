import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/utils/twitter_handle_links.dart';

void main() {
  test('finds valid Twitter handles and preserves visible text', () {
    final links = findTwitterHandleLinks(
      'Their Twitter account is: @kuroimori_twee and @Arita_123.',
    );

    expect(links, hasLength(2));
    expect(links[0].text, '@kuroimori_twee');
    expect(links[0].handle, 'kuroimori_twee');
    expect(links[0].uri.toString(), 'https://x.com/kuroimori_twee');
    expect(links[1].text, '@Arita_123');
    expect(links[1].handle, 'Arita_123');
  });

  test('ignores emails and overlong handles', () {
    final links = findTwitterHandleLinks(
      'Email art@example.com, not @abcdefghijklmnop or name+@handle.',
    );

    expect(links, isEmpty);
  });

  test('does not link partial handles inside longer words', () {
    final links = findTwitterHandleLinks(
      'Skip a@handle, @@handle, @valid_handle, and @toolonghandle_1234.',
    );

    expect(links.map((link) => link.text), ['@valid_handle']);
  });
}
