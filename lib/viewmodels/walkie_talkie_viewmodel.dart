import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:pats_app/config.dart';
import 'package:uuid/uuid.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/user.dart';
import '../services/audio_service.dart';
import '../services/network_service.dart';
import '../services/room_code_service.dart';
import '../services/local_db_service.dart'
    if (dart.library.html) '../services/local_db_service_web.dart';

typedef UserGetter = dynamic Function();

enum ConnectionMode { server, client, disconnected }

class WalkieTalkieViewModel extends ChangeNotifier {
  final AudioService _audioService;
  final NetworkService _networkService;
  final LocalDbService _localDbService;
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
  static const bool enableAudioRecordingDuringTalk = true;
  static const int _mergeWindowMs = 6000;

  // Track active transcript per user to avoid duplicate records from partials
  final Map<String, int> _activeTranscriptionIdByUser = {};
  final Map<String, String> _lastTranscriptTextByUser = {};
  final Map<String, int> _lastTranscriptUpdatedAtByUser = {};

  // Track role assignments locally
  final Map<String, Role> _userRoles = {};
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
    required LocalDbService localDbService,
  })  : _audioService = audioService,
        _networkService = networkService,
        _localDbService = localDbService,
        _userName = userName,
        _userId = const Uuid().v4();

  List<User> get users => _users;
  bool get isTalking => _isTalking;
  Role get myRole {
    final me = _users.firstWhere(
      (u) => u.id == _userId,
      orElse: () => User(id: _userId, name: _userName),
    );
    return me.role;
  }

  String get userId => _userId;
  String get userName => _userName;
  bool get isInitialized => _isInitialized;
  ConnectionMode get connectionMode => _connectionMode;
  String? get serverIP => _serverIP;
  String? get roomCode => _roomCode;

  Future<void> initialize() async {
    try {
      logger.i('Starting initialization...');

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
    _setupNetworkListeners();
    _isInitialized = true;
    notifyListeners();
  }

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
      final trimmed = text.trim();
      logger.i('Received transcription: "$trimmed"');
      if (trimmed.isEmpty) return;
      final ts = DateTime.now().millisecondsSinceEpoch;

      // Merge logic: update existing active record for this user if within window
      final lastText = _lastTranscriptTextByUser[_userId];
      final lastUpdated = _lastTranscriptUpdatedAtByUser[_userId] ?? 0;
      final activeId = _activeTranscriptionIdByUser[_userId];
      final withinWindow = ts - lastUpdated <= _mergeWindowMs;

      String newTextToPersist = trimmed;
      bool shouldUpdate = false;
      bool shouldInsertNew = activeId == null || !withinWindow;

      if (!shouldInsertNew && lastText != null) {
        if (trimmed == lastText) {
          return;
        }
        final grows = trimmed.length >= lastText.length;
        final sharesPrefix =
            grows && trimmed.toLowerCase().startsWith(lastText.toLowerCase());
        final sharesSuffix =
            grows && trimmed.toLowerCase().endsWith(lastText.toLowerCase());
        if (!grows) {
          return;
        }
        if (sharesPrefix || sharesSuffix) {
          shouldUpdate = true;
        } else {
          shouldInsertNew = true;
        }
      }

      if (shouldInsertNew) {
        final rec = _localDbService.addTranscription(
          userId: _userId,
          userName: _userName,
          text: newTextToPersist,
          timestamp: ts,
        );
        _activeTranscriptionIdByUser[_userId] = rec.id;
        _lastTranscriptTextByUser[_userId] = newTextToPersist;
        _lastTranscriptUpdatedAtByUser[_userId] = ts;
      } else if (shouldUpdate && activeId != null) {
        _localDbService.updateTranscriptionText(
            id: activeId, newText: newTextToPersist);
        _lastTranscriptTextByUser[_userId] = newTextToPersist;
        _lastTranscriptUpdatedAtByUser[_userId] = ts;
      }

      // Broadcast to peers
      _networkService.sendTranscript(
        userId: _userId,
        userName: _userName,
        text: newTextToPersist,
        timestamp: ts,
      );
      logger.i('Broadcasted transcript: "$newTextToPersist"');
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
      final activeId = _activeTranscriptionIdByUser[userIdMsg];
      final withinWindow = ts - lastUpdated <= _mergeWindowMs;

      bool shouldInsertNew = activeId == null || !withinWindow;
      bool shouldUpdate = false;

      if (!shouldInsertNew && lastText != null) {
        if (textMsg == lastText) {
          return;
        }
        final grows = textMsg.length >= lastText.length;
        final sharesPrefix =
            grows && textMsg.toLowerCase().startsWith(lastText.toLowerCase());
        final sharesSuffix =
            grows && textMsg.toLowerCase().endsWith(lastText.toLowerCase());
        if (!grows) {
          return;
        }
        if (sharesPrefix || sharesSuffix) {
          shouldUpdate = true;
        } else {
          shouldInsertNew = true;
        }
      }

      if (shouldInsertNew) {
        final rec = _localDbService.addTranscription(
          userId: userIdMsg,
          userName: userNameMsg,
          text: textMsg,
          timestamp: ts,
        );
        _activeTranscriptionIdByUser[userIdMsg] = rec.id;
        _lastTranscriptTextByUser[userIdMsg] = textMsg;
        _lastTranscriptUpdatedAtByUser[userIdMsg] = ts;
      } else if (shouldUpdate && activeId != null) {
        _localDbService.updateTranscriptionText(id: activeId, newText: textMsg);
        _lastTranscriptTextByUser[userIdMsg] = textMsg;
        _lastTranscriptUpdatedAtByUser[userIdMsg] = ts;
      }
      logger.i('Saved/merged transcript to local DB for $userNameMsg');
    } catch (e) {
      logger.e('Error handling transcript message: $e');
    }
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
      } catch (_) {}

      resetAllRoles();

      String? photoUrl;
      try {
        final dynamic currentUser =
            (globalAuthGetter != null) ? globalAuthGetter!() : null;
        if (currentUser != null) {
          photoUrl = currentUser.photoURL as String?;
        }
      } catch (_) {}

      final selfUser = User(
          id: _userId, name: _userName, photoUrl: photoUrl, role: Role.pilot);

      if (AppConfig.useFirebaseAsServer) {
        await _networkService.setupFirebaseRoom(code, _userId);

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
      } catch (_) {}
      notifyListeners();
    }
    return success;
  }

  Future<String?> getLocalIPAddress() async {
    return await NetworkInfo().getWifiIP();
  }

  /// Start audio recording and STT listening in coordinated parallel
  Future<void> _startAudioAndSTT() async {
    _audioRecordingStarted = false;
    _sttStarted = false;
    _audioRecordingCompleter = Completer<Uint8List?>();

    try {
      // Start audio recording first (gives it priority on microphone)
      if (enableAudioRecordingDuringTalk) {
        String? recordingPath;
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
            final backoffMs = 300 * (attempt + 1);
            logger.w(
                'Recorder start failed (attempt ${attempt + 1}): $e. Retrying in ${backoffMs}ms');
            await Future.delayed(Duration(milliseconds: backoffMs));
          }
        }

        if (!_audioRecordingStarted) {
          logger.e('Failed to start recorder after retries');
          _lastError =
              'Audio recording failed to start. Please check microphone permissions.';
          _audioRecordingCompleter?.completeError('Recording failed to start');
          throw Exception('Recording failed to start');
        }

        // Give recorder time to stabilize
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Start STT listening in continuous mode
      bool sttStarted = false;
      try {
        logger.i('Starting STT listening...');
        sttStarted = await _audioService
            .startListeningContinuous()
            .timeout(const Duration(seconds: 5));

        if (sttStarted) {
          logger.i('STT started successfully');
          _sttStarted = true;
        }
      } catch (e) {
        logger.e('STT start timeout or error: $e');
        sttStarted = false;
      }

      if (!_sttStarted) {
        logger.e('Failed to start STT');
        _lastError = 'Failed to start speech recognition';

        // Stop recorder if it was started but STT failed
        if (_audioRecordingStarted) {
          try {
            await _audioService.stopRecording();
            _audioRecordingStarted = false;
          } catch (e) {
            logger.e('Error stopping recorder after STT failure: $e');
          }
        }

        _audioRecordingCompleter?.completeError('STT failed to start');
        throw Exception('STT failed to start');
      }

      logger.i('Audio recording and STT started in parallel');
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

    // Prevent inspectors from starting to talk
    if (myRole == Role.inspector) {
      logger.w('Inspectors are not allowed to speak');
      _lastError = 'Inspectors are not allowed to speak';
      notifyListeners();
      return;
    }

    if (_isTalking || !_networkService.isConnected) {
      logger.w(
          'Cannot start talking: already talking=${_isTalking}, connected=${_networkService.isConnected}');
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

      // Make sure any previous audio session is cleaned up
      await _audioService.stopListening();
      if (_audioService.isRecording) {
        await _audioService.stopRecording();
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

  /// Role selection disabled - always returns false
  Future<bool> claimRole(Role desired) async {
    return false;
  }

  /// Role release disabled - always returns false
  Future<bool> releaseRole() async {
    return false;
  }

  void _updateMyRoleLocally(Role role) {
    // Role updates disabled
  }

  /// Get the role for a specific user - always returns pilot
  Role getUserRole(String userId) {
    return Role.pilot;
  }

  /// Role availability check disabled - always returns false
  bool isRoleAvailable(Role role) {
    return false;
  }

  /// Reset all roles to inspector
  void resetAllRoles() {
    _userRoles.clear();
    for (final user in _users) {
      _userRoles[user.id] = Role.inspector;
    }
    notifyListeners();
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
        logger.w('No audio data to send');
      }

      // Get final transcription
      String transcript = '';
      try {
        transcript = _audioService.lastTranscription.trim();
        if (transcript.isEmpty) {
          transcript = _audioService.lastNonEmptyTranscription.trim();
        }
      } catch (e) {
        logger.e('Error retrieving final transcription: $e');
        _lastError = 'Error processing final transcription';
        notifyListeners();
      }

      // Save and broadcast final transcription if available
      if (transcript.isNotEmpty) {
        try {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final activeId = _activeTranscriptionIdByUser[_userId];

          if (activeId != null) {
            await _localDbService.updateTranscriptionText(
                id: activeId, newText: transcript);
            _lastTranscriptTextByUser[_userId] = transcript;
            _lastTranscriptUpdatedAtByUser[_userId] = ts;
          } else {
            final rec = await _localDbService.addTranscription(
              userId: _userId,
              userName: _userName,
              text: transcript,
              timestamp: ts,
            );
            _activeTranscriptionIdByUser[_userId] = rec.id;
            _lastTranscriptTextByUser[_userId] = transcript;
            _lastTranscriptUpdatedAtByUser[_userId] = ts;
          }

          // Broadcast transcript to other users
          _networkService.sendTranscript(
            userId: _userId,
            userName: _userName,
            text: transcript,
            timestamp: ts,
          );
        } catch (e) {
          logger.e('Error saving/sending transcript: $e');
          _lastError = 'Failed to save transcription';
          notifyListeners();
        }
      }

      // Clear state for next session
      _activeTranscriptionIdByUser.remove(_userId);
      _lastTranscriptTextByUser.remove(_userId);
      _lastTranscriptUpdatedAtByUser.remove(_userId);
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

      // Clear any active transcriptions
      _activeTranscriptionIdByUser.remove(_userId);
      _lastTranscriptTextByUser.remove(_userId);
      _lastTranscriptUpdatedAtByUser.remove(_userId);
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
      _activeTranscriptionIdByUser.clear();
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
