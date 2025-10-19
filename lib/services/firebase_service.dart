import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../models/transcription.dart';

class FirebaseDbService {
  late final StreamController<List<Transcription>> _transcriptsController;
  bool _isInitialized = false;
  DatabaseReference? _roomRef;
  StreamSubscription<DatabaseEvent>? _addedSub;
  StreamSubscription<DatabaseEvent>? _changedSub;
  StreamSubscription<DatabaseEvent>? _removedSub;

  // Cache to maintain the complete list of transcripts
  final Map<String, Transcription> _transcriptsCache = {};

  // Track the last transcription key for updating
  String? _lastTranscriptionKey;

  bool get isInitialized => _isInitialized;
  bool get isRoomSet => _roomRef != null;
  String? get currentRoomPath => _roomRef?.path;

  Future<void> init() async {
    try {
      _transcriptsController =
          StreamController<List<Transcription>>.broadcast();
      _isInitialized = true;
      print('LocalDbService (firebase) initialized successfully');
    } catch (e) {
      print('Error initializing LocalDbService (firebase): $e');
      rethrow;
    }
  }

  Transcription addTranscription({
    required String userId,
    required String userName,
    required String text,
    required int timestamp,
  }) {
    if (_roomRef == null) {
      print('🔥 ERROR: Room is not set for LocalDbService');
      throw StateError('Room is not set for LocalDbService');
    }

    // Check for recent duplicate before adding
    final recentDuplicate = _transcriptsCache.values
        .where((t) =>
            t.userId == userId &&
            t.text == text &&
            (timestamp - t.timestamp).abs() < 3000) // Within 3 seconds
        .isNotEmpty;

    if (recentDuplicate) {
      print('🔥 FirebaseDbService: Skipping recent duplicate: "$text"');
      // Return the existing transcription instead of creating a new one
      final existing = _transcriptsCache.values
          .where((t) => t.userId == userId && t.text == text)
          .first;
      return existing;
    }

    print('🔥 FirebaseDbService: Adding transcription from $userName: "$text"');
    print('🔥 FirebaseDbService: Room ref: ${_roomRef!.path}');
    print(
        '🔥 FirebaseDbService: Cache size before: ${_transcriptsCache.length}');

    final t = Transcription(
      userId: userId,
      userName: userName,
      text: text,
      timestamp: timestamp,
    );
    final ref = _roomRef!.child('transcripts').push();
    final idStr = ref.key!;
    t.id = idStr.hashCode;

    print('🔥 FirebaseDbService: Generated key: $idStr');

    // Store the key for future updates
    _lastTranscriptionKey = idStr;

    ref.set({
      'id': idStr,
      'userId': userId,
      'userName': userName,
      'text': text,
      'timestamp': timestamp,
    }).then((_) {
      print('🔥 FirebaseDbService: Successfully saved to Firebase');
    }).catchError((error) {
      print('🔥 FirebaseDbService: Error saving to Firebase: $error');
    });

    // Store in cache immediately for local access
    _transcriptsCache[idStr] = t;
    print(
        '🔥 FirebaseDbService: Cache size after: ${_transcriptsCache.length}');
    _emitTranscriptions();

    return t;
  }

  // Add or update transcription - appends text if it's the same user speaking
  Transcription addOrUpdateTranscription({
    required String userId,
    required String userName,
    required String text,
    required int timestamp,
    bool isFinal = false,
  }) {
    if (_roomRef == null) {
      throw StateError('Room is not set for LocalDbService');
    }

    // Check if we should update the last transcription
    if (_lastTranscriptionKey != null &&
        _transcriptsCache.containsKey(_lastTranscriptionKey)) {
      final lastTranscription = _transcriptsCache[_lastTranscriptionKey!]!;

      // Update if same user and within 5 seconds
      final timeDiff = timestamp - lastTranscription.timestamp;
      if (lastTranscription.userId == userId && timeDiff < 5000) {
        // Update existing transcription
        _roomRef!.child('transcripts/$_lastTranscriptionKey').update({
          'text': text,
          'timestamp': timestamp,
        });

        // Update local cache immediately for responsiveness
        _transcriptsCache[_lastTranscriptionKey!] = Transcription(
          id: lastTranscription.id,
          userId: userId,
          userName: userName,
          text: text,
          timestamp: timestamp,
        );
        _emitTranscriptions();

        return _transcriptsCache[_lastTranscriptionKey!]!;
      }
    }

    // Create new transcription if final or different user
    if (isFinal) {
      return addTranscription(
        userId: userId,
        userName: userName,
        text: text,
        timestamp: timestamp,
      );
    }

    // For non-final results, still create but mark for potential update
    final t = Transcription(
      userId: userId,
      userName: userName,
      text: text,
      timestamp: timestamp,
    );
    final ref = _roomRef!.child('transcripts').push();
    final idStr = ref.key!;
    t.id = idStr.hashCode;

    _lastTranscriptionKey = idStr;

    ref.set({
      'id': idStr,
      'userId': userId,
      'userName': userName,
      'text': text,
      'timestamp': timestamp,
    });
    return t;
  }

  List<Transcription> getAllNewestFirst() {
    final list = _transcriptsCache.values.toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Stream<List<Transcription>> watchAllNewestFirst() {
    if (!_isInitialized) {
      print('LocalDbService not initialized yet, returning empty stream');
      return Stream.value([]);
    }

    // Create a stream that emits the current state immediately, then continues with updates
    late StreamController<List<Transcription>> controller;
    controller = StreamController<List<Transcription>>(
      onListen: () {
        // Emit current state immediately when first listener subscribes
        controller.add(getAllNewestFirst());

        // Then listen to updates and forward them
        _transcriptsController.stream.listen(
          (transcripts) {
            if (!controller.isClosed) {
              controller.add(transcripts);
            }
          },
          onError: (error) {
            if (!controller.isClosed) {
              controller.addError(error);
            }
          },
          onDone: () {
            if (!controller.isClosed) {
              controller.close();
            }
          },
        );
      },
      onCancel: () {
        controller.close();
      },
    );

    return controller.stream;
  }

  void _emitTranscriptions() {
    if (!_transcriptsController.isClosed) {
      final list = _transcriptsCache.values.toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      print('🔥 FirebaseDbService: Emitting ${list.length} transcripts');
      for (var t in list) {
        print('   - ${t.userName}: "${t.text}" (${t.timestamp})');
      }
      _transcriptsController.add(list);
    } else {
      print('🔥 FirebaseDbService: Controller is closed, cannot emit');
    }
  }

  void clearAllTranscriptions() {
    if (_roomRef != null) {
      _roomRef!.child('transcripts').remove();
    }
    _transcriptsCache.clear();
    _lastTranscriptionKey = null;
    _emitTranscriptions();
  }

  /// Remove duplicate transcripts (same text from same user within 10 seconds)
  void removeDuplicateTranscriptions() {
    final toRemove = <String>[];

    // Group transcripts by user and text
    final Map<String, List<MapEntry<String, Transcription>>> grouped = {};

    for (final entry in _transcriptsCache.entries) {
      final key = '${entry.value.userId}_${entry.value.text}';
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    // For each group, keep only the latest transcription
    for (final group in grouped.values) {
      if (group.length > 1) {
        // Sort by timestamp, newest first
        group.sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));

        print(
            '🔥 FirebaseDbService: Found ${group.length} duplicates for "${group.first.value.text}"');

        // Remove all but the newest (keep the first one after sorting)
        for (int i = 1; i < group.length; i++) {
          toRemove.add(group[i].key);
          print(
              '🔥 FirebaseDbService: Marking for removal: ${group[i].key} (${group[i].value.timestamp})');
        }
      }
    }

    // Remove duplicates from cache and Firebase
    for (final key in toRemove) {
      print('🔥 FirebaseDbService: Removing duplicate key: $key');
      _transcriptsCache.remove(key);
      if (_roomRef != null) {
        _roomRef!.child('transcripts/$key').remove();
      }
    }

    if (toRemove.isNotEmpty) {
      print(
          '🔥 FirebaseDbService: Successfully removed ${toRemove.length} duplicate transcripts');
      _emitTranscriptions();
    } else {
      print('🔥 FirebaseDbService: No duplicates found to remove');
    }
  }

  bool updateTranscriptionText({
    required String transcriptionKey, // Change to string key
    required String newText,
  }) {
    print(
        '🔥 updateTranscriptionText called - key: $transcriptionKey, text: "$newText"');
    print('🔥 Cache keys: ${_transcriptsCache.keys}');
    if (_roomRef != null && _transcriptsCache.containsKey(transcriptionKey)) {
      print('🔥 Key found in cache, updating...');

      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Update in Firebase
      _roomRef!.child('transcripts/$transcriptionKey').update({
        'text': newText,
        'timestamp': timestamp,
      });

      // Update local cache with new timestamp
      final t = _transcriptsCache[transcriptionKey]!;
      _transcriptsCache[transcriptionKey] = Transcription(
        id: t.id,
        userId: t.userId,
        userName: t.userName,
        text: newText,
        timestamp: timestamp, // Update timestamp to reflect the change
      );

      // Emit immediately for UI responsiveness
      _emitTranscriptions();
      print('🔥 Successfully updated transcription and emitted to UI');
      return true;
    } else {
      print('🔥 Key not found in cache or roomRef is null');
    }
    return false;
  }

  // Add method to get transcription key by ID if needed
  String? getTranscriptionKeyById(int id) {
    for (final entry in _transcriptsCache.entries) {
      if (entry.value.id == id) {
        return entry.key;
      }
    }
    return null;
  }

  // Get the last transcription key for a user
  String? getLastTranscriptionKey() {
    return _lastTranscriptionKey;
  }

  void dispose() {
    try {
      _transcriptsController.close();
    } catch (e) {
      print('Error closing transcripts controller: $e');
    }
    try {
      _addedSub?.cancel();
      _changedSub?.cancel();
      _removedSub?.cancel();
    } catch (e) {
      print('Error canceling subscriptions: $e');
    }
    _transcriptsCache.clear();
    _lastTranscriptionKey = null;
  }

  Future<void> setRoom(String roomCode) async {
    try {
      await _addedSub?.cancel();
      await _changedSub?.cancel();
      await _removedSub?.cancel();
    } catch (e) {
      print('Error canceling existing subscriptions: $e');
    }

    // Clear cache for new room
    _transcriptsCache.clear();
    _lastTranscriptionKey = null;

    print('🔥 FirebaseDbService: Setting room to: $roomCode');
    final db = FirebaseDatabase.instance.ref();
    _roomRef = db.child('rooms/$roomCode');
    print('🔥 FirebaseDbService: Room reference set to: ${_roomRef!.path}');

    // Initial load
    final snap = await _roomRef!.child('transcripts').get();
    if (snap.exists && snap.value is Map) {
      final data = Map<String, dynamic>.from((snap.value as Map));
      for (final entry in data.entries) {
        final m = Map<String, dynamic>.from(entry.value);
        _transcriptsCache[entry.key] = Transcription(
          id: entry.key.hashCode,
          userId: (m['userId'] ?? '') as String,
          userName: (m['userName'] ?? '') as String,
          text: (m['text'] ?? '') as String,
          timestamp: (m['timestamp'] ?? 0) as int,
        );
      }
      // Set the last key to the most recent transcription
      if (data.isNotEmpty) {
        final sorted = data.entries.toList()
          ..sort((a, b) {
            final aTime = (a.value as Map)['timestamp'] ?? 0;
            final bTime = (b.value as Map)['timestamp'] ?? 0;
            return (bTime as int).compareTo(aTime as int);
          });
        _lastTranscriptionKey = sorted.first.key;
      }
    }
    _emitTranscriptions();

    // Subscribe to additions
    _addedSub = _roomRef!
        .child('transcripts')
        .onChildAdded
        .listen((DatabaseEvent event) {
      final v = event.snapshot.value;
      if (v is Map && event.snapshot.key != null) {
        final m = Map<String, dynamic>.from(v);
        final key = event.snapshot.key!;

        // Only add if not already in cache (to avoid duplicates from initial load)
        if (!_transcriptsCache.containsKey(key)) {
          _transcriptsCache[key] = Transcription(
            id: key.hashCode,
            userId: (m['userId'] ?? '') as String,
            userName: (m['userName'] ?? '') as String,
            text: (m['text'] ?? '') as String,
            timestamp: (m['timestamp'] ?? 0) as int,
          );
          _lastTranscriptionKey = key;
          _emitTranscriptions();
        }
      }
    });

    // Subscribe to changes
    _changedSub = _roomRef!
        .child('transcripts')
        .onChildChanged
        .listen((DatabaseEvent event) {
      final v = event.snapshot.value;
      if (v is Map && event.snapshot.key != null) {
        final m = Map<String, dynamic>.from(v);
        final key = event.snapshot.key!;
        _transcriptsCache[key] = Transcription(
          id: key.hashCode,
          userId: (m['userId'] ?? '') as String,
          userName: (m['userName'] ?? '') as String,
          text: (m['text'] ?? '') as String,
          timestamp: (m['timestamp'] ?? 0) as int,
        );
        _emitTranscriptions();
      }
    });

    // Subscribe to removals
    _removedSub = _roomRef!
        .child('transcripts')
        .onChildRemoved
        .listen((DatabaseEvent event) {
      if (event.snapshot.key != null) {
        final key = event.snapshot.key!;
        if (_lastTranscriptionKey == key) {
          _lastTranscriptionKey = null;
        }
        _transcriptsCache.remove(key);
        _emitTranscriptions();
      }
    });
  }
}
