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
  bool _isRecording = false;
  String? _currentRecordingPath;
  StreamSubscription? _recordingSubscription;
  stt.SpeechToText? _speech;
  String _lastTranscription = '';
  String _lastNonEmptyTranscription = '';
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

      // Do NOT require storage permission. We use app-internal temp directory.
      // On Android 10+ storage permission is scoped and often denied.
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
      // Ensure microphone permission before starting
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
          // Clean up the temp file
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
      // Stop any currently playing audio
      await stopAudioPlayback();

      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${directory.path}/temp_audio_$timestamp.wav');

      await tempFile.writeAsBytes(audioData);
      _currentPlayingFile = tempFile.path;
      _isPlaying = true;

      // Set up the completion listener only once
      _playerCompleteSubscription?.cancel();
      _playerCompleteSubscription = _player.onPlayerComplete.listen((_) async {
        await _cleanupAudioPlayback();
      });

      await _player.play(DeviceFileSource(tempFile.path));
      logger.i('Audio playback started: ${tempFile.path}');
    } catch (e) {
      logger.e('Failed to play audio: $e');
      await _cleanupAudioPlayback();
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
    return await _speech!.initialize(
      onError: (e) => logger.e('STT error: $e'),
      onStatus: (s) {
        logger.d('STT status: $s');
        _lastSttStatus = s;
        try {
          _sttStatusController.add(s);
        } catch (_) {}
      },
    );
  }

  Future<bool> startListening() async {
    // Prevent multiple simultaneous listening sessions
    if (_isListening) {
      logger.w('STT is already listening, ignoring start request');
      return true;
    }

    if (!await Permission.microphone.isGranted) {
      final ok = await requestPermissions();
      if (!ok) return false;
    }

    // Initialize STT only once
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

    try {
      await _speech!.listen(
        onResult: (result) {
          _lastTranscription = result.recognizedWords;
          if (_lastTranscription.isNotEmpty) {
            _lastNonEmptyTranscription = _lastTranscription;
          }
          logger.i(
              'STT result: "$_lastTranscription" (final: ${result.finalResult})');
          try {
            if (_lastTranscription.isNotEmpty) {
              _transcriptionController.add(_lastTranscription);
            }
          } catch (e) {
            logger.e('Error adding to transcription stream: $e');
          }
        },
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 60),
      );
      return true;
    } catch (e) {
      logger.e('Error starting STT listening: $e');
      _isListening = false;
      return false;
    }
  }

  /// Start listening in continuous mode - only stops when explicitly called
  /// This is for push-to-talk scenarios where STT should not auto-pause
  Future<bool> startListeningContinuous() async {
    // Prevent multiple simultaneous listening sessions
    if (_isListening) {
      logger.w('STT is already listening, ignoring start request');
      return true;
    }

    if (!await Permission.microphone.isGranted) {
      final ok = await requestPermissions();
      if (!ok) return false;
    }

    // Initialize STT only once
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

    try {
      // Use continuous listening mode with very long timeouts
      // This prevents STT from stopping prematurely during pauses
      await _speech!.listen(
        onResult: (result) {
          _lastTranscription = result.recognizedWords;
          if (_lastTranscription.isNotEmpty) {
            _lastNonEmptyTranscription = _lastTranscription;
          }
          logger.i(
              'STT continuous result: "$_lastTranscription" (final: ${result.finalResult})');
          try {
            if (_lastTranscription.isNotEmpty) {
              _transcriptionController.add(_lastTranscription);
            }
          } catch (e) {
            logger.e('Error adding to transcription stream: $e');
          }
        },
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        // Longer pause duration to avoid stopping during natural pauses
        pauseFor: const Duration(seconds: 30),
        // Extended listen duration for continuous capture
        listenFor: const Duration(minutes: 5),
      );
      logger.i('Started continuous STT listening (press-and-hold mode)');
      return true;
    } catch (e) {
      logger.e('Error starting continuous STT listening: $e');
      _isListening = false;
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
      // Allow a moment for the final result to be delivered
      await Future.delayed(const Duration(milliseconds: 800));
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
