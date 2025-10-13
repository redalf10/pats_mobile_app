import 'dart:async';

import 'package:pats_app/services/audio_service.dart';
import 'package:pats_app/services/firebase_service.dart';

class TranscriptionHandler {
  final AudioService _audioService;
  final FirebaseDbService _dbService;
  StreamSubscription<String>? _transcriptionSubscription;
  StreamSubscription<String>? _sttStatusSubscription;
  String? _currentUserId;
  String? _currentUserName;
  Timer? _finalizeTimer;
  String _lastProcessedText = '';
  bool _hasReceivedResult = false;

  TranscriptionHandler({
    required AudioService audioService,
    required FirebaseDbService dbService,
  })  : _audioService = audioService,
        _dbService = dbService;

  void startListening({
    required String userId,
    required String userName,
  }) {
    _currentUserId = userId;
    _currentUserName = userName;
    _lastProcessedText = '';
    _hasReceivedResult = false;

    // Cancel existing subscriptions
    _transcriptionSubscription?.cancel();
    _sttStatusSubscription?.cancel();
    _finalizeTimer?.cancel();

    print('TranscriptionHandler: Starting to listen for user $userName');

    // Listen to transcription results
    _transcriptionSubscription = _audioService.transcriptionStream.listen(
      (text) {
        if (_currentUserId == null) return;

        print('TranscriptionHandler: Received text: "$text"');

        // Skip empty intermediate results
        if (text.isEmpty && !_hasReceivedResult) {
          return;
        }

        _hasReceivedResult = true;
        _lastProcessedText = text;

        if (text.isNotEmpty) {
          // Add or update transcription with partial results
          _dbService.addOrUpdateTranscription(
            userId: _currentUserId!,
            userName: _currentUserName ?? '',
            text: text,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            isFinal: false, // Mark as not final during streaming
          );

          // Reset the finalize timer - will finalize after 2 seconds of no updates
          _finalizeTimer?.cancel();
          _finalizeTimer = Timer(const Duration(seconds: 2), () {
            if (_lastProcessedText.isNotEmpty) {
              print('TranscriptionHandler: Finalizing due to timeout');
              _finalizeCurrentTranscription();
            }
          });
        }
      },
      onError: (error) {
        print('TranscriptionHandler: Error in transcription stream: $error');
      },
    );

    // Monitor STT status to detect when speech stops
    _sttStatusSubscription = _audioService.sttStatusStream.listen(
      (status) {
        print('TranscriptionHandler: STT Status: $status');

        // When STT stops listening or completes, finalize the transcription
        if (status == 'done' || status == 'notListening') {
          _finalizeTimer?.cancel();
          if (_hasReceivedResult && _lastProcessedText.isNotEmpty) {
            print(
                'TranscriptionHandler: Finalizing due to STT status: $status');
            _finalizeCurrentTranscription();
          }
        }
      },
      onError: (error) {
        print('TranscriptionHandler: Error in STT status stream: $error');
      },
    );
  }

  void _finalizeCurrentTranscription() {
    if (_currentUserId == null || _lastProcessedText.isEmpty) return;

    print(
        'TranscriptionHandler: Creating final transcription: "$_lastProcessedText"');

    // Create a final transcription entry
    _dbService.addOrUpdateTranscription(
      userId: _currentUserId!,
      userName: _currentUserName ?? 'Unknown',
      text: _lastProcessedText,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isFinal: true, // Mark as final
    );

    // Reset state
    _lastProcessedText = '';
    _hasReceivedResult = false;
  }

  void stopListening() {
    print('TranscriptionHandler: Stopping listening');

    // Finalize any pending transcription
    _finalizeTimer?.cancel();
    if (_hasReceivedResult && _lastProcessedText.isNotEmpty) {
      _finalizeCurrentTranscription();
    }

    _transcriptionSubscription?.cancel();
    _sttStatusSubscription?.cancel();
    _transcriptionSubscription = null;
    _sttStatusSubscription = null;
  }

  void dispose() {
    _finalizeTimer?.cancel();
    _transcriptionSubscription?.cancel();
    _sttStatusSubscription?.cancel();
  }
}
