import 'package:flutter/material.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
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
  VideoPlayerController? _videoController;
  bool _isVideoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoFile != null) {
      final file = File(widget.videoFile!.path); // AlistFile 转 File
      _videoController = VideoPlayerController.file(file)
        ..initialize().then((_) {
          setState(() {
            _isVideoReady = true;
          });
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name),
      ),
      body: Center(
        child: widget.videoFile != null && _isVideoReady && _videoController != null && _videoController!.value.isInitialized
            ? AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio == 0 ? 1.0 : _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              )
            : FutureBuilder<String>(
                future: widget.apiClient.getDownloadUrl(widget.file),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                    return Image.network(
                      snapshot.data!,
                      fit: BoxFit.contain,
                    );
                  } else {
                    return const CircularProgressIndicator();
                  }
                },
              ),
      ),
    );
  }
}
