import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme_config.dart';
import '../models/user.dart';

class TalkButton extends StatefulWidget {
  final bool isTalking;
  final VoidCallback onTalkStart;
  final VoidCallback onTalkEnd;
  final bool enabled;
  final UserRole? userRole;

  const TalkButton({
    super.key,
    required this.isTalking,
    required this.onTalkStart,
    required this.onTalkEnd,
    this.enabled = true,
    this.userRole,
  });

  @override
  State<TalkButton> createState() => _TalkButtonState();
}

class _TalkButtonState extends State<TalkButton> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(TalkButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTalking != oldWidget.isTalking) {
      if (widget.isTalking) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
        // Reset talking state when external talking stops
        _isTalkingStarted = false;
        _ignoreCancelEvents = false;
      }
    }
  }

  bool _isTouchActive = false;
  bool _isTalkingStarted = false;
  bool _ignoreCancelEvents = false;
  Timer? _holdTimer;
  static const Duration _minHoldDuration = Duration(milliseconds: 100);

  void _handleTapDown(TapDownDetails details) {
    if (_isTouchActive || !widget.enabled || !_canUseMicrophone()) {
      print(
          '🎤 Talk button tap ignored: active=$_isTouchActive, enabled=${widget.enabled}, canUseMic=${_canUseMicrophone()}');
      return;
    }

    _isTouchActive = true;
    _ignoreCancelEvents = false; // Reset cancel ignore flag
    _scaleController.forward();
    HapticFeedback.mediumImpact();

    // Add minimum hold duration to prevent accidental triggers
    _holdTimer = Timer(_minHoldDuration, () {
      if (_isTouchActive) {
        print('🎤 Talk button held long enough - starting talk');
        _isTalkingStarted = true;
        _ignoreCancelEvents = true; // Ignore cancel events once talking starts
        widget.onTalkStart();
      }
    });
  }

  void _handleTapUp(TapUpDetails details) {
    if (!_isTouchActive) return;

    _holdTimer?.cancel();
    _isTouchActive = false;
    _ignoreCancelEvents = false; // Reset cancel ignore flag
    _scaleController.reverse();

    if (_isTalkingStarted) {
      print('🎤 Talk button released - stopping talk');
      widget.onTalkEnd();
      _isTalkingStarted = false;
    } else {
      print('🎤 Talk button released - no talk started');
    }
  }

  void _handleTapCancel() {
    if (!_isTouchActive) return;

    if (_ignoreCancelEvents && _isTalkingStarted) {
      print(
          '🎤 Talk button tap cancelled - IGNORING because talking is active');
      // Don't do anything - keep talking active
      return;
    }

    print(
        '🎤 Talk button cancelled - but continuing to hold if talking started');

    // Don't cancel the talking state immediately on tap cancel
    // Only cancel the visual feedback
    _holdTimer?.cancel();
    _isTouchActive = false;
    _scaleController.reverse();

    // Don't stop talking on tap cancel - let the user continue holding
    // The talking will only stop when they actually release (onTapUp)
  }

  void _handlePointerDown(PointerDownEvent details) {
    if (_isTouchActive || !widget.enabled || !_canUseMicrophone()) {
      print(
          '🎤 Talk button pointer down ignored: active=$_isTouchActive, enabled=${widget.enabled}, canUseMic=${_canUseMicrophone()}');
      return;
    }

    _isTouchActive = true;
    _ignoreCancelEvents = false; // Reset cancel ignore flag
    _scaleController.forward();
    HapticFeedback.mediumImpact();

    // Add minimum hold duration to prevent accidental triggers
    _holdTimer = Timer(_minHoldDuration, () {
      if (_isTouchActive) {
        print('🎤 Talk button held long enough - starting talk');
        _isTalkingStarted = true;
        _ignoreCancelEvents = true; // Ignore cancel events once talking starts
        widget.onTalkStart();
      }
    });
  }

  void _handlePointerUp(PointerUpEvent details) {
    if (!_isTouchActive) return;

    _holdTimer?.cancel();
    _isTouchActive = false;
    _ignoreCancelEvents = false; // Reset cancel ignore flag
    _scaleController.reverse();

    if (_isTalkingStarted) {
      print('🎤 Talk button released - stopping talk');
      widget.onTalkEnd();
      _isTalkingStarted = false;
    } else {
      print('🎤 Talk button released - no talk started');
    }
  }

  void _handlePointerCancel(PointerCancelEvent details) {
    if (!_isTouchActive) return;

    if (_ignoreCancelEvents && _isTalkingStarted) {
      print(
          '🎤 Talk button pointer cancelled - IGNORING because talking is active');
      // Don't do anything - keep talking active
      return;
    }

    print(
        '🎤 Talk button pointer cancelled - but continuing to hold if talking started');

    // Don't cancel the talking state immediately on pointer cancel
    // Only cancel the visual feedback
    _holdTimer?.cancel();
    _isTouchActive = false;
    _scaleController.reverse();

    // Don't stop talking on pointer cancel - let the user continue holding
    // The talking will only stop when they actually release (onPointerUp)
  }

  bool _canUseMicrophone() {
    if (widget.userRole == null)
      return true; // Default behavior for backward compatibility
    return widget.userRole != UserRole.inspector;
  }

  String _getMicrophoneStatusText() {
    if (widget.userRole == null) return 'Hold to talk';

    switch (widget.userRole!) {
      case UserRole.pilot1:
      case UserRole.pilot2:
      case UserRole.tower:
        return 'Hold to talk';
      case UserRole.inspector:
        return 'Microphone disabled (Inspector role)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUseMic = _canUseMicrophone();
    final effectiveEnabled = widget.enabled && canUseMic;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: _getMicrophoneStatusText(),
          child: Listener(
            onPointerDown: (details) => _handlePointerDown(details),
            onPointerUp: (details) => _handlePointerUp(details),
            onPointerCancel: (details) => _handlePointerCancel(details),
            child: AnimatedBuilder(
              animation: Listenable.merge([_pulseAnimation, _scaleAnimation]),
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: !effectiveEnabled
                            ? [
                                Colors.grey.shade700,
                                Colors.grey.shade800,
                                Colors.grey.shade900,
                              ]
                            : widget.isTalking
                                ? [
                                    AppTheme.secondaryColor,
                                    AppTheme.secondaryDarkColor,
                                    AppTheme.primaryColor,
                                  ]
                                : [
                                    AppTheme.primaryColor,
                                    AppTheme.primaryDarkColor,
                                    AppTheme.primaryDarkColor,
                                  ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.isTalking
                              ? AppTheme.secondaryColor.withOpacity(0.3)
                              : AppTheme.primaryColor.withOpacity(0.3),
                          blurRadius: widget.isTalking ? 20 : 10,
                          spreadRadius: widget.isTalking ? 2 : 0,
                        ),
                      ],
                    ),
                    child: widget.isTalking
                        ? Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.mic,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                          )
                        : Icon(
                            canUseMic ? Icons.mic_off : Icons.mic_off,
                            color: canUseMic
                                ? Colors.white
                                : Colors.white.withOpacity(0.5),
                            size: 48,
                          ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _getMicrophoneStatusText(),
          style: TextStyle(
            color: canUseMic
                ? Theme.of(context).colorScheme.onSurface.withOpacity(0.7)
                : Colors.red.withOpacity(0.7),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _pulseController.dispose();
    _scaleController.dispose();
    super.dispose();
  }
}
