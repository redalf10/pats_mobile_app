import 'package:firebase_database/firebase_database.dart';
import 'dart:math';

class RoomCodeService {
  final _db = FirebaseDatabase.instance.ref();

  // Generate a random 6-digit code
  String generateRoomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (int i = 0; i < 6; i++) {
      buffer.write(chars[random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  // Save code -> ip mapping, plus mark firebase mode
  Future<void> setRoomCode(String code, String ip) async {
    await _db.child('room_codes/$code').set({
      'ip': ip,
      'use_firebase': true,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // Get IP from code
  Future<String?> getIpForCode(String code) async {
    final snapshot = await _db.child('room_codes/$code/ip').get();
    if (snapshot.exists) {
      return snapshot.value as String;
    }
    return null;
  }

  Future<bool> isFirebaseRoom(String code) async {
    final snapshot = await _db.child('room_codes/$code/use_firebase').get();
    return snapshot.exists && snapshot.value == true;
  }

  // Optionally: Clean up old codes (not required for MVP)
  Future<void> deleteRoomCode(String code) async {
    await _db.child('room_codes/$code').remove();
  }
}
