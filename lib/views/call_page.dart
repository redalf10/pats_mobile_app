import 'package:flutter/material.dart';
import 'package:pats_app/models/user.dart';
import 'package:pats_app/services/audio_service.dart';
import 'package:pats_app/services/local_db_service.dart';
import 'package:pats_app/widgets/transcript_handler.dart';
import 'package:pats_app/widgets/user_list_widget.dart';
import 'package:provider/provider.dart';

class CallPage extends StatefulWidget {
  final String roomCode;
  final String userId;
  final String userName;

  const CallPage({
    super.key,
    required this.roomCode,
    required this.userId,
    required this.userName,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late AudioService _audioService;
  late LocalDbService _dbService;
  late TranscriptionHandler _transcriptionHandler;

  // Mock users list - replace with your actual user management
  List<User> _users = [];
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _audioService = AudioService();
    _dbService = context.read<LocalDbService>();
    _transcriptionHandler = TranscriptionHandler(
      audioService: _audioService,
      dbService: _dbService,
    );

    // Initialize room
    _initializeRoom();
  }

  Future<void> _initializeRoom() async {
    try {
      await _dbService.setRoom(widget.roomCode);
      print('Room ${widget.roomCode} initialized');
    } catch (e) {
      print('Error initializing room: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    // Request permissions
    final hasPermission = await _audioService.requestPermissions();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    // Start STT listening
    final started = await _audioService.startListening();
    if (!started) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start speech recognition')),
        );
      }
      return;
    }

    // Start handling transcriptions
    _transcriptionHandler.startListening(
      userId: widget.userId,
      userName: widget.userName,
    );

    setState(() {
      _isRecording = true;
      // Update user speaking status
      _updateUserSpeakingStatus(widget.userId, true);
    });

    print('Recording and transcription started');
  }

  Future<void> _stopRecording() async {
    // Stop STT listening
    await _audioService.stopListening();

    // Stop handling transcriptions
    _transcriptionHandler.stopListening();

    setState(() {
      _isRecording = false;
      // Update user speaking status
      _updateUserSpeakingStatus(widget.userId, false);
    });

    print('Recording and transcription stopped');
  }

  void _updateUserSpeakingStatus(String userId, bool isSpeaking) {
    // Update the speaking status in your user list
    // This is a mock implementation - replace with your actual logic
    final userIndex = _users.indexWhere((u) => u.id == userId);
    if (userIndex != -1) {
      setState(() {
        _users[userIndex] = User(
          id: _users[userIndex].id,
          name: _users[userIndex].name,
          photoUrl: _users[userIndex].photoUrl,
          role: _users[userIndex].role,
          isSpeaking: isSpeaking,
        );
      });
    }
  }

  @override
  void dispose() {
    _transcriptionHandler.dispose();
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Room: ${widget.roomCode}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // Show room info
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // User list and transcriptions
          Expanded(
            child: UserListWidget(users: _users),
          ),

          // Recording controls
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Recording status indicator
                  if (_isRecording) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Recording...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Record button
                  GestureDetector(
                    onTap: _toggleRecording,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _isRecording
                              ? [Colors.red, Colors.red.shade700]
                              : [Colors.blue, Colors.blue.shade700],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? Colors.red : Colors.blue)
                                .withOpacity(0.3),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isRecording ? 'Tap to stop' : 'Tap to speak',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
