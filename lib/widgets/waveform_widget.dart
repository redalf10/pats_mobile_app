import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../config/theme_config.dart';

class WaveformWidget extends StatefulWidget {
  final bool isTalking;
  
  const WaveformWidget({super.key, required this.isTalking});

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final List<double> _waveHeights = List.generate(20, (index) => 0.1);
  Timer? _animationTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(WaveformWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTalking != oldWidget.isTalking) {
      if (widget.isTalking) {
        _startWaveAnimation();
        _pulseController.repeat(reverse: true);
      } else {
        _stopWaveAnimation();
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  void _startWaveAnimation() {
    _animationTimer?.cancel();
    _animationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted && widget.isTalking) {
        setState(() {
          for (int i = 0; i < _waveHeights.length; i++) {
            // Create more dynamic wave patterns when speaking
            if (i % 3 == 0) {
              // Every third bar gets higher amplitude
              _waveHeights[i] = Random().nextDouble() * 0.9 + 0.3;
            } else {
              // Other bars get moderate amplitude
              _waveHeights[i] = Random().nextDouble() * 0.6 + 0.2;
            }
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _stopWaveAnimation() {
    _animationTimer?.cancel();
    if (mounted) {
      setState(() {
        // Reset waves to minimal height when not talking
        for (int i = 0; i < _waveHeights.length; i++) {
          _waveHeights[i] = 0.1;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isTalking ? _pulseAnimation.value : 1.0,
          child: Container(
            height: 80,
            margin: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _waveHeights.asMap().entries.map((entry) {
                final isActive = widget.isTalking && entry.value > 0.3;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 3,
                  height: entry.value * 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: isActive
                          ? [
                              AppTheme.secondaryColor.withOpacity(0.9),
                              AppTheme.secondaryColor.withOpacity(0.4),
                            ]
                          : [
                              AppTheme.secondaryColor.withOpacity(0.3),
                              AppTheme.secondaryColor.withOpacity(0.1),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: AppTheme.secondaryColor.withOpacity(0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    _animationTimer?.cancel();
    super.dispose();
  }
}
