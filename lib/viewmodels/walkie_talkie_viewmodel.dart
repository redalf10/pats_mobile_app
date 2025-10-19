import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:pats_app/config.dart';
import 'package:pats_app/models/transcription.dart';
import 'package:uuid/uuid.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/user.dart';
import '../services/audio_service.dart';
import '../services/network_service.dart';
import '../services/room_code_service.dart';
import '../services/firebase_service.dart'
    if (dart.library.html) '../services/local_db_service_web.dart';
import '../services/gemini_service.dart';

typedef UserGetter = dynamic Function();

enum ConnectionMode { server, client, disconnected }

class WalkieTalkieViewModel extends ChangeNotifier {
  final AudioService _audioService;
  final NetworkService _networkService;
  final FirebaseDbService _localDbService;
  final GeminiService _geminiService;
  final String _userId;
  final String _userName;
  final RoomCodeService _roomCodeService = RoomCodeService();

  List<User> _users = [];
  bool _isTalking = false;
  bool _isInitialized = false;
  ConnectionMode _connectionMode = ConnectionMode.disconnected;
  String? _serverIP;
  String? _roomCode;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _userUpdateSubscription;
  Logger logger = Logger();

  // Audio and STT coordination
  static const int _mergeWindowMs = 6000;

  // Track active transcript per user to avoid duplicate records from partials
  final Map<String, String> _activeTranscriptionKeyByUser = {};
  final Map<String, String> _lastTranscriptTextByUser = {};
  final Map<String, int> _lastTranscriptUpdatedAtByUser = {};

  String? _lastError;
  int _talkStartedAtMs = 0;

  // Audio session tracking - ensures audio and STT work in sync
  Completer<Uint8List?>? _audioRecordingCompleter;
  bool _audioRecordingStarted = false;
  bool _sttStarted = false;

  String? get lastError => _lastError;

  // Optional hook to get current auth user without importing firebase_auth here
  static UserGetter? globalAuthGetter;

  WalkieTalkieViewModel({
    required String userName,
    required AudioService audioService,
    required NetworkService networkService,
    required FirebaseDbService localDbService,
    required GeminiService geminiService,
  })  : _audioService = audioService,
        _networkService = networkService,
        _localDbService = localDbService,
        _geminiService = geminiService,
        _userName = userName,
        _userId = const Uuid().v4();

  List<User> get users => _users;
  bool get isTalking => _isTalking;

  String get userId => _userId;
  String get userName => _userName;
  bool get isInitialized => _isInitialized;
  ConnectionMode get connectionMode => _connectionMode;
  String? get serverIP => _serverIP;
  String? get roomCode => _roomCode;

  Future<void> initialize() async {
    try {
      logger.i('Starting initialization...');

      // CRITICAL FIX: Initialize the database service FIRST
      try {
        await _localDbService.init();
        logger.i('Database service initialized');
      } catch (e) {
        logger.e('Error initializing database service: $e');
        // Continue even if DB init fails
      }

      final permissionCompleter = Completer<bool>();

      logger.i('Requesting permissions...');
      try {
        final hasPermission = await _audioService.requestPermissions();
        logger.i('Permissions result: $hasPermission');
        permissionCompleter.complete(hasPermission);
      } catch (e) {
        logger.e('Error requesting permissions: $e');
        permissionCompleter.complete(false);
      }

      final permissionGranted = await permissionCompleter.future;
      if (!permissionGranted) {
        logger.e('Required permissions denied');
        _lastError =
            'Microphone permissions are required for full functionality';
        notifyListeners();
      }

      try {
        final sttOk = await _audioService.initSpeech();
        logger.i('STT initialize result: $sttOk');
        if (!sttOk) {
          _lastError = 'Speech recognition initialization failed';
          notifyListeners();
        }
      } catch (e) {
        logger.e('Error initializing STT: $e');
        _lastError = 'Failed to initialize speech recognition: $e';
        notifyListeners();
      }

      logger.i('Setting up network listeners...');
      _setupNetworkListeners();

      logger.i('Initialization complete');
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      logger.e('Error during initialization: $e');
      _isInitialized = true;
      notifyListeners();
      rethrow;
    }
  }

  void forceInitialize() {
    logger.i('Force initializing app...');

    // CRITICAL FIX: Initialize database service
    _localDbService.init().then((_) {
      logger.i('Database service initialized (force init)');
    }).catchError((e) {
      logger.e('Error initializing database service (force init): $e');
    });

    _setupNetworkListeners();
    _isInitialized = true;
    notifyListeners();
  }

  // void forceInitialize() {
  //   logger.i('Force initializing app...');
  //   _setupNetworkListeners();
  //   _isInitialized = true;
  //   notifyListeners();
  // }

  void _setupNetworkListeners() {
    _messageSubscription = _networkService.messageStream.listen((message) {
      switch (message['type'] as String) {
        case 'audio':
          _handleAudioMessage(message);
          break;
        case 'transcript':
          _handleTranscriptMessage(message);
          break;
      }
    });

    _userUpdateSubscription = _networkService.userUpdateStream.listen((users) {
      logger.i('User list updated: ${users.length} users');
      for (final user in users) {
        logger
            .d('  - ${user.name} (${user.id}) - speaking: ${user.isSpeaking}');
      }
      _users = users;
      notifyListeners();
    });

    // Broadcast our partial transcripts in near real-time
    _audioService.transcriptionStream.listen((text) {
      String trimmed = text.trim();
      logger.i('🎤 Received transcription: "$trimmed"');
      logger.i(
          '🎤 Database service initialized: ${_localDbService.isInitialized}');
      logger.i('🎤 Database service room set: ${_localDbService.isRoomSet}');
      logger.i(
          '🎤 Database service room path: ${_localDbService.currentRoomPath}');

      if (trimmed.isEmpty) {
        logger.d('🎤 Empty transcription, skipping');
        return;
      }

      // FIXED: Filter out very short transcriptions that are likely incomplete
      if (trimmed.length < 2) {
        logger.d('🎤 Transcription too short, skipping: "$trimmed"');
        return;
      }

      // FIXED: Limit maximum transcription length to prevent excessive text accumulation
      if (trimmed.length > 1000) {
        logger.w(
            '🎤 Transcription too long (${trimmed.length} chars), truncating');
        trimmed = trimmed.substring(0, 1000) + '...';
      }

      final ts = DateTime.now().millisecondsSinceEpoch;

      // Check for duplicate transcripts to prevent spam
      final lastText = _lastTranscriptTextByUser[_userId];
      final lastUpdated = _lastTranscriptUpdatedAtByUser[_userId] ?? 0;
      final timeDiff = ts - lastUpdated;

      // Skip if EXACTLY same text within 1 second (prevents rapid duplicate saves)
      if (lastText == trimmed && timeDiff < 1000) {
        logger.d(
            '🎤 Exact duplicate transcription detected, skipping: "$trimmed"');
        return;
      }

      // FIXED: Skip if text is identical to last processed text (prevents accumulation)
      if (lastText == trimmed) {
        logger.d(
            '🎤 Identical transcription to last processed, skipping: "$trimmed"');
        return;
      }

      try {
        logger.i('🎤 Processing transcription: "$trimmed"');

        // Check if we should update existing transcription or create new one
        final activeKey = _activeTranscriptionKeyByUser[_userId];
        final withinWindow = timeDiff < _mergeWindowMs;

        if (activeKey != null && withinWindow && lastText != null) {
          // FIXED: Improved logic for updating existing transcription
          final grows = trimmed.length >= lastText.length;
          final sharesPrefix =
              grows && trimmed.toLowerCase().startsWith(lastText.toLowerCase());
          final isImprovement = grows &&
              (trimmed.length > lastText.length || trimmed != lastText);

          // FIXED: More strict conditions to prevent single word updates
          final significantImprovement = trimmed.length > lastText.length + 3 ||
              (trimmed.length > lastText.length && trimmed.contains(lastText));

          if (isImprovement &&
              significantImprovement &&
              (sharesPrefix || trimmed.contains(lastText))) {
            logger.i(
                '🎤 Updating existing transcription: "$lastText" -> "$trimmed"');
            _localDbService.updateTranscriptionText(
                transcriptionKey: activeKey, newText: trimmed);
            _lastTranscriptTextByUser[_userId] = trimmed;
            _lastTranscriptUpdatedAtByUser[_userId] = ts;
            logger.i('✅ Updated transcription: "$trimmed"');

            // FIXED: Don't broadcast transcript here - it's already stored in Firebase
            // The updateTranscriptionText() already updates it in the transcripts table
            logger.i(
                'Updated transcript in Firebase, will be synced to other clients');
            return;
          }
        }

        // FIXED: Only create new transcription if it's significantly different
        // This prevents single word transcriptions from creating new records
        if (lastText != null &&
            trimmed.length <= lastText.length + 2 &&
            trimmed.toLowerCase().contains(lastText.toLowerCase())) {
          logger
              .d('🎤 Transcription too similar to last, skipping: "$trimmed"');
          return;
        }

        // Create new transcription record for new/different content
        final transcription = _localDbService.addTranscription(
          userId: _userId,
          userName: _userName,
          text: trimmed,
          timestamp: ts,
        );
        logger.i(
            '✅ Saved new transcription to database: "$trimmed" (ID: ${transcription.id})');

        // Store the key for potential updates
        final key = _localDbService.getLastTranscriptionKey();
        if (key != null) {
          _activeTranscriptionKeyByUser[_userId] = key;
          _lastTranscriptTextByUser[_userId] = trimmed;
          _lastTranscriptUpdatedAtByUser[_userId] = ts;
          logger.i('🔑 Stored transcription key: $key');
        }

        // FIXED: Don't broadcast transcript here - it's already stored in Firebase
        // The FirebaseDbService.addTranscription() already stores it in the transcriptions table
        // and other clients will receive it via the Firebase listener
        logger.i(
            '📡 Transcript stored in Firebase, will be synced to other clients');
      } catch (e) {
        logger.e('❌ Error saving/broadcasting transcription: $e');
        logger.e('❌ Stack trace: ${StackTrace.current}');
        // FIXED: Don't broadcast transcript here either - avoid duplicates
        logger
            .w('Database save failed, transcript not synced to other clients');
      }
    });

    // Observe STT status for diagnostics only
    _audioService.sttStatusStream.listen((status) {
      logger.d('VM observed STT status: $status');
    });
  }

  void _handleTranscriptMessage(Map<String, dynamic> message) {
    try {
      final String userIdMsg = message['userId'] as String? ?? '';
      final String userNameMsg = message['userName'] as String? ?? 'Unknown';
      final String textMsg = (message['text'] as String? ?? '').trim();
      final int ts = (message['timestamp'] as int?) ??
          DateTime.now().millisecondsSinceEpoch;

      logger.i('Received transcript message from $userNameMsg: "$textMsg"');

      if (textMsg.isEmpty) return;

      final lastText = _lastTranscriptTextByUser[userIdMsg];
      final lastUpdated = _lastTranscriptUpdatedAtByUser[userIdMsg] ?? 0;
      final activeKey = _activeTranscriptionKeyByUser[userIdMsg];
      final withinWindow = ts - lastUpdated <= _mergeWindowMs;

      bool shouldInsertNew = activeKey == null || !withinWindow;
      bool shouldUpdate = false;

      if (!shouldInsertNew && lastText != null) {
        if (textMsg == lastText) return;

        final grows = textMsg.length >= lastText.length;
        final sharesPrefix =
            grows && textMsg.toLowerCase().startsWith(lastText.toLowerCase());
        final sharesSuffix =
            grows && textMsg.toLowerCase().endsWith(lastText.toLowerCase());

        if (!grows) return;

        if (sharesPrefix || sharesSuffix) {
          shouldUpdate = true;
        } else {
          shouldInsertNew = true;
        }
      }

      if (shouldInsertNew) {
        try {
          final rec = _localDbService.addTranscription(
            userId: userIdMsg,
            userName: userNameMsg,
            text: textMsg,
            timestamp: ts,
          );
          // Store the Firebase key, not the ID
          _activeTranscriptionKeyByUser[userIdMsg] = _getTranscriptionKey(rec);
          _lastTranscriptTextByUser[userIdMsg] = textMsg;
          _lastTranscriptUpdatedAtByUser[userIdMsg] = ts;
          logger
              .i('Saved received transcription from $userNameMsg: "$textMsg"');
        } catch (e) {
          logger.e('Error saving received transcription: $e');
        }
      } else if (shouldUpdate && activeKey != null) {
        try {
          // Use the key directly for updates
          _localDbService.updateTranscriptionText(
              transcriptionKey: activeKey, newText: textMsg);
          _lastTranscriptTextByUser[userIdMsg] = textMsg;
          _lastTranscriptUpdatedAtByUser[userIdMsg] = ts;
          logger.i('Updated transcription from $userNameMsg: "$textMsg"');
        } catch (e) {
          logger.e('Error updating received transcription: $e');
        }
      }
    } catch (e) {
      logger.e('Error handling transcript message: $e');
    }
  }

  // Helper method to get transcription key
  String _getTranscriptionKey(Transcription transcription) {
    // Try to get the key by ID first
    final keyById = _localDbService.getTranscriptionKeyById(transcription.id);
    if (keyById != null) {
      return keyById;
    }

    // Fallback to last transcription key if available
    final lastKey = _localDbService.getLastTranscriptionKey();
    if (lastKey != null) {
      return lastKey;
    }

    // Final fallback
    return transcription.id.toString();
  }

  void _handleAudioMessage(Map<String, dynamic> message) {
    try {
      final userId = message['userId'] as String?;
      final audioDataBase64 = message['data'] as String;

      if (userId == _userId) {
        logger.d('Ignoring own audio message');
        return;
      }

      logger.i('Received audio message from user: $userId');
      logger.d('Audio data length: ${audioDataBase64.length} characters');

      final audioData = base64Decode(audioDataBase64);
      logger.d('Decoded audio data length: ${audioData.length} bytes');

      _audioService.playAudioData(Uint8List.fromList(audioData));
      logger.i('Audio playback initiated');
    } catch (e) {
      logger.e('Failed to handle audio message: $e');
    }
  }

  Future<String?> startAsServer() async {
    logger.i(
        'Starting as server with Firebase mode: ${AppConfig.useFirebaseAsServer}');
    final serverIP = await _networkService.startServer();
    logger.i('Server started, IP: $serverIP');
    if (serverIP != null) {
      _connectionMode = ConnectionMode.server;
      _serverIP = serverIP;

      final code = _roomCodeService.generateRoomCode();
      logger.i('Generated room code: $code');
      _roomCode = code;

      if (!AppConfig.useFirebaseAsServer) {
        await _roomCodeService.setRoomCode(code, serverIP);
      }
      try {
        await _localDbService.setRoom(code);
        logger.i('Database service connected to room: $code');
      } catch (e) {
        logger.e('Error setting room in database service: $e');
      }

      String? photoUrl;
      try {
        final dynamic currentUser =
            (globalAuthGetter != null) ? globalAuthGetter!() : null;
        if (currentUser != null) {
          photoUrl = currentUser.photoURL as String?;
        }
      } catch (_) {}

      final selfUser = User(id: _userId, name: _userName, photoUrl: photoUrl);
      logger.i('🏠 Creating self user: ${selfUser.name} (${selfUser.id})');

      if (AppConfig.useFirebaseAsServer) {
        await _networkService.setupFirebaseRoom(code, _userId);

        // Add self user to Firebase room
        await _networkService.addSelfUserToFirebase(selfUser);

        _networkService.sendMessage({
          'type': 'join',
          'user': selfUser.toJson(),
        });
      } else {
        _networkService.addSelfUser(selfUser);
      }

      _users = [selfUser];
      notifyListeners();
      return code;
    }
    return null;
  }

  Future<bool> connectToServer(String code) async {
    String? photoUrl;
    try {
      final dynamic currentUser =
          (globalAuthGetter != null) ? globalAuthGetter!() : null;
      if (currentUser != null) {
        photoUrl = currentUser.photoURL as String?;
      }
    } catch (_) {}

    logger.i('Attempting to connect to room code: $code');

    final String serverTarget = code;

    final success = await _networkService.connectToServer(
      serverTarget,
      _userId,
      _userName,
      photoUrl: photoUrl,
    );

    logger.i('Connection result: $success');
    if (success) {
      _connectionMode = ConnectionMode.client;
      _serverIP = serverTarget;
      _roomCode = code;
      try {
        await _localDbService.setRoom(code);
        logger.i('Database service connected to room: $code');
      } catch (e) {
        logger.e('Error setting room in database service: $e');
      }
      notifyListeners();
    }
    return success;
  }

  Future<String?> getLocalIPAddress() async {
    return await NetworkInfo().getWifiIP();
  }

  /// Start audio recording and STT listening in coordinated manner
  /// FIXED: Start both STT and audio recording simultaneously for dual functionality
  Future<void> _startAudioAndSTT() async {
    _audioRecordingStarted = false;
    _sttStarted = false;
    _audioRecordingCompleter = Completer<Uint8List?>();

    try {
      // Start STT for transcription first
      logger.i('Starting STT listening...');
      bool sttStarted = false;
      try {
        sttStarted = await _audioService
            .startListeningContinuous()
            .timeout(const Duration(seconds: 5));

        if (sttStarted) {
          logger.i('STT started successfully');
          _sttStarted = true;
          // Add a small delay to let STT stabilize before starting recording
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (e) {
        logger.e('STT start timeout or error: $e');
        sttStarted = false;
      }

      // Start audio recording for audio transmission
      logger.i('Starting audio recording...');
      String? recordingPath;

      // Try the fallback method first
      try {
        logger.i('Attempting to start recording with fallback...');
        recordingPath = await _audioService
            .startRecordingWithFallback()
            .timeout(const Duration(seconds: 5));

        if (recordingPath != null) {
          logger
              .i('Recorder started successfully with fallback: $recordingPath');
          _audioRecordingStarted = true;
        }
      } catch (e) {
        logger.w('Recording with fallback failed: $e');
      }

      // If fallback failed, try multiple attempts
      if (recordingPath == null) {
        for (int attempt = 0; attempt < 3 && recordingPath == null; attempt++) {
          try {
            logger.i('Starting recorder (attempt ${attempt + 1})...');
            recordingPath = await _audioService
                .startRecording()
                .timeout(const Duration(seconds: 3));

            if (recordingPath != null) {
              logger.i('Recorder started successfully: $recordingPath');
              _audioRecordingStarted = true;
            }
          } catch (e) {
            logger.w('Recorder start failed (attempt ${attempt + 1}): $e');
            if (recordingPath == null && attempt < 2) {
              final backoffMs = 500 * (attempt + 1);
              logger.w('Retrying in ${backoffMs}ms');
              await Future.delayed(Duration(milliseconds: backoffMs));
            }
          }
        }
      }

      // Check if at least one service started successfully
      if (!_sttStarted && !_audioRecordingStarted) {
        logger.e('Failed to start both STT and audio recording');
        _lastError = 'Failed to start speech recognition and audio recording';
        _audioRecordingCompleter
            ?.completeError('Both services failed to start');
        throw Exception('Both STT and audio recording failed to start');
      } else if (!_sttStarted) {
        logger.w('STT failed to start, but audio recording is working');
        _lastError = 'Speech recognition failed, but audio recording is active';
      } else if (!_audioRecordingStarted) {
        logger.w('Audio recording failed to start, but STT is working');
        _lastError = 'Audio recording failed, but speech recognition is active';
      }

      logger.i(
          'Audio/STT services started - STT: $_sttStarted, Recording: $_audioRecordingStarted');
    } catch (e) {
      logger.e('Error starting audio and STT: $e');
      _audioRecordingCompleter?.completeError(e);
      rethrow;
    }
  }

  /// Stop audio recording and STT, coordinating cleanup
  Future<Uint8List?> _stopAudioAndSTT() async {
    Uint8List? audioData;

    try {
      // Stop STT first to finalize transcription
      if (_sttStarted) {
        try {
          logger.i('Stopping STT...');
          await _audioService.stopListening();
          _sttStarted = false;
          logger.i('STT stopped');
        } catch (e) {
          logger.e('Error stopping STT: $e');
          _lastError = 'Error processing final transcription';
        }
      }

      // Stop audio recording and retrieve data
      if (_audioRecordingStarted) {
        try {
          logger.i('Stopping audio recording...');
          audioData = await _audioService
              .stopRecording()
              .timeout(const Duration(seconds: 3));
          _audioRecordingStarted = false;

          if (audioData != null && audioData.isNotEmpty) {
            logger.i('Audio data retrieved: ${audioData.length} bytes');
          }
        } catch (e) {
          logger.e('Error stopping recording: $e');
          _lastError = 'Failed to process audio recording';
        }
      }

      return audioData;
    } catch (e) {
      logger.e('Error stopping audio and STT: $e');
      return null;
    }
  }

  Future<void> startTalking() async {
    // Clear any previous error state
    _lastError = null;

    if (_isTalking || !_networkService.isConnected) {
      logger.w(
          'Cannot start talking: already talking=$_isTalking, connected=${_networkService.isConnected}');
      _lastError = !_networkService.isConnected
          ? 'Not connected to a room'
          : 'Already in talking mode';
      notifyListeners();
      return;
    }

    // Add debounce to prevent rapid toggling
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_talkStartedAtMs > 0 && now - _talkStartedAtMs < 1000) {
      logger.w('Preventing rapid toggle of talk state');
      return;
    }

    try {
      // Set talking state
      _talkStartedAtMs = now;
      _isTalking = true;
      notifyListeners();

      // FIXED: Clear previous transcription state to prevent carry-over
      _activeTranscriptionKeyByUser.remove(_userId);
      _lastTranscriptTextByUser.remove(_userId);
      _lastTranscriptUpdatedAtByUser.remove(_userId);

      // FIXED: Make sure any previous audio session is cleaned up properly
      try {
        await _audioService.stopListening();
        if (_audioService.isRecording) {
          await _audioService.stopRecording();
        }
        // FIXED: Reset STT state to prevent carry-over from previous sessions
        await _audioService.resetSTT();

        // FIXED: Clear all transcription state to prevent text accumulation
        _activeTranscriptionKeyByUser.clear();
        _lastTranscriptTextByUser.clear();
        _lastTranscriptUpdatedAtByUser.clear();

        logger.i(
            'Previous audio session cleaned up and transcription state reset');
      } catch (e) {
        logger.w('Error cleaning up previous audio session: $e');
      }

      // Start audio recording and STT in coordinated parallel
      await _startAudioAndSTT();

      // Update speaking status after both services are running
      try {
        _networkService.updateSpeakingStatus(_userId, true);
        logger.i('Speaking status updated');
      } catch (e) {
        logger.e('Failed to update speaking status: $e');
      }
    } catch (e) {
      logger.e('Error starting talking: $e');
      _lastError = 'Failed to start talking mode: $e';
      await _cleanupTalkingState();
    }
  }

  Future<void> stopTalking() async {
    if (!_isTalking) {
      logger.w('Cannot stop talking: not currently talking');
      return;
    }

    try {
      // Update UI state immediately
      _isTalking = false;
      _lastError = null;
      notifyListeners();

      // Update speaking status first
      _networkService.updateSpeakingStatus(_userId, false);

      // Stop audio recording and STT in coordinated manner
      final audioData = await _stopAudioAndSTT();

      // Send audio data if available
      if (audioData != null && audioData.isNotEmpty) {
        try {
          logger.i(
              'Sending audio data: [${audioData.length} bytes from user $_userId]');
          _networkService.sendAudioData(audioData, _userId);
          logger.i('Audio data sent successfully');
        } catch (e) {
          logger.e('Error sending audio data: $e');
          _lastError = 'Failed to send audio data';
          notifyListeners();
        }
      } else {
        logger.w('No audio data to send - audio recording may have failed');
        if (!_audioRecordingStarted) {
          logger.w('Audio recording was not started during this session');
        }
      }

      // Get final transcription
      String transcript = '';
      try {
        transcript = _audioService.lastTranscription.trim();
        if (transcript.isEmpty) {
          transcript = _audioService.lastNonEmptyTranscription.trim();
        }
        logger.i('🎤 Final transcription retrieved: "$transcript"');
      } catch (e) {
        logger.e('Error retrieving final transcription: $e');
        _lastError = 'Error processing final transcription';
        notifyListeners();
      }

      // Use Gemini for more accurate final transcription if audio data is available
      // Only use Gemini if the current transcript is empty or very short
      if (audioData != null && audioData.isNotEmpty && transcript.length < 10) {
        try {
          final geminiTranscript =
              await _geminiService.transcribeAudio(audioData);
          if (geminiTranscript != null && geminiTranscript.isNotEmpty) {
            final geminiTrimmed = geminiTranscript.trim();
            // Only use Gemini result if it's significantly different and longer
            if (geminiTrimmed.length > transcript.length * 1.5) {
              transcript = geminiTrimmed;
              logger.i('Used Gemini transcription: "$transcript"');
            } else {
              logger.i(
                  'Gemini transcription not significantly better, keeping STT result');
            }
          }
        } catch (e) {
          logger.e('Error transcribing with Gemini: $e');
          // Fall back to speech_to_text transcript
        }
      }

      // FIXED: Save and broadcast final transcription if available
      if (transcript.isNotEmpty) {
        try {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final activeKey = _activeTranscriptionKeyByUser[_userId];

          if (activeKey != null) {
            // FIXED: Always update final transcription to ensure completeness
            final currentText = _lastTranscriptTextByUser[_userId] ?? '';
            if (transcript != currentText) {
              _localDbService.updateTranscriptionText(
                  transcriptionKey: activeKey, newText: transcript);
              _lastTranscriptTextByUser[_userId] = transcript;
              _lastTranscriptUpdatedAtByUser[_userId] = ts;
              logger.i('Updated final transcription: "$transcript"');

              // FIXED: Don't broadcast transcript here - it's already stored in Firebase
              // The updateTranscriptionText() already updates it in the transcriptions table
              logger.i(
                  'Final transcript updated in Firebase, will be synced to other clients');
            } else {
              logger.i(
                  'Final transcription same as current, skipping update: "$transcript"');
            }
          } else {
            // FIXED: Always create final transcription if no active key exists
            final rec = _localDbService.addTranscription(
              userId: _userId,
              userName: _userName,
              text: transcript,
              timestamp: ts,
            );
            _activeTranscriptionKeyByUser[_userId] = _getTranscriptionKey(rec);
            _lastTranscriptTextByUser[_userId] = transcript;
            _lastTranscriptUpdatedAtByUser[_userId] = ts;
            logger.i('Saved final transcription: "$transcript"');

            // FIXED: Don't broadcast transcript here - it's already stored in Firebase
            // The addTranscription() already stores it in the transcriptions table
            logger.i(
                'Final transcript saved in Firebase, will be synced to other clients');
          }
        } catch (e) {
          logger.e('Error saving/sending transcript: $e');
          // FIXED: Don't broadcast transcript here either - avoid duplicates
          logger.w(
              'Database save failed, final transcript not synced to other clients');
        }
      } else {
        logger.w('No final transcription available');
      }

      // Delay clearing state to allow UI to update properly
      Future.delayed(const Duration(milliseconds: 500), () {
        _activeTranscriptionKeyByUser.remove(_userId);
        _lastTranscriptTextByUser.remove(_userId);
        _lastTranscriptUpdatedAtByUser.remove(_userId);
      });

      // Clean up any duplicate transcriptions that might have been created
      _localDbService.removeDuplicateTranscriptions();

      // Also run cleanup after a short delay to catch any late duplicates
      Future.delayed(const Duration(seconds: 2), () {
        _localDbService.removeDuplicateTranscriptions();
      });
    } catch (e) {
      logger.e('Error stopping talking: $e');
      _lastError = 'Error stopping talk mode: $e';
      // Ensure cleanup happens even if there's an error
      await _cleanupTalkingState();
    }
  }

  Future<void> _cleanupTalkingState() async {
    _isTalking = false;
    notifyListeners();

    try {
      // Update speaking status first
      _networkService.updateSpeakingStatus(_userId, false);

      // Stop recording if active
      if (_audioRecordingStarted) {
        try {
          await _audioService
              .stopRecording()
              .timeout(const Duration(seconds: 2));
          _audioRecordingStarted = false;
        } catch (e) {
          logger.e('Error stopping recording: $e');
        }
      }

      // Stop STT if active
      if (_sttStarted) {
        try {
          await _audioService
              .stopListening()
              .timeout(const Duration(seconds: 2));
          _sttStarted = false;
        } catch (e) {
          logger.e('Error stopping STT: $e');
        }
      }

      // Reset all state tracking
      _talkStartedAtMs = 0;
      _lastError = null;

      // FIXED: Clear ALL transcription state to prevent text accumulation
      _activeTranscriptionKeyByUser.clear();
      _lastTranscriptTextByUser.clear();
      _lastTranscriptUpdatedAtByUser.clear();

      // FIXED: Reset STT state to prevent carry-over
      try {
        await _audioService.resetSTT();
        logger.i('STT state reset during cleanup');
      } catch (e) {
        logger.w('Error resetting STT during cleanup: $e');
      }
    } catch (e) {
      logger.e('Error during cleanup: $e');
    } finally {
      _isTalking = false;
      notifyListeners();
    }
  }

  Future<void> resetTalkingState() async {
    logger.i('Resetting talking state...');
    try {
      if (_isTalking) {
        await _cleanupTalkingState();
      }
      await _audioService.resetSTT();
      _activeTranscriptionKeyByUser.clear();
      _lastTranscriptTextByUser.clear();
      _lastTranscriptUpdatedAtByUser.clear();
      _lastError = null;
      _audioRecordingStarted = false;
      _sttStarted = false;
      logger.i('Talking state reset successfully');
    } catch (e) {
      logger.e('Error resetting talking state: $e');
      _lastError = 'Failed to reset talking state: $e';
    } finally {
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_connectionMode != ConnectionMode.disconnected) {
      await resetTalkingState();
      _networkService.leaveRoom(_userId);
      await _networkService.disconnect();
      _connectionMode = ConnectionMode.disconnected;
      _serverIP = null;
      _users.clear();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _userUpdateSubscription?.cancel();
    _audioService.dispose();
    _networkService.disconnect();
    super.dispose();
  }
}
