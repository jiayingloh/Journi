import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/upload_provider.dart';

class GlobalUploadIndicator extends StatelessWidget {
  const GlobalUploadIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UploadProvider>(
      builder: (context, provider, child) {
        if (!provider.isUploading) return const SizedBox.shrink();

        return Positioned(
          bottom: 100, // Above typical FAB/Nav bar
          left: 16,
          right: 16,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: Colors.black87,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Row(
                     children: [
                       const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                       const SizedBox(width: 16),
                       Expanded(
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text(
                               provider.statusMessage,
                               style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                             ),
                             const SizedBox(height: 4),
                             const Text(
                               'Do not force close the app.',
                               style: TextStyle(color: Colors.white70, fontSize: 12),
                             ),
                           ],
                         ),
                       ),
                     ],
                   ),
                   const SizedBox(height: 8),
                   LinearProgressIndicator(value: provider.progress, backgroundColor: Colors.white10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
