import 'dart:async';

import 'package:flutter/material.dart';

class LiveElapsed extends StatefulWidget {
  const LiveElapsed({required this.since, this.style, super.key});

  final DateTime since;
  final TextStyle? style;

  @override
  State<LiveElapsed> createState() => _LiveElapsedState();
}

class _LiveElapsedState extends State<LiveElapsed> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(formatElapsedSince(widget.since), style: widget.style);
  }
}

String formatElapsedSince(DateTime since) {
  final elapsed = DateTime.now().difference(since.toLocal());
  final seconds = elapsed.inSeconds.clamp(0, 1 << 31);
  String two(int value) => value.toString().padLeft(2, '0');

  if (seconds < 3600) {
    return '${two(seconds ~/ 60)}:${two(seconds % 60)}';
  }

  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  return '$hours:${two(minutes)}:${two(seconds % 60)}';
}
