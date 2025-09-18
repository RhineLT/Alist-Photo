import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';
import '../services/alist_api_client.dart';
import '../services/media_cache_manager.dart';
import '../services/file_download_service.dart';
import '../services/media_type_helper.dart';
import '../services/log_service.dart';

class PhotoViewerPage extends StatefulWidget {
  final AlistApiClient apiClient;
  final List<AlistFile> files;
  final int initialIndex;
  
  const PhotoViewerPage({
    super.key,
    required this.apiClient,
    required this.files,
    required this.initialIndex,
  });
  
  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showAppBar = true;
  
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  
  void _toggleAppBar() {
    setState(() {
      _showAppBar = !_showAppBar;
    });
  }
  
  Future<void> _downloadCurrentImage() async {
    try {
      final file = widget.files[_currentIndex];
      final downloadUrl = await widget.apiClient.getDownloadUrl(file);
      
      await FileDownloadService.instance.downloadFile(
        url: downloadUrl,
        fileName: file.name,
        onProgress: (received, total) {
          LogService.instance.debug('Download progress: ${((received / total) * 100).toStringAsFixed(1)}%', 'PhotoViewer');
        },
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${file.name} 下载完成')),
        );
      }
    } catch (e) {
      LogService.instance.error('Download failed: $e', 'PhotoViewer');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }
  
  // 不再返回网络URL，交由缓存管理器获取/下载本地文件
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showAppBar
      ? AppBar(
              backgroundColor: Colors.black.withAlpha((0.7 * 255).round()),
              foregroundColor: Colors.white,
              title: Text(
                '${_currentIndex + 1} / ${widget.files.length}',
                style: const TextStyle(color: Colors.white),
              ),
              centerTitle: true,
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: _downloadCurrentImage,
                  tooltip: '下载到本地',
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            scrollPhysics: const BouncingScrollPhysics(),
            builder: (BuildContext context, int index) {
              final file = widget.files[index];
              
              return PhotoViewGalleryPageOptions.customChild(
                child: _LocalCachedImage(apiClient: widget.apiClient, file: file),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained * 0.5,
                maxScale: PhotoViewComputedScale.covered * 3.0,
                heroAttributes: PhotoViewHeroAttributes(
                  tag: 'photo_${file.name}_$index',
                ),
              );
            },
            itemCount: widget.files.length,
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
            pageController: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            backgroundDecoration: const BoxDecoration(
              color: Colors.black,
            ),
          ),
          // 点击区域来切换AppBar显示
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleAppBar,
              behavior: HitTestBehavior.translucent,
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
                      Colors.black.withAlpha((0.7 * 255).round()),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.files[_currentIndex].name,
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
                            widget.files[_currentIndex].formattedSize,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            widget.files[_currentIndex].modified
                                .toString()
                                .split('.')[0],
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // 侧边导航指示器
          if (widget.files.length > 1 && _showAppBar)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  width: 4,
                  height: MediaQuery.of(context).size.height * 0.3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: Colors.white24,
                  ),
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 200),
                        top: (_currentIndex / widget.files.length) * 
                            (MediaQuery.of(context).size.height * 0.3 - 20),
                        child: Container(
                          width: 4,
                          height: 20,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: Colors.white,
                          ),
                        ),
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

class _LocalCachedImage extends StatefulWidget {
  final AlistApiClient apiClient;
  final AlistFile file;
  const _LocalCachedImage({required this.apiClient, required this.file});

  @override
  State<_LocalCachedImage> createState() => _LocalCachedImageState();
}

class _LocalCachedImageState extends State<_LocalCachedImage> {
  File? _localFile;
  bool _loading = true;
  String? _error;
  LocalDynamicInfo? _dynamicInfo;
  VideoPlayerController? _videoController;
  bool _isVideoReady = false;
  bool _isPressing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 先查本地 original，否则下载
      final f = await MediaCacheManager.instance.getOrFetchOriginal(widget.apiClient, widget.file);
      if (mounted) {
        setState(() {
          _localFile = f;
          _loading = false;
        });
      }
      if (f != null && await f.exists()) {
        // 本地动态检测
        final info = await MediaType.detectLocalDynamic(f);
        LogService.instance.info('Dynamic detection result', 'PhotoViewer', {
          'file': f.path,
          'is_dynamic': info.isDynamic,
          'vendor': info.vendor.name,
          'has_sidecar': info.videoFile != null,
          'embedded': info.isEmbeddedMotion,
        });
        if (mounted) {
          setState(() {
            _dynamicInfo = info;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _startPlayIfAvailable() async {
    final info = _dynamicInfo;
    if (info == null || info.videoFile == null) {
      // 无侧车视频，不播放，仅记录
      LogService.instance.debug('Long-press ignored: no sidecar video', 'PhotoViewer', {
        'file': _localFile?.path,
      });
      return;
    }
    // 避免重复初始化
    if (_videoController == null) {
      try {
        LogService.instance.info('Initializing sidecar video for long-press', 'PhotoViewer', {
          'video': info.videoFile!.path,
        });
        final c = VideoPlayerController.file(info.videoFile!);
        await c.initialize();
        await c.setLooping(true);
        _videoController = c;
        if (!mounted) return;
        setState(() {
          _isVideoReady = true;
        });
      } catch (e) {
        LogService.instance.error('Video init failed: $e', 'PhotoViewer');
        return;
      }
    }
    try {
      await _videoController!.seekTo(Duration.zero);
      await _videoController!.play();
      if (mounted) {
        setState(() {
          _isPressing = true;
        });
      }
      LogService.instance.info('Long-press playback started', 'PhotoViewer');
    } catch (e) {
      LogService.instance.error('Start play failed: $e', 'PhotoViewer');
    }
  }

  Future<void> _stopPlay() async {
    try {
      if (_videoController != null) {
        await _videoController!.pause();
        await _videoController!.seekTo(Duration.zero);
      }
      if (mounted) {
        setState(() {
          _isPressing = false;
        });
      }
      LogService.instance.info('Long-press playback stopped', 'PhotoViewer');
    } catch (e) {
      LogService.instance.warning('Stop play warning: $e', 'PhotoViewer');
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    if (_error != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.broken_image, size: 64, color: Colors.white54),
              SizedBox(height: 16),
              Text('加载失败', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    }
    if (_localFile != null && _localFile!.existsSync()) {
      // 默认显示静态图，支持长按播放
      final child = Stack(
        fit: StackFit.passthrough,
        children: [
          Image.file(_localFile!, fit: BoxFit.contain),
          if (_isPressing && _isVideoReady && _videoController != null && _videoController!.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio == 0
                    ? 1.0
                    : _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
            ),
          // LIVE 标识
          if (_dynamicInfo?.isDynamic == true)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.motion_photos_on, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (_) => _startPlayIfAvailable(),
        onLongPressEnd: (_) => _stopPlay(),
        child: child,
      );
    }
    return Container(color: Colors.black);
  }
}