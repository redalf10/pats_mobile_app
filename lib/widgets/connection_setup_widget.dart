import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../viewmodels/walkie_talkie_viewmodel.dart';
import '../config/theme_config.dart';
import '../models/user.dart';
import 'role_selection_dialog.dart';

class ConnectionSetupWidget extends StatefulWidget {
  final WalkieTalkieViewModel viewModel;

  const ConnectionSetupWidget({super.key, required this.viewModel});

  @override
  State<ConnectionSetupWidget> createState() => _ConnectionSetupWidgetState();
}

class _ConnectionSetupWidgetState extends State<ConnectionSetupWidget>
    with TickerProviderStateMixin {
  final _serverIPController = TextEditingController();
  bool _isConnecting = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF1A1A1A),
                    const Color(0xFF1A1A1A),
                  ]
                : [
                    AppTheme.primaryColor,
                    AppTheme.primaryColor,
                  ],
          ),
        ),
        child: SafeArea(
          // Use RepaintBoundary to prevent unnecessary repaints of the entire tree
          child: RepaintBoundary(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/pats_logo.png',
                        height: 200,
                      ),

                      const SizedBox(height: 10),
                      Text(
                        'Choose your connection mode',
                        style: TextStyle(
                          fontSize: 16,
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Server Mode Card
                      _buildModeCard(
                        title: 'Create Room (Server)',
                        subtitle: 'Create a room code that others can join',
                        icon: Icons.meeting_room,
                        gradient: const LinearGradient(
                          colors: [
                            AppTheme.primaryLightColor,
                            AppTheme.primaryLightColor
                          ],
                        ),
                        onPressed: _isConnecting ? null : _startServer,
                        isLoading: _isConnecting,
                      ),

                      const SizedBox(height: 24),

                      // Client Mode Card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF4CAF50),
                                    Color(0xFF45A049)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.link,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Join a Room',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Enter the 6-character room code',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: theme.dividerColor.withOpacity(0.3),
                                ),
                              ),
                              child: TextField(
                                controller: _serverIPController,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 16,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Room Code',
                                  hintText: 'ABC123',
                                  labelStyle: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.7),
                                  ),
                                  hintStyle: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.5),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.all(20),
                                ),
                                textCapitalization:
                                    TextCapitalization.characters,
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF4CAF50),
                                      Color(0xFF45A049)
                                    ],
                                  ),
                                ),
                                child: ElevatedButton(
                                  onPressed:
                                      _isConnecting ? null : _connectToServer,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _isConnecting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : const Text(
                                          'Connect',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
  }

  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Gradient gradient,
    required VoidCallback? onPressed,
    required bool isLoading,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: gradient,
              ),
              child: ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Start Server',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startServer() async {
    setState(() => _isConnecting = true);
    HapticFeedback.mediumImpact();

    try {
      // First show role selection dialog
      final selectedRole = await _showServerRoleSelectionDialog();

      if (selectedRole != null) {
        print(
            '🔍 Role selected, creating server with role: ${selectedRole.name}');
        // Create server with the selected role
        final code = await widget.viewModel.startAsServerWithRole(selectedRole);
        print('🔍 Server creation result: ${code ?? 'null'}');
        if (code != null) {
          print('🔍 Showing server started dialog');
          // Add a small delay to ensure the role selection dialog is fully closed
          await Future.delayed(const Duration(milliseconds: 100));
          await _showServerStartedDialog(code);
        } else {
          print('🔍 Server creation failed, showing error dialog');
          _showErrorDialog(
            'Failed to start server',
            'Unable to start room server. Please try again.',
          );
        }
      } else {
        print('🔍 No role selected, staying on connection screen');
      }
      // If user cancels role selection, do nothing (stay on connection screen)
    } catch (e) {
      _showErrorDialog('Error starting server', '$e');
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<UserRole?> _showServerRoleSelectionDialog() async {
    print('🔍 Showing server role selection dialog');

    final selectedRole = await showDialog<UserRole>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        print('🔍 Building server role selection dialog');
        return RoleSelectionDialog(
          roomCode: 'TBD', // Will be generated after role selection
          existingUsers: [], // No existing users when creating server
          onRoleSelected: (role) {
            print('🔍 Server creator selected role: ${role.name}');
            Navigator.of(context).pop(role);
          },
        );
      },
    );

    print(
        '🔍 Server role dialog closed, selected role: ${selectedRole?.name ?? 'none'}');
    return selectedRole;
  }

  Future<void> _connectToServer() async {
    final code = _serverIPController.text.trim();
    print('🔍 Attempting to connect with code: $code');

    if (code.isEmpty) {
      _showErrorDialog(
        'Missing Room Code',
        'Please enter a 6-digit room code.',
      );
      return;
    }
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code.toUpperCase())) {
      _showErrorDialog(
        'Invalid Room Code',
        'Room code must be 6 letters/numbers (A-Z, 0-9).',
      );
      return;
    }

    print('🔍 Code validation passed, showing role selection dialog');
    // Show role selection dialog before connecting
    await _showRoleSelectionDialog(code.toUpperCase());
  }

  Future<void> _showRoleSelectionDialog(String roomCode) async {
    print('🔍 Showing role selection dialog for room: $roomCode');

    // Show role selection dialog immediately with empty user list
    // We'll get the actual user list after connecting
    final selectedRole = await showDialog<UserRole>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        print('🔍 Building role selection dialog');
        return RoleSelectionDialog(
          roomCode: roomCode,
          existingUsers: [], // Start with empty list, will be updated after connection
          onRoleSelected: (role) {
            print('🔍 Role selected: ${role.name}');
            Navigator.of(context).pop(role);
          },
        );
      },
    );

    print('🔍 Dialog closed, selected role: ${selectedRole?.name ?? 'none'}');

    if (selectedRole != null) {
      print(
          '🔍 Client role selected: ${selectedRole.name}, connecting to room: $roomCode');
      await _connectWithRole(roomCode, selectedRole);
    } else {
      print('🔍 Client role selection cancelled');
    }
    // If user cancels, do nothing (stay on connection screen)
  }

  Future<void> _connectWithRole(String roomCode, UserRole role) async {
    setState(() => _isConnecting = true);
    HapticFeedback.mediumImpact();

    try {
      // Disconnect first if already connected
      if (widget.viewModel.connectionMode != ConnectionMode.disconnected) {
        await widget.viewModel.disconnect();
      }

      // Connect with the selected role
      final success =
          await widget.viewModel.connectToServerWithRole(roomCode, role);
      if (!success) {
        _showErrorDialog(
          'Connection Failed',
          'Failed to join room with selected role.',
        );
      }
    } catch (e) {
      _showErrorDialog('Error connecting to server', '$e');
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  Future<void> _showServerStartedDialog(String code) async {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Color(0xFF4CAF50),
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Room Created!',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Share this code with others to join:',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          code,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.secondaryColor,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: code));
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Room code copied!'),
                                backgroundColor: const Color(0xFF4CAF50),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.copy,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Anyone with this code can join your room while the app is open.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [
                          AppTheme.secondaryColor,
                          AppTheme.secondaryDarkColor
                        ],
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Got it!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showErrorDialog(String title, String message) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.error_outline,
                    color: Colors.red.shade400,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.surface,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'OK',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _serverIPController.dispose();
    _fadeController.dispose();
    super.dispose();
  }
}
