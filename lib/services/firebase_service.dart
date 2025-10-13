import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../models/transcription.dart';

class FirebaseDbService {
  late final StreamController<List<Transcription>> _transcriptionsController;
  bool _isInitialized = false;
  DatabaseReference? _roomRef;
  StreamSubscription<DatabaseEvent>? _addedSub;
  StreamSubscription<DatabaseEvent>? _changedSub;
  StreamSubscription<DatabaseEvent>? _removedSub;

  // Cache to maintain the complete list of transcriptions
  final Map<String, Transcription> _transcriptionsCache = {};

  // Track the last transcription key for updating
  String? _lastTranscriptionKey;

  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    try {
      _transcriptionsController =
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
      throw StateError('Room is not set for LocalDbService');
    }
    final t = Transcription(
      userId: userId,
      userName: userName,
      text: text,
      timestamp: timestamp,
    );
    final ref = _roomRef!.child('transcriptions').push();
    final idStr = ref.key!;
    t.id = idStr.hashCode;

    // Store the key for future updates
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
        _transcriptionsCache.containsKey(_lastTranscriptionKey)) {
      final lastTranscription = _transcriptionsCache[_lastTranscriptionKey!]!;

      // Update if same user and within 5 seconds
      final timeDiff = timestamp - lastTranscription.timestamp;
      if (lastTranscription.userId == userId && timeDiff < 5000) {
        // Update existing transcription
        _roomRef!.child('transcriptions/$_lastTranscriptionKey').update({
          'text': text,
          'timestamp': timestamp,
        });

        // Update local cache immediately for responsiveness
        _transcriptionsCache[_lastTranscriptionKey!] = Transcription(
          id: lastTranscription.id,
          userId: userId,
          userName: userName,
          text: text,
          timestamp: timestamp,
        );
        _emitTranscriptions();

        return _transcriptionsCache[_lastTranscriptionKey!]!;
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
    final ref = _roomRef!.child('transcriptions').push();
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
    final list = _transcriptionsCache.values.toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Stream<List<Transcription>> watchAllNewestFirst() {
    if (!_isInitialized) {
      print('LocalDbService not initialized yet, returning empty stream');
      return Stream.value([]);
    }
    return _transcriptionsController.stream;
  }

  void _emitTranscriptions() {
    if (!_transcriptionsController.isClosed) {
      final list = _transcriptionsCache.values.toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _transcriptionsController.add(list);
    }
  }

  void clearAllTranscriptions() {
    if (_roomRef != null) {
      _roomRef!.child('transcriptions').remove();
    }
    _transcriptionsCache.clear();
    _lastTranscriptionKey = null;
    _emitTranscriptions();
  }

  bool updateTranscriptionText({
    required String transcriptionKey, // Change to string key
    required String newText,
  }) {
    print(
        '🔥 updateTranscriptionText called - key: $transcriptionKey, text: "$newText"');
    print('🔥 Cache keys: ${_transcriptionsCache.keys}');
    if (_roomRef != null &&
        _transcriptionsCache.containsKey(transcriptionKey)) {
      print('🔥 Key found in cache, updating...');

      // Update in Firebase
      _roomRef!.child('transcriptions/$transcriptionKey').update({
        'text': newText,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Update local cache
      final t = _transcriptionsCache[transcriptionKey]!;
      _transcriptionsCache[transcriptionKey] = Transcription(
        id: t.id,
        userId: t.userId,
        userName: t.userName,
        text: newText,
        timestamp: t.timestamp,
      );

      _emitTranscriptions();
      return true;
    } else {
      print('🔥 Key not found in cache or roomRef is null');
    }
    return false;
  }

  // Add method to get transcription key by ID if needed
  String? getTranscriptionKeyById(int id) {
    for (final entry in _transcriptionsCache.entries) {
      if (entry.value.id == id) {
        return entry.key;
      }
    }
    return null;
  }

  void dispose() {
    try {
      _transcriptionsController.close();
    } catch (e) {
      print('Error closing transcriptions controller: $e');
    }
    try {
      _addedSub?.cancel();
      _changedSub?.cancel();
      _removedSub?.cancel();
    } catch (e) {
      print('Error canceling subscriptions: $e');
    }
    _transcriptionsCache.clear();
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
    _transcriptionsCache.clear();
    _lastTranscriptionKey = null;

    final db = FirebaseDatabase.instance.ref();
    _roomRef = db.child('rooms/$roomCode');

    // Initial load
    final snap = await _roomRef!.child('transcriptions').get();
    if (snap.exists && snap.value is Map) {
      final data = Map<String, dynamic>.from((snap.value as Map));
      for (final entry in data.entries) {
        final m = Map<String, dynamic>.from(entry.value);
        _transcriptionsCache[entry.key] = Transcription(
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
        .child('transcriptions')
        .onChildAdded
        .listen((DatabaseEvent event) {
      final v = event.snapshot.value;
      if (v is Map && event.snapshot.key != null) {
        final m = Map<String, dynamic>.from(v);
        final key = event.snapshot.key!;

        // Only add if not already in cache (to avoid duplicates from initial load)
        if (!_transcriptionsCache.containsKey(key)) {
          _transcriptionsCache[key] = Transcription(
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
        .child('transcriptions')
        .onChildChanged
        .listen((DatabaseEvent event) {
      final v = event.snapshot.value;
      if (v is Map && event.snapshot.key != null) {
        final m = Map<String, dynamic>.from(v);
        final key = event.snapshot.key!;
        _transcriptionsCache[key] = Transcription(
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
        .child('transcriptions')
        .onChildRemoved
        .listen((DatabaseEvent event) {
      if (event.snapshot.key != null) {
        final key = event.snapshot.key!;
        if (_lastTranscriptionKey == key) {
          _lastTranscriptionKey = null;
        }
        _transcriptionsCache.remove(key);
        _emitTranscriptions();
      }
    });
  }
}
