import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/card_model.dart';

class ApiService {
  static const String _baseUrl =
      'https://api.pokemontcg.io/v2/cards?q=supertype:pokemon';

  static Future<List<CardModel>> fetchCards() async {
    final response = await http.get(Uri.parse(_baseUrl));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> cards = data['data'];
      return cards.map((json) => CardModel.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load cards');
    }
  }
}
