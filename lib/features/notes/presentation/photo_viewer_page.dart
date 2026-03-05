import "dart:io";

import "package:flutter/material.dart";
import "package:photo_view/photo_view.dart";

class PhotoViewerPage extends StatelessWidget {
  const PhotoViewerPage({
    super.key,
    required this.filePath,
    this.caption,
  });

  final String filePath;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);
    if (!file.existsSync()) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: Text("Файл не найден", style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PhotoView(
              imageProvider: FileImage(file),
              initialScale: PhotoViewComputedScale.contained,
              minScale: PhotoViewComputedScale.contained * 0.5,
              maxScale: PhotoViewComputedScale.contained * 3.0,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Material(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(24),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 24),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: "Закрыть",
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (caption != null && caption!.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    32,
                    16,
                    16 + MediaQuery.paddingOf(context).bottom,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                  child: Text(
                    caption!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
