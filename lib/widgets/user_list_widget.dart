import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/transcription.dart';
import '../services/firebase_service.dart';
import '../services/audio_service.dart';
import '../config/theme_config.dart';
import '../viewmodels/transcription_viewmodel.dart';
import '../viewmodels/walkie_talkie_viewmodel.dart';

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

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.pilot1:
        return Colors.blue;
      case UserRole.pilot2:
        return Colors.cyan;
      case UserRole.tower:
        return Colors.orange;
      case UserRole.inspector:
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
    }
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getRoleColor(user.role).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _getRoleColor(user.role).withOpacity(0.3),
                          width: 1,
                        ),
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

          // Audio Playback Section
          if (transcription.audioData != null &&
              transcription.audioData!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.secondaryColor.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Consumer<AudioService>(
                builder: (context, audioService, child) {
                  final isPlaying = audioService.isPlaying;
                  final audioSize = transcription.audioData?.length ?? 0;
                  final audioSizeKB = (audioSize / 1024).toStringAsFixed(1);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.audiotrack,
                            size: 16,
                            color: AppTheme.secondaryColor.withOpacity(0.7),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Audio Recording',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.secondaryColor
                                        .withOpacity(0.8),
                                  ),
                                ),
                                Text(
                                  '${audioSizeKB} KB • WAV format',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => _playAudio(context, transcription),
                            icon: Icon(
                              isPlaying ? Icons.stop : Icons.play_arrow,
                              color: isPlaying
                                  ? Colors.red
                                  : AppTheme.secondaryColor,
                              size: 20,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: isPlaying
                                  ? Colors.red.withOpacity(0.1)
                                  : AppTheme.secondaryColor.withOpacity(0.1),
                              padding: const EdgeInsets.all(8),
                            ),
                            tooltip: isPlaying ? 'Stop audio' : 'Play audio',
                          ),
                        ],
                      ),
                      if (isPlaying) ...[
                        const SizedBox(height: 8),
                        Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 60, // Visual progress indicator
                                height: 3,
                                decoration: BoxDecoration(
                                  color: AppTheme.secondaryColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Playing audio...',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.secondaryColor,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],

          // Aviation Terms Analysis Section
          Consumer<TranscriptionViewModel>(
            builder: (context, viewModel, child) {
              final transcriptionId = transcription.timestamp;
              final isLoading =
                  viewModel.isLoadingForTranscription(transcriptionId);
              final synonyms =
                  viewModel.getSynonymsForTranscription(transcriptionId);
              final hasBeenAnalyzed =
                  viewModel.hasBeenAnalyzed(transcriptionId);

              // Manual trigger - no automatic analysis

              // Show loading indicator while analyzing
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

              // Show message if no aviation terms found
              if (synonyms.isEmpty && hasBeenAnalyzed) {
                return Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'No aviation terms detected',
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

              // Show aviation terms if found
              if (synonyms.isNotEmpty) {
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
                            Icons.flight,
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
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${synonyms.length}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.secondaryColor,
                              ),
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
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppTheme.secondaryColor.withOpacity(0.1),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ],
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
              }

              // Show "See Aviation Terms" button if not analyzed yet
              return Container(
                margin: const EdgeInsets.only(top: 12),
                child: ElevatedButton.icon(
                  onPressed: () {
                    print(
                        '🚁 Manual trigger: Analyzing aviation terms for: ${transcription.text}');
                    viewModel.analyzeSynonyms(
                        transcriptionId, transcription.text);
                  },
                  icon: Icon(
                    Icons.flight,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: Text(
                    'See Aviation Terms',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 2,
                  ),
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
      final dbService = context.read<FirebaseDbService>();
      final transcriptions = dbService.getAllNewestFirst();
      print('🔄 UI: Current transcriptions in DB: ${transcriptions.length}');
      print('🔄 UI: Database initialized: ${dbService.isInitialized}');
      print('🔄 UI: Room set: ${dbService.isRoomSet}');
      print('🔄 UI: Room path: ${dbService.currentRoomPath}');
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
              Consumer<AudioService>(
                builder: (context, audioService, child) {
                  if (audioService.isPlaying) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.secondaryColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.volume_up,
                            size: 14,
                            color: AppTheme.secondaryColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Playing',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.secondaryColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => audioService.stopAudioPlayback(),
                            child: Icon(
                              Icons.stop,
                              size: 16,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(width: 8),
              Consumer<WalkieTalkieViewModel>(
                builder: (context, viewModel, child) {
                  return IconButton(
                    onPressed: () => viewModel.toggleAutoPlayAudio(),
                    icon: Icon(
                      viewModel.autoPlayAudio
                          ? Icons.volume_up
                          : Icons.volume_off,
                      size: 20,
                      color: viewModel.autoPlayAudio
                          ? AppTheme.secondaryColor
                          : theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                    tooltip: viewModel.autoPlayAudio
                        ? 'Disable auto-playback'
                        : 'Enable auto-playback',
                  );
                },
              ),
              IconButton(
                onPressed: () => _removeDuplicates(context),
                icon: Icon(
                  Icons.merge_type,
                  size: 20,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
                tooltip: 'Remove duplicate transcriptions',
              ),
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
                    print(
                        '🔄 UI StreamBuilder: Transcriptions count: ${transcriptions.length}');
                    print(
                        '🔄 UI StreamBuilder: Connection state: ${snapshot.connectionState}');
                    print('🔄 UI StreamBuilder: Has data: ${snapshot.hasData}');
                    print(
                        '🔄 UI StreamBuilder: Has error: ${snapshot.hasError}');
                    if (snapshot.hasError) {
                      print('🔄 UI StreamBuilder: Error: ${snapshot.error}');
                    }

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
                  ...users.map((user) => _buildUserCard(user, theme)),
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

  void _removeDuplicates(BuildContext context) {
    final dbService = context.read<FirebaseDbService>();
    dbService.removeDuplicateTranscriptions();
  }

  void _playAudio(BuildContext context, Transcription transcription) async {
    try {
      final audioService = context.read<AudioService>();

      // Check if audio is currently playing
      if (audioService.isPlaying) {
        // Stop current audio
        await audioService.stopAudioPlayback();
        print('🎵 Stopped audio playback');
        return;
      }

      // Decode and play audio
      if (transcription.audioData != null &&
          transcription.audioData!.isNotEmpty) {
        print('🎵 Playing audio for transcript: "${transcription.text}"');

        try {
          final audioData = base64Decode(transcription.audioData!);
          await audioService.playAudioData(Uint8List.fromList(audioData));
          print('🎵 Audio playback started successfully');

          // Show a snackbar to indicate playback started
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text('Playing audio from ${transcription.userName}'),
                  ],
                ),
                backgroundColor: AppTheme.secondaryColor,
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        } catch (e) {
          print('❌ Error playing audio: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text('Failed to play audio: $e'),
                  ],
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        }
      } else {
        print('⚠️ No audio data available for this transcript');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text('No audio available for this transcript'),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error in _playAudio: $e');
    }
  }
}
