import 'dart:async';

// Web-compatible stub for AuthService
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  // Stub implementations
  Stream<dynamic> authStateChanges() => Stream.value(null);
  dynamic get currentUser => null;

  Future<dynamic> signInWithGoogle() async {
    throw UnsupportedError('Google Sign-In not available in web version');
  }

  Future<void> signOut() async {
    // No-op for web
  }
}
