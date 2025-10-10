import 'package:flutter/material.dart';
import '../services/gemini_service.dart';

class TranscriptionViewModel extends ChangeNotifier {
  final GeminiService _geminiService = GeminiService();

  // Store synonyms per transcription ID to avoid re-analyzing
  final Map<int, Map<String, List<String>>> _synonymsCache = {};
  final Set<int> _loadingIds = {};

  Map<String, List<String>> getSynonymsForTranscription(int transcriptionId) {
    return _synonymsCache[transcriptionId] ?? {};
  }

  bool isLoadingForTranscription(int transcriptionId) {
    return _loadingIds.contains(transcriptionId);
  }

  Future<void> analyzeSynonyms(int transcriptionId, String text) async {
    // Don't analyze if already analyzed or currently loading
    if (_synonymsCache.containsKey(transcriptionId) ||
        _loadingIds.contains(transcriptionId)) {
      return;
    }

    try {
      _loadingIds.add(transcriptionId);
      notifyListeners();

      // Use the broader word-level synonyms endpoint to get synonyms for each word
      final synonyms = await _geminiService.getSynonymsForWords(text);
      _synonymsCache[transcriptionId] = synonyms;

      _loadingIds.remove(transcriptionId);
      notifyListeners();
    } catch (e) {
      _loadingIds.remove(transcriptionId);
      _synonymsCache[transcriptionId] = {};
      notifyListeners();
      print('Error in TranscriptionViewModel: $e');
    }
  }

  void clearCache() {
    _synonymsCache.clear();
    _loadingIds.clear();
    notifyListeners();
  }
}
