import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
import '../services/firebase_service.dart';
import '../models/transcription.dart';
import 'dart:async';

class TranscriptionViewModel extends ChangeNotifier {
  final GeminiService _geminiService = GeminiService();
  StreamSubscription<List<Transcription>>? _transcriptionSubscription;

  // Store synonyms per transcription ID to avoid re-analyzing
  final Map<int, Map<String, List<String>>> _synonymsCache = {};
  final Set<int> _loadingIds = {};
  final Set<int> _analyzedIds = {}; // Track what's been analyzed
  final Set<int> _autoAnalyzedIds = {}; // Track what's been auto-analyzed

  Map<String, List<String>> getSynonymsForTranscription(int transcriptionId) {
    return _synonymsCache[transcriptionId] ?? {};
  }

  bool isLoadingForTranscription(int transcriptionId) {
    return _loadingIds.contains(transcriptionId);
  }

  bool hasBeenAnalyzed(int transcriptionId) {
    return _analyzedIds.contains(transcriptionId);
  }

  bool hasBeenAutoAnalyzed(int transcriptionId) {
    return _autoAnalyzedIds.contains(transcriptionId);
  }

  // Set up automatic analysis for new transcriptions
  void setupAutoAnalysis(FirebaseDbService dbService) {
    _transcriptionSubscription?.cancel();
    _transcriptionSubscription =
        dbService.watchAllNewestFirst().listen((transcriptions) {
      // Only analyze the most recent transcription if it hasn't been analyzed yet
      if (transcriptions.isNotEmpty) {
        final latestTranscription = transcriptions.first;
        final transcriptionId = latestTranscription.timestamp;

        // Check if this transcription hasn't been auto-analyzed yet
        if (!_autoAnalyzedIds.contains(transcriptionId) &&
            !_analyzedIds.contains(transcriptionId) &&
            !_loadingIds.contains(transcriptionId)) {
          print(
              '🚁 Auto-analyzing new transcription: "${latestTranscription.text}" (ID: $transcriptionId)');
          _autoAnalyzedIds.add(transcriptionId);
          analyzeSynonyms(transcriptionId, latestTranscription.text);
        } else {
          print(
              '🚁 Skipping analysis for transcription $transcriptionId - already processed');
        }
      }
    });
  }

  @override
  void dispose() {
    _transcriptionSubscription?.cancel();
    super.dispose();
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
    _autoAnalyzedIds.clear();
    notifyListeners();
  }
}
