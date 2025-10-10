import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
  // Allow recording alongside STT; a short delay mitigates mic contention
  static const bool enableAudioRecordingDuringTalk = true;
  // Merge window for grouping partial transcripts into a single record
  static const int _mergeWindowMs = 3000; // Reduced to 3 seconds
  // Track active transcript per user to avoid duplicate records from partials
  final Map<String, int> _activeTranscriptionIdByUser = {};
  final Map<String, String> _lastTranscriptTextByUser = {};
  final Map<String, int> _lastTranscriptUpdatedAtByUser = {};
  // Track whether we're processing a final transcript
  // Track role assignments locally
  final Map<String, Role> _userRoles = {};
  String? _lastError;
  // Reserved for future adaptive logic; currently unused
  // ignore: unused_field
  int _talkStartedAtMs = 0;

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

      // Use a Completer to handle the permission result properly
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
        // Emit an error state that UI can handle
        _lastError =
            'Microphone permissions are required for full functionality';
        notifyListeners();
      }

      // Initialize STT engine with proper error handling
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
      // Still mark as initialized so the app doesn't stay stuck
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

      // If this is a significantly larger transcript, treat it as final
      final significantWordGrowth = lastText != null &&
          trimmed.split(' ').length > lastText.split(' ').length + 2;
      final withinWindow = ts - lastUpdated <= _mergeWindowMs;

      String newTextToPersist = trimmed;
      bool shouldUpdate = false;
      bool shouldInsertNew = activeId == null || !withinWindow;

      if (!shouldInsertNew && lastText != null) {
        if (trimmed == lastText) {
          // No change; do nothing to avoid duplicates
          return;
        }
        // If STT is building up, the new text often includes previous text as prefix
        final grows = trimmed.length >= lastText.length;
        final sharesPrefix =
            grows && trimmed.toLowerCase().startsWith(lastText.toLowerCase());
        final sharesSuffix =
            grows && trimmed.toLowerCase().endsWith(lastText.toLowerCase());
        // Also handle occasional regressions: ignore shorter regressions
        if (!grows) {
          // Ignore shorter partials to avoid flicker/duplicates
          return;
        }
        // If this partial is substantially larger, treat as update
        if (significantWordGrowth) {
          shouldUpdate = true;
        } else if (sharesPrefix || sharesSuffix) {
          shouldUpdate = true;
        } else {
          // If content diverged, start a new record
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

      // Broadcast to peers (idempotency handled on their side with same merge logic)
      _networkService.sendTranscript(
        userId: _userId,
        userName: _userName,
        text: newTextToPersist,
        timestamp: ts,
      );
      logger.i('Broadcasted transcript: "$newTextToPersist"');
    });

    // Observe STT status for diagnostics only; do not stop recording
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

      // Apply same merge logic for remote users to avoid duplicate rows
      final lastText = _lastTranscriptTextByUser[userIdMsg];
      final lastUpdated = _lastTranscriptUpdatedAtByUser[userIdMsg] ?? 0;
      final activeId = _activeTranscriptionIdByUser[userIdMsg];
      final withinWindow = ts - lastUpdated <= _mergeWindowMs;

      // Determine if this is a significant update (substantially more content)
      bool isSignificantUpdate = lastText != null &&
          textMsg.split(' ').length > lastText.split(' ').length + 2;

      bool shouldInsertNew = activeId == null || !withinWindow;
      bool shouldUpdate = false;

      if (!shouldInsertNew && lastText != null) {
        if (textMsg == lastText) {
          return; // no change
        }
        final grows = textMsg.length >= lastText.length;
        if (!grows && !isSignificantUpdate) {
          return; // ignore shorter partials unless significant
        }

        // Force update if it's a significant change
        if (isSignificantUpdate) {
          shouldUpdate = true;
        } else {
          final sharesPrefix =
              grows && textMsg.toLowerCase().startsWith(lastText.toLowerCase());
          if (sharesPrefix) {
            shouldUpdate = true;
          } else {
            shouldInsertNew = true;
          }
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

      // Don't play back our own audio
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

      // Generate room code
      final code = _roomCodeService.generateRoomCode();
      logger.i('Generated room code: $code');
      _roomCode = code;

      // Only store room code metadata if not using Firebase as server
      if (!AppConfig.useFirebaseAsServer) {
        await _roomCodeService.setRoomCode(code, serverIP);
      }
      try {
        await _localDbService.setRoom(code);
      } catch (_) {}

      // Reset all roles when starting a new server
      resetAllRoles();

      // Add self as a user
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
      _users = [selfUser];
      if (_networkService.isServer) {
        _networkService.addSelfUser(selfUser);

        // Setup Firebase room for server if using Firebase
        if (AppConfig.useFirebaseAsServer) {
          // Pass the server's userId so FirebaseRoomService can set presence
          await _networkService.setupFirebaseRoom(code, userId: _userId);
          // Send initial join message for the server user
          _networkService.sendMessage({
            'type': 'join',
            'user': selfUser.toJson(),
            'ts': DateTime.now().millisecondsSinceEpoch,
          });
        }
      }
      notifyListeners();
      return code; // Return the code, not the IP
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

    // When using Firebase as server, always pass the room code directly
    // No need to validate room existence since Firebase will handle it
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
    if (_talkStartedAtMs > 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _talkStartedAtMs < 1000) {
        logger.w('Preventing rapid toggle of talk state');
        return;
      }
    }

    try {
      // Set talking state after verifying we can start
      _talkStartedAtMs = DateTime.now().millisecondsSinceEpoch;
      _isTalking = true;
      notifyListeners();

      // Make sure any previous audio session is cleaned up
      await _audioService.stopListening();
      if (_audioService.isRecording) {
        await _audioService.stopRecording();
      }

      // Start STT first with timeout
      bool sttStarted = false;
      try {
        sttStarted = await _audioService
            .startListening()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        logger.e('STT start timeout or error: $e');
        sttStarted = false;
      }

      if (!sttStarted) {
        logger.e('Failed to start STT, stopping talking');
        _lastError = 'Failed to start speech recognition';
        await _cleanupTalkingState();
        return;
      }

      // Update speaking status immediately after STT starts
      try {
        _networkService.updateSpeakingStatus(_userId, true);
      } catch (e) {
        logger.e('Failed to update speaking status: $e');
        // Continue anyway as this is not critical
      }

      if (enableAudioRecordingDuringTalk) {
        // Give STT time to initialize and acquire the mic first
        await Future.delayed(const Duration(milliseconds: 1200));
        String? recordingPath;

        // Retry starting recorder up to 3 times with small backoff
        for (int attempt = 0; attempt < 3 && recordingPath == null; attempt++) {
          try {
            recordingPath = await _audioService
                .startRecording()
                .timeout(const Duration(seconds: 2));
          } catch (e) {
            final backoffMs = 200 * (attempt + 1);
            logger.w(
                'Recorder start failed (attempt ${attempt + 1}): $e. Retrying in ${backoffMs}ms');
            await Future.delayed(Duration(milliseconds: backoffMs));
          }
        }

        if (recordingPath == null) {
          logger.e('Failed to start recorder after retries');
          _lastError = 'Audio recording failed to start';
          // Don't stop talking - continue with just STT
          notifyListeners();
        }
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

      // Handle recording cleanup
      Uint8List? audioData;
      if (enableAudioRecordingDuringTalk && _audioService.isRecording) {
        try {
          logger.i('Stopping recording...');
          audioData = await _audioService
              .stopRecording()
              .timeout(const Duration(seconds: 3));
        } catch (e) {
          logger.e('Error stopping recording: $e');
          _lastError = 'Failed to process audio recording';
          notifyListeners();
        }

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
      }

      // Stop STT and process final transcription
      String transcript = '';
      try {
        await _audioService.stopListening();
        transcript = _audioService.lastTranscription.trim();
        if (transcript.isEmpty) {
          transcript = _audioService.lastNonEmptyTranscription.trim();
        }
      } catch (e) {
        logger.e('Error stopping STT: $e');
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
      // Update speaking status first to ensure UI reflects correct state
      _networkService.updateSpeakingStatus(_userId, false);

      // Stop recording if active
      if (_audioService.isRecording) {
        try {
          await _audioService
              .stopRecording()
              .timeout(const Duration(seconds: 2));
        } catch (e) {
          logger.e('Error stopping recording: $e');
        }
      }

      // Stop STT if active
      try {
        await _audioService.stopListening().timeout(const Duration(seconds: 2));
      } catch (e) {
        logger.e('Error stopping STT: $e');
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
      // Ensure talking state is false
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
