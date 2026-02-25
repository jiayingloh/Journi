import 'package:flutter/material.dart';

class UploadProgress extends StatelessWidget {
  final double progress;
  const UploadProgress({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(value: progress);
  }
}
