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
  // 动态播放相关（页面层，避免与 PhotoView 手势冲突）
  LocalDynamicInfo? _currentDynamic;
  VideoPlayerController? _videoController;
  bool _isPressing = false;
  bool _isVideoReady = false;
  String? _currentVideoPath;
  
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    // 预备当前页的动态信息
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareDynamicForIndex(_currentIndex);
    });
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    try { _videoController?.dispose(); } catch (_) {}
    super.dispose();
  }
  
  void _toggleAppBar() {
    setState(() {
      _showAppBar = !_showAppBar;
    });
  }

  Future<void> _prepareDynamicForIndex(int index) async {
    try {
      final file = widget.files[index];
      final localImage = await MediaCacheManager.instance.getOrFetchOriginal(widget.apiClient, file);
      LocalDynamicInfo? result;

      if (localImage != null && await localImage.exists()) {
        // 先根据同目录文件列表找侧车视频
        final sidecar = _findSidecarFromList(file);
        if (sidecar != null) {
          final localVideo = await MediaCacheManager.instance.getOrFetchVideo(widget.apiClient, sidecar);
          if (localVideo != null && await localVideo.exists()) {
            // 根据扩展名大致判断供应商
            final ext = sidecar.name.toLowerCase().split('.').last;
            final vendor = (ext == 'mov') ? DynamicVendor.apple : DynamicVendor.xiaomi;
            result = LocalDynamicInfo(
              isDynamic: true,
              vendor: vendor,
              imageFile: localImage,
              videoFile: localVideo,
            );
          }
        }
        // 若未找到侧车，回退到本地嵌入式检查
        if (result == null) {
          final info = await MediaType.detectLocalDynamic(localImage);
          // 若是嵌入式动态图，则尝试抽取视频
          if (info.isEmbeddedMotion) {
            final extracted = await MediaType.extractEmbeddedMicroVideo(localImage);
            if (extracted != null && await extracted.exists()) {
              result = LocalDynamicInfo(
                isDynamic: true,
                vendor: DynamicVendor.google,
                imageFile: localImage,
                videoFile: extracted,
                isEmbeddedMotion: true,
              );
            } else {
              result = info; // 仅保留标识
            }
          } else {
            result = info;
          }
        }
      }

      LogService.instance.info('Dynamic prepared for index $index', 'PhotoViewer', {
        'has_result': result != null,
        'has_sidecar': result?.videoFile != null,
        'embedded': result?.isEmbeddedMotion,
        'vendor': result?.vendor.name,
      });

      if (!mounted) return;
      setState(() {
        _currentDynamic = result;
      });
    } catch (e) {
      LogService.instance.warning('Prepare dynamic failed: $e', 'PhotoViewer');
    }
  }

  AlistFile? _findSidecarFromList(AlistFile baseFile) {
    String baseNameNoExt(String name) {
      final parts = name.split('.');
      if (parts.length <= 1) return name;
      return parts.sublist(0, parts.length - 1).join('.');
    }
    final base = baseNameNoExt(baseFile.name).toLowerCase();
    final sameDir = widget.files.where((f) => !f.isDir).toList();
    // 优先匹配完全同名不同扩展
    final exts = ['mov', 'mp4', 'mp4v'];
    for (final f in sameDir) {
      final name = f.name.toLowerCase();
      final parts = name.split('.');
      if (parts.length < 2) continue;
      final stem = parts.sublist(0, parts.length - 1).join('.');
      final ext = parts.last;
      if (stem == base && exts.contains(ext)) {
        return f;
      }
    }
    // 次选：常见后缀 _VIDEO
    final alt = '${base}_video.mp4';
    for (final f in sameDir) {
      if (f.name.toLowerCase() == alt) return f;
    }
    return null;
  }

  Future<void> _startPressPlay() async {
    final info = _currentDynamic;
    if (info == null || info.videoFile == null) {
      LogService.instance.debug('Playback ignored: no sidecar for current', 'PhotoViewer');
      return;
    }
    try {
      // 若当前 controller 对应不同文件，先释放
      if (_videoController != null && _currentVideoPath != info.videoFile!.path) {
        try { await _videoController!.dispose(); } catch (_) {}
        _videoController = null;
        _isVideoReady = false;
      }
      if (_videoController == null) {
        LogService.instance.info('Initializing video for LIVE playback', 'PhotoViewer', {
          'video': info.videoFile!.path,
        });
        final c = VideoPlayerController.file(info.videoFile!);
        await c.initialize();
        await c.setLooping(true);
        _videoController = c;
        _currentVideoPath = info.videoFile!.path;
        _isVideoReady = true;
      }
      await _videoController!.seekTo(Duration.zero);
      await _videoController!.play();
      if (!mounted) return;
      setState(() {
        _isPressing = true;
      });
      LogService.instance.info('LIVE playback started', 'PhotoViewer');
    } catch (e) {
      LogService.instance.error('Start LIVE playback failed: $e', 'PhotoViewer');
    }
  }

  Future<void> _stopPressPlay() async {
    try {
      if (_videoController != null) {
        await _videoController!.pause();
        await _videoController!.seekTo(Duration.zero);
      }
      if (!mounted) return;
      setState(() { _isPressing = false; });
      LogService.instance.info('LIVE playback stopped', 'PhotoViewer');
    } catch (e) {
      LogService.instance.warning('Stop LIVE playback warning: $e', 'PhotoViewer');
    }
  }

  Future<void> _togglePlayback() async {
    if (_isPressing) {
      await _stopPressPlay();
    } else {
      await _startPressPlay();
    }
  }

  Future<void> _onPageChanged(int index) async {
    setState(() { _currentIndex = index; });
    // 切换页面时停止当前播放
    await _stopPressPlay();
    // 预备新页面的动态信息
    await _prepareDynamicForIndex(index);
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
            onPageChanged: _onPageChanged,
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
          // LIVE 标识（可点击：有侧车视频时）
          if (_currentDynamic?.videoFile != null)
            Positioned(
              top: 12,
              left: 12,
              child: GestureDetector(
                onTap: _togglePlayback,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_isPressing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          // 仅嵌入式（无侧车）时显示不可点击的 LIVE 提示
          if (_currentDynamic?.isDynamic == true && _currentDynamic?.videoFile == null)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.motion_photos_on, color: Colors.white70, size: 16),
                    SizedBox(width: 4),
                    Text('LIVE', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          // 长按播放覆盖层
          if (_isPressing && _isVideoReady && _videoController != null && _videoController!.value.isInitialized)
            Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio == 0
                      ? 1.0
                      : _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 先查本地 original，否则下载
      final f = await MediaCacheManager.instance.getOrFetchOriginal(widget.apiClient, widget.file);
      
      // 确保文件真实存在且可读取
      if (f != null && await f.exists()) {
        final stat = await f.stat();
        if (stat.size > 0) {
          if (mounted) {
            setState(() {
              _localFile = f;
              _loading = false;
            });
          }
          return;
        }
      }
      
      // 如果文件不存在或为空，设置错误状态
      if (mounted) {
        setState(() {
          _error = '图片文件不可用或下载失败';
          _loading = false;
        });
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
            children: [
              const Icon(Icons.broken_image, size: 64, color: Colors.white54),
              const SizedBox(height: 16),
              const Text('加载失败', style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.white30, fontSize: 12)),
            ],
          ),
        ),
      );
    }
    
    if (_localFile != null) {
      // 文件已经在 _load() 中验证过存在性和大小，直接显示
      return Image.file(_localFile!, fit: BoxFit.contain);
    }
    
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, size: 64, color: Colors.white54),
            SizedBox(height: 16),
            Text('图片不可用', style: TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}