import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
// firebase_database.dart provides the Transaction/MutableData types we need.
import '../models/user.dart';
import 'package:logger/logger.dart';

class FirebaseRoomService {
  final Logger logger = Logger();
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  late final DatabaseReference _roomRef;
  late final DatabaseReference _usersRef;
  StreamSubscription? _usersSub;
  StreamSubscription? _messagesSub;
  final String roomCode;
  final void Function(Map<String, dynamic>) onMessage;
  final void Function(List<User>) onUsersChanged;
  Timer? _presenceTimer;
  final String userId;

  FirebaseRoomService({
    required this.roomCode,
    required this.onMessage,
    required this.onUsersChanged,
    required this.userId,
  }) {
    _roomRef = _db.child('rooms/$roomCode');
    _usersRef = _roomRef.child('users');
  }

  Future<void> initialize() async {
    try {
      // Set up users listener
      _usersSub = _usersRef.onValue.listen((event) {
        final users = <User>[];
        if (event.snapshot.value != null) {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          data.forEach((key, value) {
            if (value is Map) {
              final userData = Map<String, dynamic>.from(value);
              users.add(User.fromJson(userData));
            }
          });
        }
        onUsersChanged(users);
      });

      // FIXED: Set up listeners for all message types
      // Listen to messages table (for join, leave, speaking_status, etc.)
      _messagesSub = _roomRef.child('messages').onChildAdded.listen((event) {
        if (event.snapshot.value != null) {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          onMessage(data);
        }
      });

      // Listen to audio table
      _roomRef.child('audio').onChildAdded.listen((event) {
        if (event.snapshot.value != null) {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          onMessage(data);
        }
      });

      // Listen to transcripts table
      _roomRef.child('transcripts').onChildAdded.listen((event) {
        if (event.snapshot.value != null) {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          onMessage(data);
        }
      });

      // Set up presence system
      await _setupPresence();
    } catch (e) {
      logger.e('Error initializing Firebase room service: $e');
      rethrow;
    }
  }

  Future<void> _setupPresence() async {
    // Set up presence ping
    _presenceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _updatePresence();
    });

    // Set initial presence
    await _updatePresence();

    // Set cleanup on disconnect
    await _usersRef.child(userId).onDisconnect().remove();
  }

  Future<void> _updatePresence() async {
    try {
      await _usersRef.child(userId).update({
        'lastSeen': ServerValue.timestamp,
      });
    } catch (e) {
      logger.e('Error updating presence: $e');
    }
  }

  Future<void> addUser(User user) async {
    try {
      logger.i('🔥 FirebaseRoomService: Adding user ${user.name} (${user.id})');
      final userData = {
        ...user.toJson(),
        'lastSeen': ServerValue.timestamp,
      };
      logger.d('🔥 User data: $userData');
      await _usersRef.child(user.id).set(userData);
      logger.i('✅ User added successfully to Firebase');
    } catch (e) {
      logger.e('❌ Error adding user: $e');
      rethrow;
    }
  }

  Future<void> updateUserSpeakingStatus(String userId, bool isSpeaking) async {
    try {
      await _usersRef.child(userId).update({
        'isSpeaking': isSpeaking,
        'lastSeen': ServerValue.timestamp,
      });
    } catch (e) {
      logger.e('Error updating speaking status: $e');
    }
  }

  Future<void> sendMessage(Map<String, dynamic> message) async {
    try {
      final messageType = message['type'] as String?;

      // FIXED: Route messages to appropriate tables based on type
      if (messageType == 'audio') {
        // Audio messages go to the 'audio' table
        await _roomRef.child('audio').push().set({
          ...message,
          'timestamp': ServerValue.timestamp,
        });
        logger.i(
            '🔥 Audio message sent to audio table: ${message['userId']} (${message['data']?.length ?? 0} chars)');
      } else if (messageType == 'transcript') {
        // Transcript messages go to the 'transcripts' table (not messages)
        await _roomRef.child('transcripts').push().set({
          ...message,
          'timestamp': ServerValue.timestamp,
        });
        logger.i(
            '🔥 Transcript message sent to transcripts table: ${message['userId']} - "${message['text']}"');
      } else {
        // Other messages (join, leave, speaking_status, etc.) go to messages table
        await _roomRef.child('messages').push().set({
          ...message,
          'timestamp': ServerValue.timestamp,
        });
        logger.d('Other message sent to messages table');
      }
    } catch (e) {
      logger.e('Error sending message: $e');
      rethrow;
    }
  }

  Future<void> removeUser() async {
    try {
      await _usersRef.child(userId).remove();
    } catch (e) {
      logger.e('Error removing user: $e');
    }
  }

  void dispose() {
    _usersSub?.cancel();
    _messagesSub?.cancel();
    _presenceTimer?.cancel();
    // Note: The audio and transcript listeners are not stored in variables
    // so they will be automatically cancelled when the service is disposed
  }
}
