import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cache              actions: [
                if (widget.videoFile != null)
                  IconButton(
                    icon: Icon(_isPlayingVideo ? Icons.pause : Icons.play_arrow),
                    onPressed: _togglePlayback,
                    tooltip: _isPlayingVideo ? '暂停' : '播放动态照片',
                  ),
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: _downloadFile,
                  tooltip: '下载照片',
                ),
                if (widget.videoFile != null)
                  IconButton(
                    icon: const Icon(Icons.video_file),
                    onPressed: _downloadVideoFile,
                    tooltip: '下载视频文件',
                  ),
              ],rk_image.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/alist_api_client.dart';
import '../services/log_service.dart';
import '../services/file_download_service.dart';
import '../services/media_cache_manager.dart';

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
  bool _videoError = false;
  String? _errorMessage;
  
  // Live Photo 类型检测
  LivePhotoType _livePhotoType = LivePhotoType.unknown;
  
  @override
  void initState() {
    super.initState();
    _detectLivePhotoType();
    if (widget.videoFile != null) {
      _initializeVideo();
    }
    
    // 保持屏幕常亮
    WakelockPlus.enable();
  }
  
  @override
  void dispose() {
    _videoController?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }
  
  void _detectLivePhotoType() {
    final fileName = widget.file.name.toLowerCase();
    final videoFileName = widget.videoFile?.name.toLowerCase() ?? '';
    
    if (fileName.contains('heic') || fileName.contains('heif')) {
      _livePhotoType = LivePhotoType.apple;
    } else if (videoFileName.contains('mp4') && fileName.contains('jpg')) {
      _livePhotoType = LivePhotoType.xiaomi;
    } else {
      _livePhotoType = LivePhotoType.generic;
    }
    
    LogService.instance.info('Detected Live Photo type: $_livePhotoType', 'LivePhotoViewer');
  }
  
  Future<void> _initializeVideo() async {
    if (widget.videoFile == null) return;
    
    try {
      LogService.instance.info('Initializing Live Photo video: ${widget.videoFile!.name}', 'LivePhotoViewer');
      
      final videoUrl = await widget.apiClient.getDownloadUrl(widget.videoFile!);
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        httpHeaders: {
          'User-Agent': 'Alist-Photo-Flutter-App',
        },
      );
      
      await _videoController!.initialize();
      
      // 根据 Live Photo 类型设置不同的播放行为
      switch (_livePhotoType) {
        case LivePhotoType.apple:
          // 苹果 Live Photo 通常短时间播放
          _videoController!.setLooping(false);
          break;
        case LivePhotoType.xiaomi:
          // 小米动态照片通常循环播放
          _videoController!.setLooping(true);
          break;
        default:
          _videoController!.setLooping(true);
          break;
      }
      
      // 监听播放完成
      _videoController!.addListener(_videoListener);
      
      setState(() {
        _videoInitialized = true;
        _videoError = false;
        _errorMessage = null;
      });
      
      LogService.instance.info('Live Photo video initialized successfully', 'LivePhotoViewer');
    } catch (e) {
      LogService.instance.error('Failed to initialize Live Photo video: $e', 'LivePhotoViewer');
      setState(() {
        _videoError = true;
        _errorMessage = e.toString();
      });
    }
  }
  
  void _videoListener() {
    if (_videoController == null) return;
    
    // 如果是苹果 Live Photo 且播放完成，自动停止
    if (_livePhotoType == LivePhotoType.apple && 
        _videoController!.value.position >= _videoController!.value.duration) {
      setState(() {
        _isPlayingVideo = false;
      });
    }
  }
  
  void _toggleAppBar() {
    setState(() {
      _showAppBar = !_showAppBar;
    });
  }
  
  void _togglePlayback() {
    if (_videoController == null || !_videoInitialized || _videoError) return;
    
    setState(() {
      if (_isPlayingVideo) {
        _videoController!.pause();
        _isPlayingVideo = false;
        
        // 对于苹果 Live Photo，暂停时重置到开始位置
        if (_livePhotoType == LivePhotoType.apple) {
          _videoController!.seekTo(Duration.zero);
        }
      } else {
        // 对于苹果 Live Photo，从头开始播放
        if (_livePhotoType == LivePhotoType.apple) {
          _videoController!.seekTo(Duration.zero);
        }
        
        _videoController!.play();
        _isPlayingVideo = true;
      }
    });
    
    // 触觉反馈
    HapticFeedback.lightImpact();
  }
  
  Future<void> _downloadVideoFile() async {
    if (widget.videoFile == null) return;
    
    try {
      final downloadUrl = await widget.apiClient.getDownloadUrl(widget.videoFile!);
      
      await FileDownloadService.instance.downloadFile(
        url: downloadUrl,
        fileName: widget.videoFile!.name,
        onProgress: (received, total) {
          LogService.instance.debug('Video download progress: ${((received / total) * 100).toStringAsFixed(1)}%', 'LivePhotoViewer');
        },
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.videoFile!.name} 下载完成')),
        );
      }
    } catch (e) {
      LogService.instance.error('Video download failed: $e', 'LivePhotoViewer');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('视频下载失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _downloadFile() async {
    try {
      final downloadUrl = await widget.apiClient.getDownloadUrl(widget.file);
      
      await FileDownloadService.instance.downloadFile(
          url: downloadUrl,
          fileName: widget.file.name,
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
  
  Widget _buildPhotoContent() {
    if (_videoError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                '动态照片加载失败',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (_isPlayingVideo && _videoController != null && _videoInitialized) {
      return Container(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio.isNaN 
                ? 16 / 9 
                : _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
        ),
      );
    }

    return FutureBuilder<String>(
      future: _getImageUrl(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return PhotoView(
            imageProvider: CachedNetworkImageProvider(
              snapshot.data!,
              cacheManager: MediaCacheManager.instance.originalCache,
            ),
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
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                    const SizedBox(height: 16),
                    if (event != null)
                      Text(
                        '${((event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1)) * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Colors.white70),
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
                      color: Colors.red,
                      size: 48,
                    ),
                    SizedBox(height: 16),
                    Text(
                      '无法加载照片',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            backgroundDecoration: const BoxDecoration(
              color: Colors.black,
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
                    color: Colors.red,
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
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),
          );
        }
      },
    );
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
            child: Stack(
              children: [
                // 主要内容区域
                GestureDetector(
                  onTap: _toggleAppBar,
                  onLongPress: widget.videoFile != null ? _togglePlayback : null,
                  child: _buildPhotoContent(),
                ),
                
                // Live Photo 指示器
                if (widget.videoFile != null)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: AnimatedOpacity(
                      opacity: _showAppBar ? 1.0 : 0.3,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isPlayingVideo ? Icons.motion_photos_on : Icons.motion_photos_paused,
                              color: _isPlayingVideo ? Colors.blue : Colors.white70,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: _isPlayingVideo ? Colors.blue : Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                
                // 播放/暂停按钮覆盖层（仅在显示 UI 时）
                if (widget.videoFile != null && _showAppBar && !_isPlayingVideo)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black38,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: _togglePlayback,
                          icon: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ),
                
                // 用户提示（长按播放）
                if (widget.videoFile != null && _showAppBar && !_videoError)
                  Positioned(
                    bottom: 100,
                    left: 16,
                    right: 16,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _livePhotoType == LivePhotoType.apple 
                              ? '长按查看 Live Photo' 
                              : '长按播放动态照片',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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

// Live Photo 类型枚举
enum LivePhotoType {
  apple,     // 苹果 Live Photo (HEIC/HEIF + MOV)
  xiaomi,    // 小米动态照片 (JPG + MP4)
  generic,   // 通用格式
  unknown    // 未知类型
}