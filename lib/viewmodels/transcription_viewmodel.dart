import 'package:flutter/material.dart';
import '../services/gemini_service.dart';

class TranscriptionViewModel extends ChangeNotifier {
  final GeminiService _geminiService = GeminiService();

  // Store synonyms per transcription ID to avoid re-analyzing
  final Map<int, Map<String, List<String>>> _synonymsCache = {};
  final Set<int> _loadingIds = {};
  final Set<int> _analyzedIds = {}; // Track what's been analyzed

  Map<String, List<String>> getSynonymsForTranscription(int transcriptionId) {
    return _synonymsCache[transcriptionId] ?? {};
  }

  bool isLoadingForTranscription(int transcriptionId) {
    return _loadingIds.contains(transcriptionId);
  }

  bool hasBeenAnalyzed(int transcriptionId) {
    return _analyzedIds.contains(transcriptionId);
  }

  Future<void> analyzeSynonyms(int transcriptionId, String text) async {
    // CRITICAL: Check if already analyzed or loading to prevent duplicates
    if (_analyzedIds.contains(transcriptionId) ||
        _loadingIds.contains(transcriptionId)) {
      print(
          '🚁 Analysis already in progress or completed for $transcriptionId');
      return;
    }

    // Validate input text
    if (text.trim().isEmpty) {
      print('🚁 Empty text provided for analysis: $transcriptionId');
      _analyzedIds.add(transcriptionId);
      _synonymsCache[transcriptionId] = {};
      notifyListeners();
      return;
    }

    // Mark as analyzed immediately to prevent duplicate calls
    _analyzedIds.add(transcriptionId);

    try {
      _loadingIds.add(transcriptionId);
      notifyListeners();

      print(
          '🚁 Starting aviation terms analysis for transcription $transcriptionId');
      print('🚁 Text to analyze: "$text"');

      // Use the improved aviation terms analysis
      final synonyms = await _geminiService.getSynonymsForWords(text);

      print('🚁 Received aviation terms for $transcriptionId: $synonyms');
      print('🚁 Number of terms found: ${synonyms.length}');

      _synonymsCache[transcriptionId] = synonyms;
      _loadingIds.remove(transcriptionId);
      notifyListeners();
    } catch (e) {
      print('🚁 Error in TranscriptionViewModel for $transcriptionId: $e');
      _loadingIds.remove(transcriptionId);
      _synonymsCache[transcriptionId] = {};
      notifyListeners();
    }
  }

  void clearCache() {
    _synonymsCache.clear();
    _loadingIds.clear();
    _analyzedIds.clear();
    notifyListeners();
  }
}
