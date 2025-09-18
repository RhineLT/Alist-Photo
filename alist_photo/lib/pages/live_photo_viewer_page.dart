import 'package:flutter/material.dart';
import '../services/alist_api_client.dart';

class LivePhotoViewerPage extends StatefulWidget {
  final AlistApiClient apiClient;
  final AlistFile file;
  final AlistFile? videoFile;
  
  const LivePhotoViewerPage({
    super.key,
    required this.apiClient,
    required this.file,
    this.videoFile,
  });
  
  @override
  State<LivePhotoViewerPage> createState() => _LivePhotoViewerPageState();
}

class _LivePhotoViewerPageState extends State<LivePhotoViewerPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name),
      ),
      body: const Center(
        child: Text('Live Photo Viewer - Coming Soon'),
      ),
    );
  }
}
