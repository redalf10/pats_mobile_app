import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pats_app/models/user.dart';
import 'package:provider/provider.dart';
import '../viewmodels/walkie_talkie_viewmodel.dart';
import '../widgets/connection_setup_widget.dart';
import '../widgets/connection_status_widget.dart';
import '../widgets/user_list_widget.dart';
import '../widgets/waveform_widget.dart';
import '../widgets/talk_button.dart';
import '../widgets/theme_toggle_button.dart';
import '../services/auth_service.dart';
import '../config/theme_config.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const WalkieTalkieView();
  }
}

class WalkieTalkieView extends StatefulWidget {
  const WalkieTalkieView({super.key});

  @override
  State<WalkieTalkieView> createState() => _WalkieTalkieViewState();
}

class _WalkieTalkieViewState extends State<WalkieTalkieView> {
  bool _showForceInitButton = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showForceInitButton = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      drawer: _buildDrawer(context), // Add this line
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.history),
          //   tooltip: 'Transcription History',
          //   onPressed: () {
          //     Navigator.of(context).push(
          //       MaterialPageRoute(
          //           builder: (_) => const TranscriptionHistoryPage()),
          //     );
          //   },
          // ),
          const ThemeToggleButton(),
          const SizedBox(width: 8),
          Consumer<WalkieTalkieViewModel>(
            builder: (context, viewModel, child) {
              return Container(
                margin: const EdgeInsets.only(right: 16),
                child: PopupMenuButton<String>(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(0.2),
                      ),
                    ),
                    child: Icon(
                      Icons.more_vert,
                      color: theme.colorScheme.onSurface,
                      size: 20,
                    ),
                  ),
                  color: theme.cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: (value) async {
                    if (value == 'disconnect') {
                      await viewModel.disconnect();
                    } else if (value == 'logout') {
                      await AuthService.instance.signOut();
                    }
                  },
                  itemBuilder: (BuildContext context) {
                    return [
                      if (viewModel.connectionMode !=
                          ConnectionMode.disconnected)
                        PopupMenuItem<String>(
                          value: 'disconnect',
                          child: Row(
                            children: [
                              Icon(
                                Icons.logout,
                                color: Colors.red.shade400,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Disconnect',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'logout',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.person_off,
                              color: Colors.white70,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Logout',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ];
                  },
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<WalkieTalkieViewModel>(
        builder: (context, viewModel, child) {
          // Show error snackbar if there's an error
          if (viewModel.lastError != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(viewModel.lastError!),
                  backgroundColor: Colors.red.shade700,
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(16),
                  duration: const Duration(seconds: 3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            });
          }

          if (!viewModel.isInitialized) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.surface,
                    theme.colorScheme.surface.withOpacity(0.92),
                  ],
                ),
              ),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.2),
                          ),
                        ),
                        child: Image.asset(
                          'assets/pats_logo.png',
                          height: 150,
                          width: 150,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.2),
                          ),
                        ),
                        child: const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.secondaryColor,
                          ),
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Initializing app...',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_showForceInitButton) ...[
                        const SizedBox(height: 32),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.surface,
                                theme.colorScheme.surface.withOpacity(0.8),
                              ],
                            ),
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              viewModel.forceInitialize();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'Continue without permissions',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Taking too long? You can continue and grant permissions later.',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }

          if (viewModel.connectionMode == ConnectionMode.disconnected) {
            return ConnectionSetupWidget(viewModel: viewModel);
          }

          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.surface,
                  theme.colorScheme.surface.withOpacity(0.92),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // ConnectionStatusWidget(viewModel: viewModel),
                  Expanded(
                    child: UserListWidget(users: viewModel.users),
                  ),
                  Column(
                    children: [
                      WaveformWidget(isTalking: viewModel.isTalking),
                      const SizedBox(height: 16),
                      TalkButton(
                        isTalking: viewModel.isTalking,
                        onTalkStart: viewModel.startTalking,
                        onTalkEnd: viewModel.stopTalking,
                        enabled: true, // Connection-based enabling
                        userRole: viewModel.currentUserRole,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Add this method to build the drawer:
  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withOpacity(0.2),
                  ),
                ),
              ),
              child: Consumer<WalkieTalkieViewModel>(
                builder: (context, viewModel, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.meeting_room,
                            color: AppTheme.secondaryColor,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Room Code',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.secondaryColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              viewModel.roomCode ?? 'Not Connected',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                                color: AppTheme.secondaryColor,
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                final roomCode = viewModel.roomCode;
                                if (roomCode != null) {
                                  Clipboard.setData(
                                      ClipboardData(text: roomCode));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Room code copied!'),
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: AppTheme.secondaryColor,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              icon: Icon(
                                Icons.copy,
                                color: AppTheme.secondaryColor,
                                size: 20,
                              ),
                              tooltip: 'Copy room code',
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: Consumer<WalkieTalkieViewModel>(
                builder: (context, viewModel, _) {
                  return ListView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.people,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Connected Users (${viewModel.users.length})',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...viewModel.users
                          .map((user) => _buildUserListTile(user, theme)),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border(
                  top: BorderSide(
                    color: theme.dividerColor.withOpacity(0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Share the room code with others to let them join the conversation.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Add this helper method for user list tiles:
  Widget _buildUserListTile(User user, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: user.isSpeaking
              ? AppTheme.secondaryColor.withOpacity(0.5)
              : theme.dividerColor.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: user.photoUrl != null && user.photoUrl!.isNotEmpty
                      ? Image.network(
                          user.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) =>
                              _defaultAvatar(theme, user.isSpeaking),
                        )
                      : _defaultAvatar(theme, user.isSpeaking),
                ),
              ),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        user.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getRoleColor(user.role).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _getRoleDisplayName(user.role),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _getRoleColor(user.role),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        user.isSpeaking ? 'Speaking...' : 'Listening',
                        style: TextStyle(
                          fontSize: 14,
                          color: user.isSpeaking
                              ? AppTheme.secondaryColor
                              : theme.colorScheme.onSurface.withOpacity(0.7),
                          fontWeight: user.isSpeaking
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ],
              ),
            ],
          ),
          if (user.isSpeaking)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppTheme.secondaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.secondaryColor,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Add these methods inside the _WalkieTalkieViewState class:
  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.pilot1:
        return Colors.blue;
      case UserRole.pilot2:
        return Colors.green;
      case UserRole.tower:
        return Colors.orange;
      case UserRole.inspector:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getRoleDisplayName(UserRole role) {
    switch (role) {
      case UserRole.pilot1:
        return 'PILOT 1';
      case UserRole.pilot2:
        return 'PILOT 2';
      case UserRole.tower:
        return 'TOWER';
      case UserRole.inspector:
        return 'INSPECTOR';
      default:
        return 'UNKNOWN';
    }
  }

  Widget _defaultAvatar(ThemeData theme, bool isSpeaking) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isSpeaking
              ? [AppTheme.secondaryColor, AppTheme.secondaryDarkColor]
              : [
                  theme.colorScheme.surface,
                  theme.colorScheme.surface.withOpacity(0.8),
                ],
        ),
        shape: BoxShape.rectangle,
      ),
      child: Icon(
        isSpeaking ? Icons.mic : Icons.person,
        color: Colors.white,
        size: isSpeaking ? 24 : 20,
      ),
    );
  }
}
