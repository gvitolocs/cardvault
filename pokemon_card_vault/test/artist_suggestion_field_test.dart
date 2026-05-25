import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/widgets/artist_suggestion_field.dart';

void main() {
  testWidgets('selecting an artist suggestion enables immediate save',
      (tester) async {
    final controller = TextEditingController();
    var selectedArtistId = '';
    var selectedArtistName = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  ArtistSuggestionField(
                    controller: controller,
                    fallbackSuggestions: const [
                      ArtistSuggestion(
                        name: 'Mitsuhiro Arita',
                        normalizedArtist: 'mitsuhiro-arita',
                        slug: 'mitsuhiro-arita',
                        knownCount: 42,
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      if (value.trim() != selectedArtistName.trim()) {
                        selectedArtistId = '';
                        selectedArtistName = '';
                      }
                    }),
                    onSelected: (artist) => setState(() {
                      selectedArtistId = artist.normalizedArtist;
                      selectedArtistName = artist.name;
                      controller.value = TextEditingValue(
                        text: artist.name,
                        selection: TextSelection.collapsed(
                          offset: artist.name.length,
                        ),
                      );
                    }),
                  ),
                  FilledButton(
                    onPressed: selectedArtistId.isEmpty ? null : () {},
                    child: const Text('Save artist'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    await tester.enterText(find.byType(TextField), 'ari');
    await tester.pump();

    await tester.tap(find.text('Mitsuhiro Arita').last);
    await tester.pump();

    expect(controller.text, 'Mitsuhiro Arita');
    expect(selectedArtistId, 'mitsuhiro-arita');
    expect(selectedArtistName, 'Mitsuhiro Arita');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
}
