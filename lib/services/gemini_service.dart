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
You are an aviation communication assistant trained on air traffic control (ATC) and pilot radio phraseology.

Your task is to:

1. Suggest one or more aviation scripts or phrases that sound similar, have a related meaning, or are typically used in the same situation — based on standard ICAO/FAA/Philippine ATC procedures and the Flight Procedures Script reference.
3. Convert any aircraft call signs, letters, or identifiers into the NATO phonetic alphabet.
4. Include **ICAO airport codes** and expand them to their **full airport names**, especially for Philippine airports.

If the spoken phrase is unclear, suggest the closest matching script based on phonetic or procedural similarity especially the word PhilSCA.

Formatting Rules:
- If the user's phrase matches a known script → show the closest complete line from the official ATC script.
- If it's not an exact match → suggest related or phonetically similar aviation terms.

When displaying call signs or ICAO codes:
- Replace any letters with their **NATO phonetic equivalents**.
- If an ICAO airport code is detected, include the corresponding **airport name** in parentheses.

Example Interaction:

🎙 User says: "Tower, RPC 223 ready for departure."

🤖 AI Suggestion:
"Did you mean: 'PhilSCA Tower, Romeo Papa Charlie Two Two Three, ready for take-off'?
Related phrase: 'Romeo Papa Charlie Two Two Three, cleared for take-off, wind 060 at 8 knots.'"

Text to analyze: "$sanitized"

Respond with aviation script suggestions and related phrases in the concise, professional format shown above.
''';

      final content = [Content.text(prompt)];

      // Add timeout and better error handling
      final response = await _model
          .generateContent(content)
          .timeout(const Duration(seconds: 30));

      // Check if response has valid text
      if (response.text == null || response.text!.isEmpty) {
        // print('Empty response from Gemini');
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

        // Handle special case for no aviation terms
        if (word == 'no_aviation_terms' && synonymsPart == 'none') {
          print('🚁 No aviation terms detected in text');
          return {};
        }

        final synonyms = synonymsPart
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s != 'none')
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
