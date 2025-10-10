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

      // Set up messages listener
      _messagesSub = _roomRef.child('messages').onChildAdded.listen((event) {
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
      await _usersRef.child(user.id).set({
        ...user.toJson(),
        'lastSeen': ServerValue.timestamp,
      });
    } catch (e) {
      logger.e('Error adding user: $e');
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

  Future<void> updateUserRole(String userId, String role) async {
    try {
      await _usersRef.child(userId).update({
        'role': role,
        'lastSeen': ServerValue.timestamp,
      });
    } catch (e) {
      logger.e('Error updating user role: $e');
    }
  }

  /// Atomically claim a role using a Firebase transaction. Returns true if this
  /// user's role was set to [role], false if another user already holds it.
  Future<bool> claimRole(String userId, String role) async {
    try {
      final result = await _usersRef.runTransaction((currentData) {
        final dyn = currentData as dynamic;
        if (dyn == null) return Transaction.abort();
        final Map<dynamic, dynamic> usersMap =
            (dyn.value as Map?)?.cast<dynamic, dynamic>() ?? {};

        // Check if someone else already holds the role
        String? existingHolder;
        usersMap.forEach((key, value) {
          if (value is Map && value['role'] == role) {
            existingHolder = key as String;
          }
        });

        if (existingHolder == null || existingHolder == userId) {
          // Safe to assign role to this user (either unclaimed or already ours)
          final Map userEntry = (usersMap[userId] is Map)
              ? Map<String, dynamic>.from(usersMap[userId])
              : <String, dynamic>{};
          userEntry['role'] = role;
          userEntry['lastSeen'] = ServerValue.timestamp;
          usersMap[userId] = userEntry;
          dyn.value = usersMap;
          return Transaction.success(dyn);
        }

        // Role taken by someone else; abort
        return Transaction.abort();
      });

      return result.committed;
    } catch (e) {
      logger.e('Error during claimRole transaction: $e');
      return false;
    }
  }

  Future<void> sendMessage(Map<String, dynamic> message) async {
    try {
      await _roomRef.child('messages').push().set({
        ...message,
        'timestamp': ServerValue.timestamp,
      });
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

  /// Resets all users in the room to have the inspector role
  Future<void> resetAllRoles() async {
    try {
      final snapshot = await _usersRef.get();
      if (snapshot.exists) {
        final Map<dynamic, dynamic> usersMap = snapshot.value as Map;
        final batch = <Future<void>>[];

        usersMap.forEach((key, value) {
          if (value is Map) {
            batch.add(_usersRef.child(key.toString()).update({
              'role': 'inspector',
              'lastSeen': ServerValue.timestamp,
            }));
          }
        });

        await Future.wait(batch);
      }
    } catch (e) {
      logger.e('Error resetting user roles: $e');
    }
  }

  void dispose() {
    _usersSub?.cancel();
    _messagesSub?.cancel();
    _presenceTimer?.cancel();
  }
}
