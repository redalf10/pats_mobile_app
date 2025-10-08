class AppConfig {
  static const int serverPort = 8888;
  static const int audioSampleRate = 16000;
  static const int audioBufferSize = 4096;
  static const Duration speakingTimeout = Duration(milliseconds: 300);
  static const Duration heartbeatInterval = Duration(seconds: 5);

  // If set, the app will connect to this central server instead of device-hosted server
  // Example: 'example.com' or '1.2.3.4'
  static const String? centralServerHost =
      null; // TODO: set to your public host
  static const bool useSecureWebSocket =
      false; // set true if using wss with TLS

  // Use Firebase Realtime Database as the transport/server
  static const bool useFirebaseAsServer = true;
  static const String firebaseRoomsRoot = 'rooms';

  // UI Configuration
  static const double waveformHeight = 100.0;
  static const double buttonSize = 80.0;
  static const Duration waveformUpdateInterval = Duration(milliseconds: 50);
}
