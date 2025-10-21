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

Identify the aviation context of the spoken phrase (e.g., taxi request, landing clearance, approach report, etc.).

Suggest one or more aviation scripts or phrases that sound similar, have a related meaning, or are typically used in the same situation — based on standard ICAO/FAA/Philippine ATC procedures and the Flight Procedures Script reference.

Keep responses concise and professional, just like real ATC/pilot radio transmissions.

If the spoken phrase is unclear, suggest the closest matching script based on phonetic or procedural similarity.

Example Interaction:

🎙 User says: "Tower, RPC 223 ready for departure." (dont include this in your response)

🤖 AI Suggestion:
"Did you mean: 'PhilSCA Tower, RPC 223, ready for take-off'?
Related phrase: 'RPC 223, cleared for take-off, wind 060 at 8 knots.'"

🎙 User says: "Cleared for taxi." (dont include this in your response)

🤖 AI Suggestion:
"Similar script: 'PhilSCA Tower, Philippine 145, now ready for taxi.'
Related term: 'Taxi via C2, B, H1, hold short runway 06.'"

Formatting Rules:

If the user's phrase matches a known phrase from the script → show the closest complete line from the official script.

If it's not an exact match → suggest related or phonetically similar aviation terms (e.g., "pushback approved," "hold short," "report over [waypoint]").

Include context tags like [Start-Up], [Taxi], [Takeoff], [Landing], etc. to help categorize responses.

Text to analyze: "$sanitized"

Respond with aviation script suggestions and related phrases in the format shown above. Be concise and professional.
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
