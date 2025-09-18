import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/alist_api_client.dart';
import '../services/log_service.dart';
import '../services/file_download_service.dart';

class LivePhotoViewerPage extends StatefulWidget {
  final AlistApiClient apiClient;
  final AlistFile file;
  final AlistFile? videoFile; // 对应的视频文件（如果有）
  
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
  bool _showAppBar = true;
  bool _isPlayingVideo = false;
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  
  @override
  void initState() {
    super.initState();
    if (widget.videoFile != null) {
      _initializeVideo();
    }
  }
  
  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }
  
  Future<void> _initializeVideo() async {
    if (widget.videoFile == null) return;
    
    try {
      final videoUrl = await widget.apiClient.getDownloadUrl(widget.videoFile!);
      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await _videoController!.initialize();
      
      // 设置循环播放
      _videoController!.setLooping(true);
      
      setState(() {
        _videoInitialized = true;
      });
    } catch (e) {
      LogService.instance.error('Failed to initialize Live Photo video: $e', 'LivePhotoViewer');
    }
  }
  
  void _toggleAppBar() {
    setState(() {
      _showAppBar = !_showAppBar;
    });
  }
  
  void _togglePlayback() {
    if (_videoController == null || !_videoInitialized) return;
    
    setState(() {
      if (_isPlayingVideo) {
        _videoController!.pause();
        _isPlayingVideo = false;
      } else {
        _videoController!.play();
        _isPlayingVideo = true;
      }
    });
  }
  
  Future<void> _downloadFile() async {
    try {
      final downloadUrl = await widget.apiClient.getDownloadUrl(widget.file);
      
      await FileDownloadService.instance.downloadFile(
          url: downloadUrl,
          fileName: file.name,
          onProgress: (received, total) {
            LogService.instance.debug('Download progress: ${((received / total) * 100).toStringAsFixed(1)}%', 'LivePhotoViewer');
          },
        );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.file.name} 下载完成')),
        );
      }
    } catch (e) {
      LogService.instance.error('Download failed: $e', 'LivePhotoViewer');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }
  
  Future<String> _getImageUrl() async {
    if (widget.file.rawUrl?.isNotEmpty == true) {
      return widget.apiClient.getFullUrl(widget.file.rawUrl!);
    } else {
      return await widget.apiClient.getDownloadUrl(widget.file);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showAppBar
          ? AppBar(
              backgroundColor: Colors.black.withOpacity(0.7),
              foregroundColor: Colors.white,
              title: const Text(
                'Live Photo',
                style: TextStyle(color: Colors.white),
              ),
              centerTitle: true,
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: _downloadFile,
                  tooltip: '下载到本地',
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          // 背景图片或视频
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleAppBar,
              onLongPress: widget.videoFile != null ? _togglePlayback : null,
              child: _isPlayingVideo && _videoController != null && _videoInitialized
                  ? VideoPlayer(_videoController!)
                  : FutureBuilder<String>(
                      future: _getImageUrl(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return PhotoView(
                            imageProvider: CachedNetworkImageProvider(snapshot.data!),
                            initialScale: PhotoViewComputedScale.contained,
                            minScale: PhotoViewComputedScale.contained * 0.5,
                            maxScale: PhotoViewComputedScale.covered * 3.0,
                            heroAttributes: PhotoViewHeroAttributes(
                              tag: 'live_photo_${widget.file.name}',
                            ),
                            loadingBuilder: (context, event) => Container(
                              color: Colors.black,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                    const SizedBox(height: 16),
                                    if (event != null)
                                      Text(
                                        '${((event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1)) * 100).toStringAsFixed(0)}%',
                                        style: const TextStyle(color: Colors.white54),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: Colors.black,
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: Colors.white70,
                                      size: 48,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      '无法加载Live Photo',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        } else if (snapshot.hasError) {
                          return Container(
                            color: Colors.black,
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.white70,
                                    size: 48,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    '加载失败',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        } else {
                          return Container(
                            color: Colors.black,
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          );
                        }
                      },
                    ),
            ),
          ),
          
          // Live Photo 指示器
          if (widget.videoFile != null && _showAppBar)
            Positioned(
              top: kToolbarHeight + MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.motion_photos_on,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isPlayingVideo ? 'LIVE' : 'PHOTO',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // 播放控制提示
          if (widget.videoFile != null && _showAppBar && !_isPlayingVideo)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '长按播放Live Photo',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          
          // 底部信息栏
          if (_showAppBar)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.file.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            widget.file.formattedSize,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            widget.file.modified
                                .toString()
                                .split('.')[0],
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          if (widget.videoFile != null) ...[
                            const SizedBox(width: 16),
                            const Icon(
                              Icons.motion_photos_on,
                              color: Colors.white70,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Live Photo',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}