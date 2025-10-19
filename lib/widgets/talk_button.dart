import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme_config.dart';

class TalkButton extends StatefulWidget {
  final bool isTalking;
  final VoidCallback onTalkStart;
  final VoidCallback onTalkEnd;
  final bool enabled;

  const TalkButton({
    super.key,
    required this.isTalking,
    required this.onTalkStart,
    required this.onTalkEnd,
    this.enabled = true,
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
      }
    }
  }

  bool _isTouchActive = false;
  Timer? _holdTimer;
  static const Duration _minHoldDuration = Duration(milliseconds: 100);

  void _handleTapDown(TapDownDetails details) {
    if (_isTouchActive || !widget.enabled) {
      print(
          '🎤 Talk button tap ignored: active=$_isTouchActive, enabled=${widget.enabled}');
      return;
    }

    _isTouchActive = true;
    _scaleController.forward();
    HapticFeedback.mediumImpact();

    // Add minimum hold duration to prevent accidental triggers
    _holdTimer = Timer(_minHoldDuration, () {
      if (_isTouchActive) {
        print('🎤 Talk button held long enough - starting talk');
        widget.onTalkStart();
      }
    });
  }

  void _handleTapUp(TapUpDetails details) {
    if (!_isTouchActive) return;

    _holdTimer?.cancel();
    _isTouchActive = false;
    _scaleController.reverse();

    print('🎤 Talk button released - stopping talk');
    widget.onTalkEnd();
  }

  void _handleTapCancel() {
    if (!_isTouchActive) return;

    _holdTimer?.cancel();
    _isTouchActive = false;
    _scaleController.reverse();

    print('🎤 Talk button cancelled - stopping talk');
    widget.onTalkEnd();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
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
                  colors: !widget.enabled
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
                  : const Icon(
                      Icons.mic_off,
                      color: Colors.white,
                      size: 48,
                    ),
            ),
          );
        },
      ),
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
