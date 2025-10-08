import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../models/transcription.dart';

class LocalDbService {
  late final StreamController<List<Transcription>> _transcriptionsController;
  bool _isInitialized = false;
  DatabaseReference? _roomRef;
  StreamSubscription<DatabaseEvent>? _addedSub;
  StreamSubscription<DatabaseEvent>? _changedSub;
  StreamSubscription<DatabaseEvent>? _removedSub;

  // Cache to maintain the complete list of transcriptions
  final Map<String, Transcription> _transcriptionsCache = {};

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
    _emitTranscriptions();
  }

  bool updateTranscriptionText({
    required int id,
    required String newText,
  }) {
    // Find the transcription in cache and update
    final key = _transcriptionsCache.keys.firstWhere(
      (k) => k.hashCode == id,
      orElse: () => '',
    );

    if (key.isNotEmpty && _roomRef != null) {
      _roomRef!.child('transcriptions/$key').update({'text': newText});

      // Update cache
      final t = _transcriptionsCache[key];
      if (t != null) {
        _transcriptionsCache[key] = Transcription(
          id: t.id,
          userId: t.userId,
          userName: t.userName,
          text: newText,
          timestamp: t.timestamp,
        );
        _emitTranscriptions();
      }
      return true;
    }
    return false;
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
        _transcriptionsCache.remove(event.snapshot.key!);
        _emitTranscriptions();
      }
    });
  }
}
