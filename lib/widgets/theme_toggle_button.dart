import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../config/theme_config.dart';

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return PopupMenuButton<ThemeMode>(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
              ),
            ),
            child: Icon(
              themeProvider.isDarkMode
                  ? Icons.dark_mode
                  : themeProvider.isLightMode
                      ? Icons.light_mode
                      : Icons.brightness_auto,
              color: Theme.of(context).colorScheme.onSurface,
              size: 20,
            ),
          ),
          color: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onSelected: (ThemeMode mode) {
            themeProvider.setThemeMode(mode);
          },
          itemBuilder: (BuildContext context) {
            return [
              PopupMenuItem<ThemeMode>(
                value: ThemeMode.light,
                child: Row(
                  children: [
                    const Icon(
                      Icons.light_mode,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Light',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: themeProvider.isLightMode
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    if (themeProvider.isLightMode) ...[
                      const Spacer(),
                      const Icon(
                        Icons.check,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuItem<ThemeMode>(
                value: ThemeMode.dark,
                child: Row(
                  children: [
                    const Icon(
                      Icons.dark_mode,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Dark',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: themeProvider.isDarkMode
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    if (themeProvider.isDarkMode) ...[
                      const Spacer(),
                      const Icon(
                        Icons.check,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuItem<ThemeMode>(
                value: ThemeMode.system,
                child: Row(
                  children: [
                    const Icon(
                      Icons.brightness_auto,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'System',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: themeProvider.isSystemMode
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    if (themeProvider.isSystemMode) ...[
                      const Spacer(),
                      const Icon(
                        Icons.check,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                    ],
                  ],
                ),
              ),
            ];
          },
        );
      },
    );
  }
}
