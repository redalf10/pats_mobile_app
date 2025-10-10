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
      return;
    }

    // Mark as analyzed immediately to prevent duplicate calls
    _analyzedIds.add(transcriptionId);

    try {
      _loadingIds.add(transcriptionId);
      notifyListeners();

      print('Starting analysis for transcription $transcriptionId: $text');

      // Use the broader word-level synonyms endpoint
      final synonyms = await _geminiService.getSynonymsForWords(text);

      print('Received synonyms for $transcriptionId: $synonyms');

      _synonymsCache[transcriptionId] = synonyms;
      _loadingIds.remove(transcriptionId);
      notifyListeners();
    } catch (e) {
      print('Error in TranscriptionViewModel for $transcriptionId: $e');
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
