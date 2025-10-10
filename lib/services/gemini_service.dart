import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static const String _apiKey = 'AIzaSyCZD818_pm5hMLUMc2W__INHPShDsiLSEg';
  final GenerativeModel _model;

  GeminiService()
      : _model = GenerativeModel(
          model: 'gemini-pro',
          apiKey: _apiKey,
        );

  Future<Map<String, List<String>>> getNounSynonyms(String text) async {
    try {
      final prompt = '''
      Analyze the following text and extract only nouns. For each noun, provide 3 synonyms.
      Return the result in this format:
      noun1: synonym1, synonym2, synonym3
      noun2: synonym1, synonym2, synonym3

      Text: $text
      ''';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      final responseText = response.text ?? '';

      // Parse the response into a map of nouns and their synonyms
      final Map<String, List<String>> synonymMap = {};
      final lines = responseText.split('\n');

      for (final line in lines) {
        if (line.contains(':')) {
          final parts = line.split(':');
          final noun = parts[0].trim();
          final synonyms = parts[1]
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (synonyms.isNotEmpty) {
            synonymMap[noun] = synonyms;
          }
        }
      }

      return synonymMap;
    } catch (e) {
      print('Error getting synonyms: $e');
      return {};
    }
  }

  /// Get synonyms for each word in the given text.
  /// Returns a map of word -> list of synonyms (up to 3 each where available).
  Future<Map<String, List<String>>> getSynonymsForWords(String text) async {
    try {
      // Basic sanitization: collapse whitespace and remove punctuation except apostrophes
      final sanitized = text
          .replaceAll(RegExp(r'[\r\n]+'), ' ')
          .replaceAll(RegExp(r"[^A-Za-z0-9\s']"), '')
          .trim();

      if (sanitized.isEmpty) return {};

      final prompt = '''
      For the provided text, extract each distinct meaningful word (ignore common stopwords like "the,a,an,and,or,of,to,in,is,are,was,were,that,it") and for each word provide up to 3 concise synonyms.
      Return only lines in the format:
      word: synonym1, synonym2, synonym3

      Text: $sanitized
      ''';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      final responseText = response.text ?? '';

      final Map<String, List<String>> synonymMap = {};
      final lines = responseText.split(RegExp(r'\n'));

      for (var raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (!line.contains(':')) continue;
        final parts = line.split(':');
        if (parts.length < 2) continue;
        final word = parts[0].trim();
        if (word.isEmpty) continue;
        final synonyms = parts[1]
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (synonyms.isNotEmpty) {
          synonymMap[word] = synonyms;
        }
      }

      return synonymMap;
    } catch (e) {
      print('Error getting synonyms for words: $e');
      return {};
    }
  }
}
