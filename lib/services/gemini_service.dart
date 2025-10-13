import 'dart:async';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static const String _apiKey = 'AIzaSyCZD818_pm5hMLUMc2W__INHPShDsiLSEg';
  final GenerativeModel _model;

  GeminiService()
      : _model = GenerativeModel(
          model: 'gemini-1.5-flash', // Updated to newer model
          apiKey: _apiKey,
        );

  /// Get synonyms for each word in the given text.
  /// Returns a map of word -> list of synonyms (up to 3 each where available).
  Future<Map<String, List<String>>> getSynonymsForWords(String text) async {
    try {
      // Basic sanitization
      final sanitized = text
          .replaceAll(RegExp(r'[\r\n]+'), ' ')
          .replaceAll(RegExp(r"[^A-Za-z0-9\s']"), '')
          .trim();

      if (sanitized.isEmpty) return {};

      final prompt = '''
Extract aviation-related or important words from the text and provide up to 3 synonyms for each.
Ignore common words like: the, a, an, and, or, of, to, in, is, are, was, were, that, it, this, for, on, with, at, by, from.

Format each line exactly as:
word: synonym1, synonym2, synonym3

Text: $sanitized

Respond ONLY with the word:synonym format, one per line. No explanations or extra text.
''';

      final content = [Content.text(prompt)];

      // Add timeout and better error handling
      final response = await _model
          .generateContent(content)
          .timeout(const Duration(seconds: 30));

      // Check if response has valid text
      if (response.text == null || response.text!.isEmpty) {
        print('Empty response from Gemini');
        return {};
      }

      final responseText = response.text!;
      print('Gemini response: $responseText'); // Debug log

      final Map<String, List<String>> synonymMap = {};
      final lines = responseText.split(RegExp(r'\n'));

      for (var raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;

        // Skip lines that don't contain colon
        if (!line.contains(':')) continue;

        final colonIndex = line.indexOf(':');
        final word = line.substring(0, colonIndex).trim();
        final synonymsPart = line.substring(colonIndex + 1).trim();

        if (word.isEmpty || synonymsPart.isEmpty) continue;

        final synonyms = synonymsPart
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .take(3) // Limit to 3 synonyms
            .toList();

        if (synonyms.isNotEmpty) {
          synonymMap[word] = synonyms;
        }
      }

      print('Parsed synonyms: $synonymMap'); // Debug log
      return synonymMap;
    } on TimeoutException catch (e) {
      print('Timeout getting synonyms: $e');
      return {};
    } catch (e) {
      print('Error getting synonyms for words: $e');
      return {};
    }
  }

  /// Transcribe audio data to text using Gemini.
  /// Returns the transcribed text or null if failed.
  Future<String?> transcribeAudio(Uint8List audioData) async {
    try {
      final prompt =
          'Transcribe this audio accurately. Provide only the transcribed text, no additional comments or formatting.';

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('audio/wav', audioData),
        ])
      ];

      final response = await _model
          .generateContent(content)
          .timeout(const Duration(seconds: 30));

      if (response.text != null && response.text!.trim().isNotEmpty) {
        return response.text!.trim();
      }
      return null;
    } on TimeoutException catch (e) {
      print('Timeout transcribing audio: $e');
      return null;
    } catch (e) {
      print('Error transcribing audio: $e');
      return null;
    }
  }
}
