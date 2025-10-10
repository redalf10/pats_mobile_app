import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  // Use ephemeral players for remote audio playback to avoid interfering
  // with the main player or recording. Track active players for cleanup.
  final List<AudioPlayer> _activePlayers = [];
  bool _isRecording = false;
  String? _currentRecordingPath;
  StreamSubscription? _recordingSubscription;
  stt.SpeechToText? _speech;
  String _lastTranscription = '';
  String _lastNonEmptyTranscription = '';
  // Indicates whether recording was paused (true) or stopped (false) to allow STT
  bool _pausedRecordingForStt = false;
  final StreamController<String> _transcriptionController =
      StreamController<String>.broadcast();
  final StreamController<String> _sttStatusController =
      StreamController<String>.broadcast();
  String _lastSttStatus = '';
  bool _isListening = false;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentPlayingFile;
  StreamSubscription? _playerCompleteSubscription;

  Logger logger = Logger();

  Future<bool> requestPermissions() async {
    try {
      logger.i('Requesting microphone permission...');
      final micStatus = await Permission.microphone.request().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          logger.w('Microphone permission request timed out');
          return PermissionStatus.denied;
        },
      );

      logger.i('Microphone permission status: $micStatus');

      final result = micStatus.isGranted;
      logger.i('Overall permission result (mic only): $result');

      return result;
    } catch (e) {
      logger.e('Error requesting permissions: $e');
      return false;
    }
  }

  Future<String?> startRecording() async {
    if (_isRecording) return null;

    try {
      if (!await Permission.microphone.isGranted) {
        final ok = await requestPermissions();
        if (!ok) {
          logger.e('Microphone permission denied when starting recording');
          return null;
        }
      }

      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${directory.path}/audio_$timestamp.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          bitRate: 128000,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      return _currentRecordingPath;
    } catch (e) {
      logger.e('Failed to start recording: $e');
      return null;
    }
  }

  Future<Uint8List?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      await _recorder.stop();
      _isRecording = false;

      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          final audioData = await file.readAsBytes();
          await file.delete();
          return audioData;
        }
      }
      return null;
    } catch (e) {
      logger.e('Failed to stop recording: $e');
      return null;
    }
  }

  Future<void> playAudioData(Uint8List audioData) async {
    try {
      // Create a temporary file for this playback
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${directory.path}/temp_audio_$timestamp.wav');

      await tempFile.writeAsBytes(audioData);

      // Use a new AudioPlayer instance for this playback
      final player = AudioPlayer();
      _activePlayers.add(player);

      // Clean up this player and temporary file when done
      player.onPlayerComplete.listen((_) async {
        try {
          await player.stop();
        } catch (_) {}
        try {
          await player.dispose();
        } catch (_) {}
        _activePlayers.remove(player);
        try {
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
      });

      await player.play(DeviceFileSource(tempFile.path));
      logger.i('Audio playback started (ephemeral): ${tempFile.path}');
    } catch (e) {
      logger.e('Failed to play audio: $e');
      // Try best-effort cleanup of any active ephemeral players
      for (final p in List<AudioPlayer>.from(_activePlayers)) {
        try {
          await p.stop();
          await p.dispose();
        } catch (_) {}
        _activePlayers.remove(p);
      }
    }
  }

  Future<void> stopAudioPlayback() async {
    try {
      if (_isPlaying) {
        await _player.stop();
        await _cleanupAudioPlayback();
        logger.i('Audio playback stopped');
      }
    } catch (e) {
      logger.e('Error stopping audio playback: $e');
    }
  }

  Future<void> _cleanupAudioPlayback() async {
    try {
      _isPlaying = false;
      _playerCompleteSubscription?.cancel();
      _playerCompleteSubscription = null;

      // Dispose any remaining ephemeral players
      for (final p in List<AudioPlayer>.from(_activePlayers)) {
        try {
          await p.stop();
        } catch (_) {}
        try {
          await p.dispose();
        } catch (_) {}
        _activePlayers.remove(p);
      }

      if (_currentPlayingFile != null) {
        final file = File(_currentPlayingFile!);
        if (await file.exists()) {
          await file.delete();
          logger.d('Cleaned up audio file: $_currentPlayingFile');
        }
        _currentPlayingFile = null;
      }
    } catch (e) {
      logger.e('Error cleaning up audio playback: $e');
    }
  }

  Future<bool> initSpeech() async {
    _speech = stt.SpeechToText();
    final available = await _speech!.initialize(
      onError: (e) => logger.e('STT error: $e'),
      onStatus: (s) {
        logger.d('STT status: $s');
        _lastSttStatus = s;
        try {
          _sttStatusController.add(s);
        } catch (_) {}
      },
    );
    _isInitialized = available;
    return available;
  }

  Future<bool> startListening() async {
    if (_isListening) {
      logger.w('STT is already listening, ignoring start request');
      return true;
    }

    if (!await Permission.microphone.isGranted) {
      final ok = await requestPermissions();
      if (!ok) return false;
    }

    if (!_isInitialized) {
      _speech ??= stt.SpeechToText();
      final available = await _speech!.initialize(
        onError: (e) => logger.e('STT init error: $e'),
        onStatus: (s) {
          logger.d('STT init status: $s');
          _lastSttStatus = s;
          try {
            _sttStatusController.add(s);
          } catch (_) {}
        },
      );
      if (!available) {
        logger.e('Speech recognition not available');
        return false;
      }
      _isInitialized = true;
    }

    _lastTranscription = '';
    _isListening = true;

    // If currently recording, try to pause recording to avoid mic contention.
    var didPauseRecording = false;
    try {
      if (_isRecording) {
        try {
          // Record package supports pause(); if not available it will throw
          await _recorder.pause();
          didPauseRecording = true;
          logger.i('Recording paused for STT');
        } catch (e) {
          logger.w(
              'Pause not supported or failed, stopping recording before STT: $e');
          try {
            await _recorder.stop();
            _isRecording = false;
            didPauseRecording = false;
            logger.i('Recording stopped for STT');
          } catch (e2) {
            logger.e('Failed to stop recording before STT: $e2');
          }
        }
      }

      // Start listening with more conservative timeouts and explicit handling
      await _speech!.listen(
        onResult: (result) {
          final text = result.recognizedWords.trim();
          final isFinal = result.finalResult;
          logger.d('STT result: "$text" (final: $isFinal)');

          if (text.isNotEmpty) {
            _lastTranscription = text;
            _lastNonEmptyTranscription = text;
          }

          // Emit partial results frequently but avoid flooding: only emit when changed
          try {
            if (isFinal) {
              // Final result: emit and also mark last transcription
              if (text.isNotEmpty) {
                _transcriptionController.add(text);
                logger.i('Final STT result emitted: "$text"');
              }
            } else {
              // Partial result: emit when changed from previous partial
              if (text.isNotEmpty && text != _lastTranscription) {
                _transcriptionController.add(text);
                logger.d('Partial STT result emitted: "$text"');
              }
            }
          } catch (e) {
            logger.e('Error adding to transcription stream: $e');
          }
        },
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        pauseFor: const Duration(seconds: 6),
        listenFor: const Duration(seconds: 180),
      );

      // store whether we paused recording so stopListening can resume appropriately
      _pausedRecordingForStt = didPauseRecording;

      return true;
    } catch (e) {
      logger.e('Error starting STT listening: $e');
      _isListening = false;
      // try to resume recording if we paused
      if (didPauseRecording) {
        try {
          await _recorder.resume();
          _isRecording = true;
          logger.i('Recording resumed after STT failed to start');
        } catch (e2) {
          logger.e('Failed to resume recording after STT start failure: $e2');
        }
      }
      return false;
    }
  }

  Future<void> stopListening() async {
    if (!_isListening) {
      logger.w('STT is not listening, ignoring stop request');
      return;
    }

    try {
      await _speech?.stop();
      _isListening = false;

      // Wait briefly to allow engine to push final result events (if any)
      await Future.delayed(const Duration(milliseconds: 700));

      // Ensure the last captured transcription is emitted as the final result
      final finalText = _lastTranscription.trim();
      if (finalText.isNotEmpty) {
        try {
          _transcriptionController.add(finalText);
          logger.i('Final STT transcription emitted: "$finalText"');
        } catch (e) {
          logger.e('Error emitting final transcription: $e');
        }
      }

      // If we paused recording earlier, resume it now. If we had stopped it, restart a new recording
      try {
        if (_pausedRecordingForStt == true) {
          await _recorder.resume();
          _isRecording = true;
          logger.i('Recording resumed after STT');
        } else if (!_isRecording && _currentRecordingPath != null) {
          // We had stopped recording to free the mic; restart a new recording file
          final directory = await getTemporaryDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          _currentRecordingPath =
              '${directory.path}/audio_${timestamp}_resumed.wav';
          try {
            await _recorder.start(
              const RecordConfig(
                encoder: AudioEncoder.wav,
                sampleRate: 16000,
                bitRate: 128000,
              ),
              path: _currentRecordingPath!,
            );
            _isRecording = true;
            logger.i('Recording restarted after STT');
          } catch (e) {
            logger.e('Failed to restart recording after STT: $e');
          }
        }
      } catch (e) {
        logger.e(
            'Error while attempting to resume/restart recording after STT: $e');
      }
    } catch (e) {
      logger.e('STT stop error: $e');
      _isListening = false;
    }
  }

  String get lastTranscription => _lastTranscription;
  String get lastNonEmptyTranscription => _lastNonEmptyTranscription;

  bool get isRecording => _isRecording;
  bool get isListening => _isListening;
  bool get isPlaying => _isPlaying;

  Future<void> resetSTT() async {
    try {
      if (_isListening) {
        await stopListening();
      }
      _lastTranscription = '';
      _lastNonEmptyTranscription = '';
      _isInitialized = false;
      _speech = null;
      logger.i('STT state reset successfully');
    } catch (e) {
      logger.e('Error resetting STT state: $e');
    }
  }

  Future<void> dispose() async {
    await stopAudioPlayback();
    await _recorder.dispose();
    await _player.dispose();
    _recordingSubscription?.cancel();
    _playerCompleteSubscription?.cancel();
    await _transcriptionController.close();
    await _sttStatusController.close();
  }

  Stream<String> get transcriptionStream => _transcriptionController.stream;
  Stream<String> get sttStatusStream => _sttStatusController.stream;
  String get lastSttStatus => _lastSttStatus;
}
