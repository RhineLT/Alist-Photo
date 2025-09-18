import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/alist_api_client.dart';
import '../services/media_cache_manager.dart';
import '../services/file_download_service.dart';
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
  
  Future<String> _getImageUrl(AlistFile file) async {
    // 优先使用原始URL，如果没有则通过API获取完整的下载URL
    if (file.rawUrl?.isNotEmpty == true) {
      return widget.apiClient.getFullUrl(file.rawUrl!);
    } else {
      // 使用异步方法获取带sign的正确URL
      return await widget.apiClient.getDownloadUrl(file);
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
                child: _AsyncImage(file: file, getImageUrl: _getImageUrl),
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

class _AsyncImage extends StatefulWidget {
  final AlistFile file;
  final Future<String> Function(AlistFile) getImageUrl;

  const _AsyncImage({
    required this.file,
    required this.getImageUrl,
  });

  @override
  State<_AsyncImage> createState() => _AsyncImageState();
}

class _AsyncImageState extends State<_AsyncImage> {
  String? _imageUrl;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImageUrl();
  }

  Future<void> _loadImageUrl() async {
    try {
      final url = await widget.getImageUrl(widget.file);
      if (mounted) {
        setState(() {
          _imageUrl = url;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
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
              const Icon(
                Icons.broken_image,
                size: 64,
                color: Colors.white54,
              ),
              const SizedBox(height: 16),
              Text(
                '加载失败',
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 8),
              Text(
                widget.file.name,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    if (_imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: _imageUrl!,
        fit: BoxFit.contain,
        cacheManager: MediaCacheManager.instance.originalImageCache,
        placeholder: (context, url) => Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(
              color: Colors.white,
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.broken_image,
                  size: 64,
                  color: Colors.white54,
                ),
                const SizedBox(height: 16),
                Text(
                  '图片加载失败',
                  style: const TextStyle(color: Colors.white54),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.file.name,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: const Center(
        child: Text(
          '无法加载图片',
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}