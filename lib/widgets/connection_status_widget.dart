import 'package:flutter/material.dart';
import '../viewmodels/walkie_talkie_viewmodel.dart';
import '../config/theme_config.dart';

class ConnectionStatusWidget extends StatelessWidget {
  final WalkieTalkieViewModel viewModel;

  const ConnectionStatusWidget({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (viewModel.connectionMode) {
      case ConnectionMode.server:
        statusText = viewModel.roomCode != null
            ? 'Room Code: ${viewModel.roomCode}'
            : 'Server Room';
        statusColor = AppTheme.secondaryColor;
        statusIcon = Icons.wifi;
        break;
      case ConnectionMode.client:
        statusText = viewModel.roomCode != null
            ? 'Joined Room: ${viewModel.roomCode}'
            : 'Joined Room';
        statusColor = const Color(0xFF4CAF50);
        statusIcon = Icons.link;
        break;
      default:
        statusText = 'Disconnected';
        statusColor = Colors.red.shade400;
        statusIcon = Icons.link_off;
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor.withOpacity(0.1),
            statusColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              statusIcon,
              color: statusColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                    fontSize: 16,
                  ),
                ),
                if (viewModel.connectionMode != ConnectionMode.disconnected)
                  Text(
                    '${viewModel.users.length} connected',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  viewModel.connectionMode == ConnectionMode.disconnected
                      ? 'Offline'
                      : 'Online',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
