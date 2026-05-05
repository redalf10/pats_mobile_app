import 'package:flutter/material.dart';
import '../models/user.dart';
import '../config/theme_config.dart';

class RoleSelectionDialog extends StatefulWidget {
  final String roomCode;
  final List<User> existingUsers;
  final Function(UserRole) onRoleSelected;

  const RoleSelectionDialog({
    super.key,
    required this.roomCode,
    required this.existingUsers,
    required this.onRoleSelected,
  });

  @override
  State<RoleSelectionDialog> createState() => _RoleSelectionDialogState();
}

class _RoleSelectionDialogState extends State<RoleSelectionDialog> {
  UserRole? _selectedRole;

  @override
  Widget build(BuildContext context) {
    print('🔍 RoleSelectionDialog build() called');
    final theme = Theme.of(context);
    final availableRoles = _getAvailableRoles();
    print('🔍 Available roles: ${availableRoles.map((r) => r.name).toList()}');
    print(
        '🔍 Existing users: ${widget.existingUsers.map((u) => '${u.name} (${u.role.name})').toList()}');

    return Dialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 400,
          maxHeight: 600,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.flight,
                    color: AppTheme.secondaryColor,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  'Select Your Role',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  widget.roomCode == 'TBD'
                      ? 'Creating New Room'
                      : 'Room Code: ${widget.roomCode}',
                  style: TextStyle(
                    color: AppTheme.secondaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'Choose your role in this aviation simulation room. Only one person can be each pilot or tower role.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),

                // Role Selection
                ...availableRoles.map((role) => _buildRoleCard(role, theme)),

                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          side: BorderSide(
                            color: theme.dividerColor.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: _selectedRole != null
                                ? [
                                    AppTheme.secondaryColor,
                                    AppTheme.secondaryDarkColor
                                  ]
                                : [Colors.grey, Colors.grey.shade600],
                          ),
                        ),
                        child: ElevatedButton(
                          onPressed:
                              _selectedRole != null ? _confirmRole : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            widget.roomCode == 'TBD'
                                ? 'Create Room'
                                : 'Join Room',
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(UserRole role, ThemeData theme) {
    final isSelected = _selectedRole == role;
    final isTaken = _isRoleTaken(role);
    final canSelect = !isTaken;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canSelect ? () => setState(() => _selectedRole = role) : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.secondaryColor.withOpacity(0.1)
                  : theme.colorScheme.surface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? AppTheme.secondaryColor
                    : isTaken
                        ? Colors.red.withOpacity(0.3)
                        : theme.dividerColor.withOpacity(0.2),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.secondaryColor
                        : isTaken
                            ? Colors.red.withOpacity(0.2)
                            : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getRoleIcon(role),
                    color: isSelected
                        ? Colors.white
                        : isTaken
                            ? Colors.red
                            : theme.colorScheme.onSurface.withOpacity(0.7),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getRoleTitle(role),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isTaken
                              ? Colors.red
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getRoleDescription(role),
                        style: TextStyle(
                          fontSize: 12,
                          color: isTaken
                              ? Colors.red.withOpacity(0.7)
                              : theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      if (isTaken) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Already taken',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<UserRole> _getAvailableRoles() {
    return UserRole.values;
  }

  bool _isRoleTaken(UserRole role) {
    return widget.existingUsers.any((user) => user.role == role);
  }

  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.pilot1:
        return Icons.flight;
      case UserRole.pilot2:
        return Icons.flight_takeoff;
      case UserRole.tower:
        return Icons.radio;
      case UserRole.inspector:
        return Icons.visibility;
    }
  }

  String _getRoleTitle(UserRole role) {
    switch (role) {
      case UserRole.pilot1:
        return 'Pilot 1';
      case UserRole.pilot2:
        return 'Pilot 2';
      case UserRole.tower:
        return 'Tower';
      case UserRole.inspector:
        return 'Inspector';
    }
  }

  String _getRoleDescription(UserRole role) {
    switch (role) {
      case UserRole.pilot1:
        return 'Primary pilot - can use microphone';
      case UserRole.pilot2:
        return 'Secondary pilot - can use microphone';
      case UserRole.tower:
        return 'Air traffic control - can use microphone';
      case UserRole.inspector:
        return 'Observer - microphone disabled, can listen';
    }
  }

  void _confirmRole() {
    if (_selectedRole != null) {
      widget.onRoleSelected(_selectedRole!);
      // Don't call Navigator.pop() here - let the parent handle it
    }
  }
}
