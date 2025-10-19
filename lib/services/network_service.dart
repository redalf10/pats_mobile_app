import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:logger/logger.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../models/user.dart';
import '../config.dart';
import 'firebase_room_service.dart';

class NetworkService {
  HttpServer? _server;
  final List<WebSocket> _clients = [];
  final Map<String, User> _connectedUsers = {};
  bool _isServer = false;
  bool _isConnected = false;
  WebSocket? _clientSocket;
  Timer? _heartbeatTimer;
  FirebaseRoomService? _roomService;

  Logger logger = Logger();

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _userUpdateController = StreamController<List<User>>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<List<User>> get userUpdateStream => _userUpdateController.stream;
  bool get isConnected => _isConnected;
  bool get isServer => _isServer;
  List<User> get connectedUsers => _connectedUsers.values.toList();

  // Start as server (device-hosted). If using Firebase, set up room channel.
  Future<String?> startServer() async {
    try {
      if (AppConfig.useFirebaseAsServer) {
        _isServer = true;
        _isConnected = true;
        // Note: Firebase room setup will be done when room code is available
        return 'FIREBASE';
      }
      if (AppConfig.centralServerHost != null &&
          AppConfig.centralServerHost!.isNotEmpty) {
        // When using a central server, we don't bind locally. Return the host for display only.
        _isServer = true; // Treat as server for UI purposes
        _isConnected = true;
        return AppConfig.centralServerHost;
      }
      _server =
          await HttpServer.bind(InternetAddress.anyIPv4, AppConfig.serverPort);
      _isServer = true;
      _isConnected = true;

      _server!.transform(WebSocketTransformer()).listen((WebSocket socket) {
        _clients.add(socket);

        socket.listen(
          (message) => _handleMessage(jsonDecode(message), socket),
          onDone: () => _handleClientDisconnected(socket),
          onError: (error) => _handleClientDisconnected(socket),
        );
      });

      _startHeartbeat();

      // Try to determine a usable IPv4 address for display
      String? ipForDisplay;
      try {
        ipForDisplay = await NetworkInfo().getWifiIP();
      } catch (_) {
        ipForDisplay = null;
      }
      if (ipForDisplay == null) {
        try {
          final interfaces = await NetworkInterface.list(
            includeLoopback: false,
            type: InternetAddressType.IPv4,
          );
          for (final iface in interfaces) {
            for (final addr in iface.addresses) {
              if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
                ipForDisplay = addr.address;
                break;
              }
            }
            if (ipForDisplay != null) break;
          }
        } catch (_) {
          // ignore and fall through
        }
      }

      // Always return a non-null string so UI can proceed
      return ipForDisplay ?? '0.0.0.0';
    } catch (e) {
      logger.e('Failed to start server: $e');
      return null;
    }
  }

  // Connect as client
  Future<bool> connectToServer(String serverIP, String userId, String userName,
      {String? photoUrl}) async {
    try {
      if (AppConfig.useFirebaseAsServer) {
        // Join Firebase room by code (serverIP holds code's IP in current design; here treat as code)
        final success = await _connectFirebaseRoom(serverIP, userId, userName,
            photoUrl: photoUrl);
        if (success) {
          _isConnected = true;
          return true;
        } else {
          return false;
        }
      }
      final String host = (AppConfig.centralServerHost != null &&
              AppConfig.centralServerHost!.isNotEmpty)
          ? AppConfig.centralServerHost!
          : serverIP;
      const bool secure = AppConfig.useSecureWebSocket;
      final uri =
          Uri.parse('${secure ? 'wss' : 'ws'}://$host:${AppConfig.serverPort}');
      _clientSocket = await WebSocket.connect(uri.toString());
      _isConnected = true;

      _clientSocket!.listen(
        (message) => _handleMessage(jsonDecode(message), null),
        onDone: () => _handleServerDisconnected(),
        onError: (error) => _handleServerDisconnected(),
      );

      // Send join message
      sendMessage({
        'type': 'join',
        'user': User(id: userId, name: userName, photoUrl: photoUrl).toJson(),
      });

      _startHeartbeat();
      return true;
    } catch (e) {
      logger.e('Failed to connect to server: $e');
      _isConnected = false;
      return false;
    }
  }

  void _handleMessage(Map<String, dynamic> message, WebSocket? sender) {
    logger.d(
        'Handling message: ${message['type']} from ${sender != null ? 'client' : 'server/self'}');

    switch (message['type']) {
      case 'join':
        _handleUserJoined(message, sender);
        break;
      case 'leave':
        _handleUserLeft(message);
        break;
      case 'audio':
        _handleAudioMessage(message, sender);
        break;
      case 'speaking_status':
        _handleSpeakingStatus(message);
        break;
      case 'transcript':
        _handleTranscript(message, sender);
        break;
      case 'heartbeat':
        _handleHeartbeat(message, sender);
        break;
      case 'user_list':
        _handleUserList(message);
        break;
    }

    // Always add to message stream for local processing (audio playback)
    _messageController.add(message);
  }

  // In setupFirebaseRoom() method, add the userId parameter:

  Future<void> setupFirebaseRoom(String code, String userId) async {
    try {
      logger.i('Setting up Firebase room for server: $code');

      // Create new FirebaseRoomService instance with the server's userId
      final roomService = FirebaseRoomService(
        roomCode: code,
        userId: userId, // Pass the server's userId
        onMessage: _handleFirebaseMessage,
        onUsersChanged: (users) {
          _connectedUsers.clear();
          for (final user in users) {
            _connectedUsers[user.id] = user;
          }
          _userUpdateController.add(users);
        },
      );

      // Initialize the room service
      await roomService.initialize();

      // Store the room service
      _roomService = roomService;
      logger.i('Firebase room setup successful');
    } catch (e) {
      logger.e('Failed to setup Firebase room: $e');
    }
  }

  Future<void> addSelfUserToFirebase(User user) async {
    if (AppConfig.useFirebaseAsServer && _roomService != null) {
      try {
        await _roomService!.addUser(user);
        logger.i('Added self user to Firebase: ${user.name}');
      } catch (e) {
        logger.e('Failed to add self user to Firebase: $e');
      }
    }
  }

  void _handleFirebaseMessage(Map<String, dynamic> message) {
    _handleMessage(message, null);
  }

  Future<bool> _connectFirebaseRoom(String code, String userId, String userName,
      {String? photoUrl}) async {
    try {
      logger.i('Connecting to Firebase room: $code');

      // Create user object
      final user = User(id: userId, name: userName, photoUrl: photoUrl);

      final FirebaseRoomService roomService = FirebaseRoomService(
        roomCode: code,
        userId: userId,
        onMessage: _handleFirebaseMessage,
        onUsersChanged: (users) {
          _connectedUsers.clear();
          for (final user in users) {
            _connectedUsers[user.id] = user;
          }
          _userUpdateController.add(users);
        },
      );

      // Initialize room and add user
      await roomService.initialize();
      await roomService.addUser(user);

      _roomService = roomService;
      logger.i('Firebase room connection successful');
      return true;
    } catch (e) {
      logger.e('Failed to connect to Firebase room: $e');
      return false;
    }
  }

  void _handleTranscript(Map<String, dynamic> message, WebSocket? sender) {
    // If server, relay to all other clients
    if (_isServer) {
      _broadcastMessage(message, exclude: sender);
    }
    // Nothing else to do here; consumers (ViewModel) will persist via messageStream
  }

  void _handleUserJoined(Map<String, dynamic> message, WebSocket? sender) {
    final user = User.fromJson(message['user']);

    // Don't add the same user twice
    if (_connectedUsers.containsKey(user.id)) {
      logger.d('User ${user.name} already in connected users');
      return;
    }

    _connectedUsers[user.id] = user;
    logger.i(
        'User joined: ${user.name} (${user.id}), total users: ${_connectedUsers.length}');

    if (_isServer && !AppConfig.useFirebaseAsServer) {
      // Traditional WebSocket server behavior
      // Broadcast to all other clients
      _broadcastMessage(message, exclude: sender);

      // Send current user list to the new client
      if (sender != null) {
        _sendMessageToClient(sender, {
          'type': 'user_list',
          'users': _connectedUsers.values.map((u) => u.toJson()).toList(),
        });
      }
    } else if (AppConfig.useFirebaseAsServer) {
      // Firebase mode - no need to broadcast since Firebase handles it
      logger.d('Firebase mode: user joined, not broadcasting');
    }

    _userUpdateController.add(connectedUsers);
  }

  void _handleUserLeft(Map<String, dynamic> message) {
    final userId = message['userId'];
    _connectedUsers.remove(userId);
    _userUpdateController.add(connectedUsers);
  }

  void _handleAudioMessage(Map<String, dynamic> message, WebSocket? sender) {
    if (_isServer) {
      // Relay audio to all other clients
      _broadcastMessage(message, exclude: sender);
    }
    // Audio will be handled by AudioService via messageStream
    // This ensures both server and clients process audio for playback
  }

  void _handleSpeakingStatus(Map<String, dynamic> message) {
    final userId = message['userId'];
    final isSpeaking = message['isSpeaking'];

    if (_connectedUsers.containsKey(userId)) {
      final current = _connectedUsers[userId]!;
      // Update speaking status
      _connectedUsers[userId] = current.copyWith(
        isSpeaking: isSpeaking,
      );
      _userUpdateController.add(connectedUsers);
    }

    if (_isServer) {
      _broadcastMessage(message);
    }
  }

  void _handleHeartbeat(Map<String, dynamic> message, WebSocket? sender) {
    if (_isServer && sender != null) {
      // Respond to client heartbeat
      _sendMessageToClient(sender, {'type': 'heartbeat_response'});
    }
  }

  void _handleUserList(Map<String, dynamic> message) {
    if (!_isServer) {
      _connectedUsers.clear();
      final users =
          (message['users'] as List).map((u) => User.fromJson(u)).toList();
      for (final user in users) {
        _connectedUsers[user.id] = user;
      }
      _userUpdateController.add(connectedUsers);
    }
  }

  void _handleClientDisconnected(WebSocket socket) {
    _clients.remove(socket);
    // Remove user associated with this socket
    // Note: In a more robust implementation, you'd track socket-to-user mapping

    // Clean up the socket properly
    try {
      socket.close();
    } catch (e) {
      logger.e('Error closing disconnected client socket: $e');
    }
  }

  void _handleServerDisconnected() {
    _isConnected = false;
    _connectedUsers.clear();
    _userUpdateController.add([]);
    _heartbeatTimer?.cancel();

    // Clean up client socket
    try {
      _clientSocket?.close();
      _clientSocket = null;
    } catch (e) {
      logger.e('Error closing client socket on disconnect: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(AppConfig.heartbeatInterval, (timer) {
      if (_isConnected) {
        sendMessage({'type': 'heartbeat'});
      } else {
        timer.cancel();
      }
    });
  }

  void _broadcastMessage(Map<String, dynamic> message, {WebSocket? exclude}) {
    if (_isServer && !AppConfig.useFirebaseAsServer) {
      final messageStr = jsonEncode(message);
      final clientsToRemove = <WebSocket>[];

      for (final client in _clients) {
        if (client != exclude) {
          try {
            client.add(messageStr);
          } catch (e) {
            logger.e('Failed to send message to client: $e');
            clientsToRemove.add(client);
          }
        }
      }

      // Remove failed clients
      for (final client in clientsToRemove) {
        _clients.remove(client);
        try {
          client.close();
        } catch (e) {
          logger.e('Error closing failed client: $e');
        }
      }
    } else if (_isServer && AppConfig.useFirebaseAsServer) {
      // FIXED: Use FirebaseRoomService to properly route messages to correct tables
      try {
        if (_roomService != null) {
          _roomService!.sendMessage(message);
        } else {
          logger.e('FirebaseRoomService not available for broadcasting');
        }
      } catch (e) {
        logger.e('Failed to send message to Firebase: $e');
      }
    }
  }

  void _sendMessageToClient(WebSocket client, Map<String, dynamic> message) {
    try {
      client.add(jsonEncode(message));
    } catch (e) {
      logger.e('Failed to send message to client: $e');
      _clients.remove(client);
      try {
        client.close();
      } catch (closeError) {
        logger.e('Error closing failed client: $closeError');
      }
    }
  }

  void sendMessage(Map<String, dynamic> message) {
    if (AppConfig.useFirebaseAsServer && _roomService != null) {
      _roomService!.sendMessage(message);
    } else if (_isServer) {
      _broadcastMessage(message);
    } else if (_clientSocket != null) {
      try {
        _clientSocket!.add(jsonEncode(message));
      } catch (e) {
        logger.e('Failed to send message to server: $e');
        _handleServerDisconnected();
      }
    }
  }

  void sendTranscript({
    required String userId,
    required String userName,
    required String text,
    required int timestamp,
  }) {
    sendMessage({
      'type': 'transcript',
      'userId': userId,
      'userName': userName,
      'text': text,
      'timestamp': timestamp,
    });
  }

  void sendAudioData(Uint8List audioData, String userId) {
    logger.i('Sending audio data: ${audioData.length} bytes from user $userId');
    sendMessage({
      'type': 'audio',
      'userId': userId,
      'data': base64Encode(audioData),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    logger.d('Audio message queued for transmission');
  }

  void updateSpeakingStatus(String userId, bool isSpeaking) {
    if (AppConfig.useFirebaseAsServer && _roomService != null) {
      _roomService!.updateUserSpeakingStatus(userId, isSpeaking);
    } else {
      sendMessage({
        'type': 'speaking_status',
        'userId': userId,
        'isSpeaking': isSpeaking,
      });
    }
  }

  void leaveRoom(String userId) {
    sendMessage({
      'type': 'leave',
      'userId': userId,
    });
  }

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _isConnected = false;

    if (AppConfig.useFirebaseAsServer && _roomService != null) {
      await _roomService?.removeUser();
      _roomService?.dispose();
      _roomService = null;
    } else if (_isServer && !AppConfig.useFirebaseAsServer) {
      for (final client in _clients) {
        try {
          await client.close();
        } catch (e) {
          logger.e('Error closing client during disconnect: $e');
        }
      }
      _clients.clear();
      try {
        await _server?.close();
      } catch (e) {
        logger.e('Error closing server during disconnect: $e');
      }
      _server = null;
      _isServer = false;
    } else {
      try {
        await _clientSocket?.close();
      } catch (e) {
        logger.e('Error closing client socket during disconnect: $e');
      }
      _clientSocket = null;
    }

    _connectedUsers.clear();

    // Close stream controllers to prevent memory leaks
    try {
      await _messageController.close();
    } catch (e) {
      logger.e('Error closing message controller: $e');
    }
    try {
      await _userUpdateController.close();
    } catch (e) {
      logger.e('Error closing user update controller: $e');
    }
  }

  // Add self as a user when starting as server
  void addSelfUser(User user) {
    if (_isServer) {
      _connectedUsers[user.id] = user;
      logger.i(
          'Added self user: ${user.name} (${user.id}), total users: ${_connectedUsers.length}');
      _userUpdateController.add(connectedUsers);
    }
  }
}
