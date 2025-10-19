import 'dart:async';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static const String _apiKey = 'AIzaSyCZD818_pm5hMLUMc2W__INHPShDsiLSEg';
  final GenerativeModel _model;

  GeminiService()
      : _model = GenerativeModel(
          model: 'gemini-2.0-flash', // Updated to correct model name
          apiKey: _apiKey,
        );

  /// Get synonyms for each word in the given text.
  /// Returns a map of word -> list of synonyms (up to 3 each where available).
  Future<Map<String, List<String>>> getSynonymsForWords(String text) async {
    try {
      // Minimal sanitization - preserve the original text as much as possible
      final sanitized = text
          .replaceAll(RegExp(r'[\r\n]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (sanitized.isEmpty) return {};

      print('🚁 Analyzing text for aviation terms: $sanitized');

      final prompt = '''
You are an aviation expert. Analyze the following text and identify ALL aviation-related terms, flight operations, aircraft terminology, airport codes, flight numbers, and aviation procedures.

Look for terms like:
- Flight numbers (e.g., "Flight 4B7", "AA123")
- Aircraft types and models
- Airport names and codes (e.g., "Hong Kong", "San Francisco", "LAX", "JFK")
- Aviation procedures (e.g., "take-off", "landing", "boarding", "departure")
- Aviation terminology (e.g., "runway", "taxi", "gate", "terminal")
- Airline names and codes
- Aviation weather terms
- Navigation and communication terms

For each aviation term found, provide up to 3 related synonyms or alternative terms.

Format each line exactly as:
term: synonym1, synonym2, synonym3

Text to analyze: "$sanitized"

Respond ONLY with the term:synonym format, one per line. No explanations or extra text.
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
      print('🚁 Gemini response: $responseText'); // Debug log

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

      print('🚁 Parsed aviation terms: $synonymMap'); // Debug log
      return synonymMap;
    } on TimeoutException catch (e) {
      print('Timeout getting aviation terms: $e');
      return {};
    } catch (e) {
      print('Error getting aviation terms: $e');
      return {};
    }
  }

  /// Transcribe audio data to text using Gemini.
  /// Returns the transcribed text or null if failed.
  Future<String?> transcribeAudio(Uint8List audioData) async {
    try {
      const prompt =
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
