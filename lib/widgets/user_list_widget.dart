import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/transcription.dart';
import '../services/firebase_service.dart';
import '../config/theme_config.dart';
import '../viewmodels/transcription_viewmodel.dart';

class UserListWidget extends StatelessWidget {
  final List<User> users;

  const UserListWidget({super.key, required this.users});

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

  Widget _buildUserCard(User user, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.cardColor,
            theme.colorScheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: user.isSpeaking
              ? AppTheme.secondaryColor.withOpacity(0.5)
              : theme.dividerColor.withOpacity(0.2),
          width: user.isSpeaking ? 2 : 1,
        ),
      ),
      child: Row(
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
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                _roleBadge(user, theme),
                const SizedBox(height: 6),
                Text(
                  user.isSpeaking ? 'Speaking...' : 'Listening',
                  style: TextStyle(
                    fontSize: 14,
                    color: user.isSpeaking
                        ? AppTheme.secondaryColor
                        : theme.colorScheme.onSurface.withOpacity(0.7),
                    fontWeight:
                        user.isSpeaking ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          if (user.isSpeaking)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppTheme.secondaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.secondaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.secondaryColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _roleBadge(User user, ThemeData theme) {
    final role = user.role;
    String label;
    Color bg;
    Color textColor = Colors.white;

    switch (role) {
      case Role.tower1:
        label = 'Tower 1';
        bg = AppTheme.secondaryColor;
        break;
      case Role.tower2:
        label = 'Tower 2';
        bg = AppTheme.secondaryDarkColor;
        break;
      case Role.pilot:
        label = 'Pilot';
        bg = Colors.blueAccent;
        break;
      case Role.inspector:
      default:
        label = 'Inspector';
        bg = theme.dividerColor.withOpacity(0.2);
        textColor = theme.colorScheme.onSurface.withOpacity(0.8);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildTranscriptItem(
    BuildContext context,
    Transcription transcription,
    ThemeData theme,
    bool isLatest,
  ) {
    final time = DateTime.fromMillisecondsSinceEpoch(transcription.timestamp);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLatest
            ? theme.colorScheme.surface.withOpacity(0.8)
            : theme.colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLatest
              ? AppTheme.secondaryColor.withOpacity(0.3)
              : theme.dividerColor.withOpacity(0.1),
          width: isLatest ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isLatest
                      ? AppTheme.secondaryColor
                      : AppTheme.secondaryColor.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                transcription.userName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.secondaryColor,
                ),
              ),
              const SizedBox(width: 8),
              if (isLatest)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
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
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.secondaryColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Transcription text
          Text(
            transcription.text,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withOpacity(0.9),
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),

          // Synonyms section with proper analysis trigger
          Consumer<TranscriptionViewModel>(
            builder: (context, viewModel, child) {
              final transcriptionId = transcription.timestamp;
              final isLoading =
                  viewModel.isLoadingForTranscription(transcriptionId);
              final synonyms =
                  viewModel.getSynonymsForTranscription(transcriptionId);
              final hasBeenAnalyzed =
                  viewModel.hasBeenAnalyzed(transcriptionId);

              // Only trigger analysis once using hasBeenAnalyzed check
              if (!hasBeenAnalyzed && !isLoading) {
                // Use Future.microtask to avoid calling during build
                Future.microtask(() {
                  viewModel.analyzeSynonyms(
                      transcriptionId, transcription.text);
                });
              }

              if (isLoading) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: AppTheme.secondaryColor,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Analyzing aviation terms...',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (synonyms.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('No Suggestions'),
                );
              }

              return Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.secondaryColor.withOpacity(0.15),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: 14,
                          color: AppTheme.secondaryColor.withOpacity(0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Aviation Terms',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.secondaryColor.withOpacity(0.9),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: synonyms.entries.map((entry) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppTheme.secondaryColor.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${entry.key}: ',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.secondaryColor,
                                  ),
                                ),
                                TextSpan(
                                  text: entry.value.join(', '),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptSection(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final transcriptions =
          context.read<FirebaseDbService>().getAllNewestFirst();
      print('🔄 Current transcriptions in DB: ${transcriptions.length}');
      for (var t in transcriptions) {
        print('   - ${t.userName}: "${t.text}" (id: ${t.id})');
      }
    });

    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.2),
        ),
        color: theme.cardColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Live Transcript',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _clearTranscriptions(context),
                icon: Icon(
                  Icons.clear_all,
                  size: 20,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
                tooltip: 'Clear all transcriptions',
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: Consumer<FirebaseDbService>(
              builder: (context, dbService, child) {
                // FIXED: Check if database is initialized properly
                if (!dbService.isInitialized) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          color: AppTheme.secondaryColor,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Initializing database...',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // FIXED: Use the correct stream method that exists in your service
                return StreamBuilder<List<Transcription>>(
                  stream: dbService.watchAllNewestFirst(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(
                              color: AppTheme.secondaryColor,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Loading transcript...',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final transcriptions = snapshot.data ?? [];

                    // Debug logging
                    debugPrint(
                        'Transcriptions count: ${transcriptions.length}');

                    if (transcriptions.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.mic_off,
                              size: 32,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.3),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No transcriptions yet',
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.5),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Press and hold the talk button to speak',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: transcriptions.length,
                      itemBuilder: (context, index) {
                        final transcription = transcriptions[index];
                        final isLatest = index == 0;

                        return _buildTranscriptItem(
                          context,
                          transcription,
                          theme,
                          isLatest,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Users Section
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.dividerColor.withOpacity(0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                      'Connected Users (${users.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
                if (users.isEmpty) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 48,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No users connected',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Waiting for people to join...',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  ...users.map((user) => _buildUserCard(user, theme)).toList(),
                ],
              ],
            ),
          ),

          // Transcripts Section
          _buildTranscriptSection(context),
        ],
      ),
    );
  }

  void _clearTranscriptions(BuildContext context) {
    final dbService = context.read<FirebaseDbService>();
    dbService.clearAllTranscriptions();
  }
}
