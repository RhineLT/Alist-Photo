import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/alist_api_client.dart';
import '../services/log_service.dart';
import '../services/file_download_service.dart';

class VideoViewerPage extends StatefulWidget {
  final AlistApiClient apiClient;
  final List<AlistFile> files;
  final int initialIndex;
  
  const VideoViewerPage({
    super.key,
    required this.apiClient,
    required this.files,
    required this.initialIndex,
  });
  
  @override
  State<VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<VideoViewerPage> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showAppBar = true;
  bool _isFullScreen = false;
  
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    
    // 保持屏幕常亮
    WakelockPlus.enable();
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    // 恢复屏幕设置
    WakelockPlus.disable();
    super.dispose();
  }
  
  void _toggleAppBar() {
    setState(() {
      _showAppBar = !_showAppBar;
    });
  }
  
  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
    
    if (_isFullScreen) {
      // 进入全屏模式
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      // 退出全屏模式
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }
  
  Future<void> _downloadFile() async {
    try {
      final file = widget.files[_currentIndex];
      final downloadUrl = await widget.apiClient.getDownloadUrl(file);
      
      await FileDownloadService.instance.downloadFile(
        url: downloadUrl,
        fileName: file.name,
        onProgress: (received, total) {
          LogService.instance.debug('Download progress: ${((received / total) * 100).toStringAsFixed(1)}%', 'VideoViewer');
        },
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${file.name} 下载完成')),
        );
      }
    } catch (e) {
      LogService.instance.error('Download failed: $e', 'VideoViewer');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
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
                  icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
                  onPressed: _toggleFullScreen,
                  tooltip: _isFullScreen ? '退出全屏' : '全屏播放',
                ),
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: _downloadFile,
                  tooltip: '下载到本地',
                ),
              ],
            )
          : null,
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemCount: widget.files.length,
        itemBuilder: (context, index) {
          final file = widget.files[index];
          return GestureDetector(
            onTap: _toggleAppBar,
            child: VideoPlayerWidget(
              apiClient: widget.apiClient,
              file: file,
              key: ValueKey(file.name), // 使用 key 确保每个视频独立
            ),
          );
        },
      ),
      bottomNavigationBar: _showAppBar
          ? Container(
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
            )
          : null,
    );
  }
}

class VideoPlayerWidget extends StatefulWidget {
  final AlistApiClient apiClient;
  final AlistFile file;
  
  const VideoPlayerWidget({
    super.key,
    required this.apiClient,
    required this.file,
  });
  
  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitializing = true;
  String? _errorMessage;
  bool _hasError = false;
  
  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }
  
  @override
  void dispose() {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    try {
      setState(() {
        _isInitializing = true;
        _hasError = false;
        _errorMessage = null;
      });

      LogService.instance.info('Initializing video: ${widget.file.name}', 'VideoPlayer');
      
      final videoUrl = await widget.apiClient.getDownloadUrl(widget.file);
      LogService.instance.debug('Video URL obtained: $videoUrl', 'VideoPlayer');
      
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        httpHeaders: {
          'User-Agent': 'Alist-Photo-Flutter-App',
        },
      );
      
      await _videoPlayerController!.initialize();
      
      if (_videoPlayerController!.value.hasError) {
        throw Exception('Video player initialization error');
      }
      
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        showControlsOnInitialize: true,
        showControls: true,
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: Icon(
              Icons.video_library,
              size: 64,
              color: Colors.white54,
            ),
          ),
        ),
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.blue,
          handleColor: Colors.blue,
          backgroundColor: Colors.grey.shade800,
          bufferedColor: Colors.white38,
        ),
        cupertinoProgressColors: ChewieProgressColors(
          playedColor: Colors.blue,
          handleColor: Colors.blue,
          backgroundColor: Colors.grey.shade800,
          bufferedColor: Colors.white38,
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
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
                  '视频播放出错',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _retryInitialization,
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        },
      );
      
      LogService.instance.info('Video initialized successfully: ${widget.file.name}', 'VideoPlayer');
      
      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      LogService.instance.error('Failed to initialize video: $e', 'VideoPlayer', {
        'file_name': widget.file.name,
        'error': e.toString(),
      });
      
      setState(() {
        _isInitializing = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }
  
  Future<void> _retryInitialization() async {
    await _initializeVideo();
  }  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.blue),
              SizedBox(height: 16),
              Text(
                '正在加载视频...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    
    if (_hasError || _errorMessage != null) {
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
                '无法播放视频',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
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
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _retryInitialization,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    
    if (_chewieController != null && _videoPlayerController != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: _videoPlayerController!.value.aspectRatio.isNaN 
                ? 16 / 9 
                : _videoPlayerController!.value.aspectRatio,
            child: Chewie(controller: _chewieController!),
          ),
        ),
      );
    }
    
    return Container(
      color: Colors.black,
      child: const Center(
        child: Text(
          '视频初始化中...',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}