import 'package:flutter/material.dart';import 'package:flutter/material.dart';import 'package:flutter/material.dart';import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:photo_view/photo_view.dart';import 'package:flutter/services.dart';

import 'package:video_player/video_player.dart';

import 'package:cached_network_image/cached_network_image.dart';import 'package:photo_view/photo_view.dart';import 'package:flutter/services.dart';import 'package:flutter/services.dart';

import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:video_player/video_player.dart';

import '../services/alist_api_client.dart';

import '../services/log_service.dart';import 'package:cached_network_image/cached_network_image.dart';import 'package:photo_view/photo_view.dart';import 'package:photo_view/photo_view.dart';

import '../services/file_download_service.dart';

import '../services/media_cache_manager.dart';import 'package:wakelock_plus/wakelock_plus.dart';



enum LivePhotoType {import 'package:video_player/video_player.dart';import 'package:video_player/video_player.dart';

  apple,

  xiaomi,import '../services/alist_api_client.dart';

  generic,

  unknownimport '../services/log_service.dart';import 'package:cached_network_image/cached_network_image.dart';import 'package:cached_network_image/cached_network_image.dart';

}

import '../services/file_download_service.dart';

class LivePhotoViewerPage extends StatefulWidget {

  final AlistApiClient apiClient;import '../services/media_cache_manager.dart';import 'package:wakelock_plus/wakelock_plus.dart';import 'package:wakelock_plus/wakelock_plus.dart';

  final AlistFile file;

  final AlistFile? videoFile;

  

  const LivePhotoViewerPage({// Live Photo 类型枚举import '../services/alist_api_client.dart';import '../services/alist_api_client.dart';

    super.key,

    required this.apiClient,enum LivePhotoType {

    required this.file,

    this.videoFile,  apple,     // 苹果 Live Photo (HEIC/HEIF + MOV)import '../services/log_service.dart';import '../services/log_service.dart';

  });

    xiaomi,    // 小米动态照片 (JPG + MP4)

  @override

  State<LivePhotoViewerPage> createState() => _LivePhotoViewerPageState();  generic,   // 通用格式import '../services/file_download_service.dart';import '../services/file_download_service.dart';

}

  unknown    // 未知类型

class _LivePhotoViewerPageState extends State<LivePhotoViewerPage> {

  bool _showAppBar = true;}import '../services/media_cache_manager.dart';import '../services/media_cache_manager.dart';

  bool _isPlayingVideo = false;

  VideoPlayerController? _videoController;

  bool _videoInitialized = false;

  bool _videoError = false;class LivePhotoViewerPage extends StatefulWidget {

  String? _errorMessage;

  LivePhotoType _livePhotoType = LivePhotoType.unknown;  final AlistApiClient apiClient;

  

  @override  final AlistFile file;// Live Photo 类型枚举class LivePhotoViewerPage extends StatefulWidget {

  void initState() {

    super.initState();  final AlistFile? videoFile;

    _detectLivePhotoType();

    if (widget.videoFile != null) {  enum LivePhotoType {  final AlistApiClient apiClient;

      _initializeVideo();

    }  const LivePhotoViewerPage({

    WakelockPlus.enable();

  }    super.key,  apple,     // 苹果 Live Photo (HEIC/HEIF + MOV)  final AlistFile file;

  

  @override    required this.apiClient,

  void dispose() {

    _videoController?.removeListener(_videoListener);    required this.file,  xiaomi,    // 小米动态照片 (JPG + MP4)  final AlistFile? videoFile; // 对应的视频文件（如果有）

    _videoController?.dispose();

    WakelockPlus.disable();    this.videoFile,

    super.dispose();

  }  });  generic,   // 通用格式  

  

  void _detectLivePhotoType() {  

    final fileName = widget.file.name.toLowerCase();

    final videoFileName = widget.videoFile?.name.toLowerCase() ?? '';  @override  unknown    // 未知类型  const LivePhotoViewerPage({

    

    if (fileName.contains('heic') || fileName.contains('heif')) {  State<LivePhotoViewerPage> createState() => _LivePhotoViewerPageState();

      _livePhotoType = LivePhotoType.apple;

    } else if (videoFileName.contains('mp4') && fileName.contains('jpg')) {}}    super.key,

      _livePhotoType = LivePhotoType.xiaomi;

    } else {

      _livePhotoType = LivePhotoType.generic;

    }class _LivePhotoViewerPageState extends State<LivePhotoViewerPage> {    required this.apiClient,

    

    LogService.instance.info('Detected Live Photo type: $_livePhotoType', 'LivePhotoViewer');  bool _showAppBar = true;

  }

    bool _isPlayingVideo = false;class LivePhotoViewerPage extends StatefulWidget {    required this.file,

  Future<void> _initializeVideo() async {

    if (widget.videoFile == null) return;  VideoPlayerController? _videoController;

    

    try {  bool _videoInitialized = false;  final AlistApiClient apiClient;    this.videoFile,

      final videoUrl = await widget.apiClient.getDownloadUrl(widget.videoFile!);

      _videoController = VideoPlayerController.networkUrl(  bool _videoError = false;

        Uri.parse(videoUrl),

        httpHeaders: {  String? _errorMessage;  final AlistFile file;  });

          'User-Agent': 'Alist-Photo-Flutter-App',

        },  LivePhotoType _livePhotoType = LivePhotoType.unknown;

      );

          final AlistFile? videoFile; // 对应的视频文件（如果有）  

      await _videoController!.initialize();

        @override

      switch (_livePhotoType) {

        case LivePhotoType.apple:  void initState() {    @override

          _videoController!.setLooping(false);

          break;    super.initState();

        case LivePhotoType.xiaomi:

          _videoController!.setLooping(true);    _detectLivePhotoType();  const LivePhotoViewerPage({  State<LivePhotoViewerPage> createState() => _LivePhotoViewerPageState();

          break;

        default:    if (widget.videoFile != null) {

          _videoController!.setLooping(true);

          break;      _initializeVideo();    super.key,}

      }

          }

      _videoController!.addListener(_videoListener);

          WakelockPlus.enable();    required this.apiClient,  final AlistApiClient apiClient;

      setState(() {

        _videoInitialized = true;  }

        _videoError = false;

        _errorMessage = null;      required this.file,  final AlistFile file;

      });

        @override

    } catch (e) {

      LogService.instance.error('Failed to initialize Live Photo video: $e', 'LivePhotoViewer');  void dispose() {    this.videoFile,  final AlistFile? videoFile; // 对应的视频文件（如果有）

      setState(() {

        _videoError = true;    _videoController?.removeListener(_videoListener);

        _errorMessage = e.toString();

      });    _videoController?.dispose();  });  

    }

  }    WakelockPlus.disable();

  

  void _videoListener() {    super.dispose();    const LivePhotoViewerPage({

    if (_videoController == null) return;

      }

    if (_livePhotoType == LivePhotoType.apple && 

        _videoController!.value.position >= _videoController!.value.duration) {    @override    super.key,

      setState(() {

        _isPlayingVideo = false;  void _detectLivePhotoType() {

      });

    }    final fileName = widget.file.name.toLowerCase();  State<LivePhotoViewerPage> createState() => _LivePhotoViewerPageState();    required this.apiClient,

  }

      final videoFileName = widget.videoFile?.name.toLowerCase() ?? '';

  void _toggleAppBar() {

    setState(() {    }    required this.file,

      _showAppBar = !_showAppBar;

    });    if (fileName.contains('heic') || fileName.contains('heif')) {

  }

        _livePhotoType = LivePhotoType.apple;    this.videoFile,

  void _togglePlayback() {

    if (_videoController == null || !_videoInitialized || _videoError) return;    } else if (videoFileName.contains('mp4') && fileName.contains('jpg')) {

    

    setState(() {      _livePhotoType = LivePhotoType.xiaomi;class _LivePhotoViewerPageState extends State<LivePhotoViewerPage> {  });

      if (_isPlayingVideo) {

        _videoController!.pause();    } else {

        _isPlayingVideo = false;

              _livePhotoType = LivePhotoType.generic;  bool _showAppBar = true;  

        if (_livePhotoType == LivePhotoType.apple) {

          _videoController!.seekTo(Duration.zero);    }

        }

      } else {      bool _isPlayingVideo = false;  @override

        if (_livePhotoType == LivePhotoType.apple) {

          _videoController!.seekTo(Duration.zero);    LogService.instance.info('Detected Live Photo type: $_livePhotoType', 'LivePhotoViewer');

        }

          }  VideoPlayerController? _videoController;  State<LivePhotoViewerPage> createState() => _LivePhotoViewerPageState();

        _videoController!.play();

        _isPlayingVideo = true;  

      }

    });  Future<void> _initializeVideo() async {  bool _videoInitialized = false;}

    

    HapticFeedback.lightImpact();    if (widget.videoFile == null) return;

  }

        bool _videoError = false;

  Future<void> _downloadFile() async {

    try {    try {

      final downloadUrl = await widget.apiClient.getDownloadUrl(widget.file);

            final videoUrl = await widget.apiClient.getDownloadUrl(widget.videoFile!);  String? _errorMessage;class _LivePhotoViewerPageState extends State<LivePhotoViewerPage> {

      await FileDownloadService.instance.downloadFile(

        url: downloadUrl,      _videoController = VideoPlayerController.networkUrl(

        fileName: widget.file.name,

        onProgress: (received, total) {},        Uri.parse(videoUrl),    bool _showAppBar = true;

      );

              httpHeaders: {

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(          'User-Agent': 'Alist-Photo-Flutter-App',  // Live Photo 类型检测  bool _isPlayingVideo = false;

          SnackBar(content: Text('${widget.file.name} 下载完成')),

        );        },

      }

    } catch (e) {      );  LivePhotoType _livePhotoType = LivePhotoType.unknown;  VideoPlayerController? _videoController;

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(      

          SnackBar(

            content: Text('下载失败: $e'),      await _videoController!.initialize();    bool _videoInitialized = false;

            backgroundColor: Colors.red,

          ),      

        );

      }      switch (_livePhotoType) {  @override  bool _videoError = false;

    }

  }        case LivePhotoType.apple:

  

  Widget _buildContent() {          _videoController!.setLooping(false);  void initState() {  String? _errorMessage;

    if (_videoError) {

      return Container(          break;

        color: Colors.black,

        child: const Center(        case LivePhotoType.xiaomi:    super.initState();  

          child: Column(

            mainAxisAlignment: MainAxisAlignment.center,          _videoController!.setLooping(true);

            children: [

              Icon(Icons.error_outline, color: Colors.red, size: 48),          break;    _detectLivePhotoType();  // Live Photo 类型检测

              SizedBox(height: 16),

              Text('动态照片加载失败', style: TextStyle(color: Colors.white, fontSize: 18)),        default:

            ],

          ),          _videoController!.setLooping(true);    if (widget.videoFile != null) {  LivePhotoType _livePhotoType = LivePhotoType.unknown;

        ),

      );          break;

    }

      }      _initializeVideo();  

    if (_isPlayingVideo && _videoController != null && _videoInitialized) {

      return Container(      

        color: Colors.black,

        child: Center(      _videoController!.addListener(_videoListener);    }  @override

          child: AspectRatio(

            aspectRatio: _videoController!.value.aspectRatio.isNaN       

                ? 16 / 9 

                : _videoController!.value.aspectRatio,      setState(() {      void initState() {

            child: VideoPlayer(_videoController!),

          ),        _videoInitialized = true;

        ),

      );        _videoError = false;    // 保持屏幕常亮    super.initState();

    }

        _errorMessage = null;

    return FutureBuilder<String>(

      future: widget.apiClient.getDownloadUrl(widget.file),      });    WakelockPlus.enable();    _detectLivePhotoType();

      builder: (context, snapshot) {

        if (snapshot.hasData) {      

          return PhotoView(

            imageProvider: CachedNetworkImageProvider(      LogService.instance.info('Live Photo video initialized successfully', 'LivePhotoViewer');  }    if (widget.videoFile != null) {

              snapshot.data!,

              cacheManager: MediaCacheManager.instance.originalCache,    } catch (e) {

            ),

            initialScale: PhotoViewComputedScale.contained,      LogService.instance.error('Failed to initialize Live Photo video: $e', 'LivePhotoViewer');        _initializeVideo();

            minScale: PhotoViewComputedScale.contained * 0.5,

            maxScale: PhotoViewComputedScale.covered * 3.0,      setState(() {

            heroAttributes: PhotoViewHeroAttributes(

              tag: 'live_photo_${widget.file.name}',        _videoError = true;  @override    }

            ),

            loadingBuilder: (context, event) => Container(        _errorMessage = e.toString();

              color: Colors.black,

              child: const Center(      });  void dispose() {    

                child: CircularProgressIndicator(

                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),    }

                ),

              ),  }    _videoController?.removeListener(_videoListener);    // 保持屏幕常亮

            ),

            errorBuilder: (context, error, stackTrace) => Container(  

              color: Colors.black,

              child: const Center(  void _videoListener() {    _videoController?.dispose();    WakelockPlus.enable();

                child: Column(

                  mainAxisAlignment: MainAxisAlignment.center,    if (_videoController == null) return;

                  children: [

                    Icon(Icons.error_outline, color: Colors.red, size: 48),        WakelockPlus.disable();  }

                    SizedBox(height: 16),

                    Text('无法加载照片', style: TextStyle(color: Colors.white, fontSize: 16)),    if (_livePhotoType == LivePhotoType.apple && 

                  ],

                ),        _videoController!.value.position >= _videoController!.value.duration) {    super.dispose();  

              ),

            ),      setState(() {

            backgroundDecoration: const BoxDecoration(color: Colors.black),

          );        _isPlayingVideo = false;  }  @override

        } else {

          return Container(      });

            color: Colors.black,

            child: const Center(    }    void dispose() {

              child: CircularProgressIndicator(

                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),  }

              ),

            ),    void _detectLivePhotoType() {    _videoController?.dispose();

          );

        }  void _toggleAppBar() {

      },

    );    setState(() {    final fileName = widget.file.name.toLowerCase();    WakelockPlus.disable();

  }

        _showAppBar = !_showAppBar;

  @override

  Widget build(BuildContext context) {    });    final videoFileName = widget.videoFile?.name.toLowerCase() ?? '';    super.dispose();

    return Scaffold(

      backgroundColor: Colors.black,  }

      appBar: _showAppBar

          ? AppBar(        }

              backgroundColor: Colors.black.withOpacity(0.7),

              foregroundColor: Colors.white,  void _togglePlayback() {

              title: Text(

                widget.file.name,    if (_videoController == null || !_videoInitialized || _videoError) return;    if (fileName.contains('heic') || fileName.contains('heif')) {  

                style: const TextStyle(color: Colors.white),

                overflow: TextOverflow.ellipsis,    

              ),

              centerTitle: true,    setState(() {      _livePhotoType = LivePhotoType.apple;  void _detectLivePhotoType() {

              elevation: 0,

              actions: [      if (_isPlayingVideo) {

                if (widget.videoFile != null)

                  IconButton(        _videoController!.pause();    } else if (videoFileName.contains('mp4') && fileName.contains('jpg')) {    final fileName = widget.file.name.toLowerCase();

                    icon: Icon(_isPlayingVideo ? Icons.pause : Icons.play_arrow),

                    onPressed: _togglePlayback,        _isPlayingVideo = false;

                  ),

                IconButton(              _livePhotoType = LivePhotoType.xiaomi;    final videoFileName = widget.videoFile?.name.toLowerCase() ?? '';

                  icon: const Icon(Icons.download),

                  onPressed: _downloadFile,        if (_livePhotoType == LivePhotoType.apple) {

                ),

              ],          _videoController!.seekTo(Duration.zero);    } else {    

            )

          : null,        }

      body: Stack(

        children: [      } else {      _livePhotoType = LivePhotoType.generic;    if (fileName.contains('heic') || fileName.contains('heif')) {

          Positioned.fill(

            child: GestureDetector(        if (_livePhotoType == LivePhotoType.apple) {

              onTap: _toggleAppBar,

              onLongPress: widget.videoFile != null ? _togglePlayback : null,          _videoController!.seekTo(Duration.zero);    }      _livePhotoType = LivePhotoType.apple;

              child: _buildContent(),

            ),        }

          ),

                          } else if (videoFileName.contains('mp4') && fileName.contains('jpg')) {

          if (widget.videoFile != null)

            Positioned(        _videoController!.play();

              top: 16,

              right: 16,        _isPlayingVideo = true;    LogService.instance.info('Detected Live Photo type: $_livePhotoType', 'LivePhotoViewer');      _livePhotoType = LivePhotoType.xiaomi;

              child: AnimatedOpacity(

                opacity: _showAppBar ? 1.0 : 0.3,      }

                duration: const Duration(milliseconds: 300),

                child: Container(    });  }    } else {

                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

                  decoration: BoxDecoration(    

                    color: Colors.black54,

                    borderRadius: BorderRadius.circular(20),    HapticFeedback.lightImpact();        _livePhotoType = LivePhotoType.generic;

                  ),

                  child: Row(  }

                    mainAxisSize: MainAxisSize.min,

                    children: [    Future<void> _initializeVideo() async {    }

                      Icon(

                        _isPlayingVideo ? Icons.motion_photos_on : Icons.motion_photos_paused,  Future<void> _downloadFile() async {

                        color: _isPlayingVideo ? Colors.blue : Colors.white70,

                        size: 16,    try {    if (widget.videoFile == null) return;    

                      ),

                      const SizedBox(width: 4),      final downloadUrl = await widget.apiClient.getDownloadUrl(widget.file);

                      Text(

                        'LIVE',              LogService.instance.info('Detected Live Photo type: $_livePhotoType', 'LivePhotoViewer');

                        style: TextStyle(

                          color: _isPlayingVideo ? Colors.blue : Colors.white70,      await FileDownloadService.instance.downloadFile(

                          fontSize: 12,

                          fontWeight: FontWeight.bold,        url: downloadUrl,    try {  }

                        ),

                      ),        fileName: widget.file.name,

                    ],

                  ),        onProgress: (received, total) {},      LogService.instance.info('Initializing Live Photo video: ${widget.videoFile!.name}', 'LivePhotoViewer');  

                ),

              ),      );

            ),

        ],              Future<void> _initializeVideo() async {

      ),

    );      if (mounted) {

  }

}        ScaffoldMessenger.of(context).showSnackBar(      final videoUrl = await widget.apiClient.getDownloadUrl(widget.videoFile!);    if (widget.videoFile == null) return;

          SnackBar(content: Text('${widget.file.name} 下载完成')),

        );      _videoController = VideoPlayerController.networkUrl(    

      }

    } catch (e) {        Uri.parse(videoUrl),    try {

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(        httpHeaders: {      LogService.instance.info('Initializing Live Photo video: ${widget.videoFile!.name}', 'LivePhotoViewer');

          SnackBar(

            content: Text('下载失败: $e'),          'User-Agent': 'Alist-Photo-Flutter-App',      

            backgroundColor: Colors.red,

          ),        },      final videoUrl = await widget.apiClient.getDownloadUrl(widget.videoFile!);

        );

      }      );      _videoController = VideoPlayerController.networkUrl(

    }

  }              Uri.parse(videoUrl),

  

  Future<void> _downloadVideoFile() async {      await _videoController!.initialize();        httpHeaders: {

    if (widget.videoFile == null) return;

                    'User-Agent': 'Alist-Photo-Flutter-App',

    try {

      final downloadUrl = await widget.apiClient.getDownloadUrl(widget.videoFile!);      // 根据 Live Photo 类型设置不同的播放行为        },

      

      await FileDownloadService.instance.downloadFile(      switch (_livePhotoType) {      );

        url: downloadUrl,

        fileName: widget.videoFile!.name,        case LivePhotoType.apple:      

        onProgress: (received, total) {},

      );          // 苹果 Live Photo 通常短时间播放      await _videoController!.initialize();

      

      if (mounted) {          _videoController!.setLooping(false);      

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(content: Text('${widget.videoFile!.name} 下载完成')),          break;      // 根据 Live Photo 类型设置不同的播放行为

        );

      }        case LivePhotoType.xiaomi:      switch (_livePhotoType) {

    } catch (e) {

      if (mounted) {          // 小米动态照片通常循环播放        case LivePhotoType.apple:

        ScaffoldMessenger.of(context).showSnackBar(

          SnackBar(          _videoController!.setLooping(true);          // 苹果 Live Photo 通常短时间播放

            content: Text('视频下载失败: $e'),

            backgroundColor: Colors.red,          break;          _videoController!.setLooping(false);

          ),

        );        default:          break;

      }

    }          _videoController!.setLooping(true);        case LivePhotoType.xiaomi:

  }

            break;          // 小米动态照片通常循环播放

  Future<String> _getImageUrl() async {

    return await widget.apiClient.getDownloadUrl(widget.file);      }          _videoController!.setLooping(true);

  }

                  break;

  Widget _buildPhotoContent() {

    if (_videoError) {      // 监听播放完成        default:

      return Container(

        color: Colors.black,      _videoController!.addListener(_videoListener);          _videoController!.setLooping(true);

        child: const Center(

          child: Column(                break;

            mainAxisAlignment: MainAxisAlignment.center,

            children: [      setState(() {      }

              Icon(Icons.error_outline, color: Colors.red, size: 48),

              SizedBox(height: 16),        _videoInitialized = true;      

              Text('动态照片加载失败', style: TextStyle(color: Colors.white, fontSize: 18)),

            ],        _videoError = false;      // 监听播放完成

          ),

        ),        _errorMessage = null;      _videoController!.addListener(_videoListener);

      );

    }      });      



    if (_isPlayingVideo && _videoController != null && _videoInitialized) {            setState(() {

      return Container(

        color: Colors.black,      LogService.instance.info('Live Photo video initialized successfully', 'LivePhotoViewer');        _videoInitialized = true;

        child: Center(

          child: AspectRatio(    } catch (e) {        _videoError = false;

            aspectRatio: _videoController!.value.aspectRatio.isNaN 

                ? 16 / 9       LogService.instance.error('Failed to initialize Live Photo video: $e', 'LivePhotoViewer');        _errorMessage = null;

                : _videoController!.value.aspectRatio,

            child: VideoPlayer(_videoController!),      setState(() {      });

          ),

        ),        _videoError = true;      

      );

    }        _errorMessage = e.toString();      LogService.instance.info('Live Photo video initialized successfully', 'LivePhotoViewer');



    return FutureBuilder<String>(      });    } catch (e) {

      future: _getImageUrl(),

      builder: (context, snapshot) {    }      LogService.instance.error('Failed to initialize Live Photo video: $e', 'LivePhotoViewer');

        if (snapshot.hasData) {

          return PhotoView(  }      setState(() {

            imageProvider: CachedNetworkImageProvider(

              snapshot.data!,          _videoError = true;

              cacheManager: MediaCacheManager.instance.originalCache,

            ),  void _videoListener() {        _errorMessage = e.toString();

            initialScale: PhotoViewComputedScale.contained,

            minScale: PhotoViewComputedScale.contained * 0.5,    if (_videoController == null) return;      });

            maxScale: PhotoViewComputedScale.covered * 3.0,

            heroAttributes: PhotoViewHeroAttributes(        }

              tag: 'live_photo_${widget.file.name}',

            ),    // 如果是苹果 Live Photo 且播放完成，自动停止  }

            loadingBuilder: (context, event) => Container(

              color: Colors.black,    if (_livePhotoType == LivePhotoType.apple &&   

              child: const Center(

                child: CircularProgressIndicator(        _videoController!.value.position >= _videoController!.value.duration) {  void _videoListener() {

                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),

                ),      setState(() {    if (_videoController == null) return;

              ),

            ),        _isPlayingVideo = false;    

            errorBuilder: (context, error, stackTrace) => Container(

              color: Colors.black,      });    // 如果是苹果 Live Photo 且播放完成，自动停止

              child: const Center(

                child: Column(    }    if (_livePhotoType == LivePhotoType.apple && 

                  mainAxisAlignment: MainAxisAlignment.center,

                  children: [  }        _videoController!.value.position >= _videoController!.value.duration) {

                    Icon(Icons.error_outline, color: Colors.red, size: 48),

                    SizedBox(height: 16),        setState(() {

                    Text('无法加载照片', style: TextStyle(color: Colors.white, fontSize: 16)),

                  ],  void _toggleAppBar() {        _isPlayingVideo = false;

                ),

              ),    setState(() {      });

            ),

            backgroundDecoration: const BoxDecoration(color: Colors.black),      _showAppBar = !_showAppBar;    }

          );

        } else if (snapshot.hasError) {    });  }

          return Container(

            color: Colors.black,  }  

            child: const Center(

              child: Column(    void _toggleAppBar() {

                mainAxisAlignment: MainAxisAlignment.center,

                children: [  void _togglePlayback() {    setState(() {

                  Icon(Icons.error_outline, color: Colors.red, size: 48),

                  SizedBox(height: 16),    if (_videoController == null || !_videoInitialized || _videoError) return;      _showAppBar = !_showAppBar;

                  Text('加载失败', style: TextStyle(color: Colors.white, fontSize: 16)),

                ],        });

              ),

            ),    setState(() {  }

          );

        } else {      if (_isPlayingVideo) {  

          return Container(

            color: Colors.black,        _videoController!.pause();  void _togglePlayback() {

            child: const Center(

              child: CircularProgressIndicator(        _isPlayingVideo = false;    if (_videoController == null || !_videoInitialized || _videoError) return;

                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),

              ),            

            ),

          );        // 对于苹果 Live Photo，暂停时重置到开始位置    setState(() {

        }

      },        if (_livePhotoType == LivePhotoType.apple) {      if (_isPlayingVideo) {

    );

  }          _videoController!.seekTo(Duration.zero);        _videoController!.pause();

  

  @override        }        _isPlayingVideo = false;

  Widget build(BuildContext context) {

    return Scaffold(      } else {        

      backgroundColor: Colors.black,

      appBar: _showAppBar        // 对于苹果 Live Photo，从头开始播放        // 对于苹果 Live Photo，暂停时重置到开始位置

          ? AppBar(

              backgroundColor: Colors.black.withOpacity(0.7),        if (_livePhotoType == LivePhotoType.apple) {        if (_livePhotoType == LivePhotoType.apple) {

              foregroundColor: Colors.white,

              title: Text(          _videoController!.seekTo(Duration.zero);          _videoController!.seekTo(Duration.zero);

                widget.file.name,

                style: const TextStyle(color: Colors.white),        }        }

                overflow: TextOverflow.ellipsis,

              ),              } else {

              centerTitle: true,

              elevation: 0,        _videoController!.play();        // 对于苹果 Live Photo，从头开始播放

              actions: [

                if (widget.videoFile != null)        _isPlayingVideo = true;        if (_livePhotoType == LivePhotoType.apple) {

                  IconButton(

                    icon: Icon(_isPlayingVideo ? Icons.pause : Icons.play_arrow),      }          _videoController!.seekTo(Duration.zero);

                    onPressed: _togglePlayback,

                    tooltip: _isPlayingVideo ? '暂停' : '播放动态照片',    });        }

                  ),

                IconButton(            

                  icon: const Icon(Icons.download),

                  onPressed: _downloadFile,    // 触觉反馈        _videoController!.play();

                  tooltip: '下载照片',

                ),    HapticFeedback.lightImpact();        _isPlayingVideo = true;

                if (widget.videoFile != null)

                  IconButton(  }      }

                    icon: const Icon(Icons.video_file),

                    onPressed: _downloadVideoFile,      });

                    tooltip: '下载视频文件',

                  ),  Future<void> _downloadFile() async {    

              ],

            )    try {    // 触觉反馈

          : null,

      body: Stack(      final downloadUrl = await widget.apiClient.getDownloadUrl(widget.file);    HapticFeedback.lightImpact();

        children: [

          Positioned.fill(        }

            child: GestureDetector(

              onTap: _toggleAppBar,      await FileDownloadService.instance.downloadFile(  

              onLongPress: widget.videoFile != null ? _togglePlayback : null,

              child: _buildPhotoContent(),        url: downloadUrl,  Future<void> _downloadVideoFile() async {

            ),

          ),        fileName: widget.file.name,    if (widget.videoFile == null) return;

          

          if (widget.videoFile != null)        onProgress: (received, total) {    

            Positioned(

              top: 16,          LogService.instance.debug('Download progress: ${((received / total) * 100).toStringAsFixed(1)}%', 'LivePhotoViewer');    try {

              right: 16,

              child: AnimatedOpacity(        },      final downloadUrl = await widget.apiClient.getDownloadUrl(widget.videoFile!);

                opacity: _showAppBar ? 1.0 : 0.3,

                duration: const Duration(milliseconds: 300),      );      

                child: Container(

                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),            await FileDownloadService.instance.downloadFile(

                  decoration: BoxDecoration(

                    color: Colors.black54,      if (mounted) {        url: downloadUrl,

                    borderRadius: BorderRadius.circular(20),

                  ),        ScaffoldMessenger.of(context).showSnackBar(        fileName: widget.videoFile!.name,

                  child: Row(

                    mainAxisSize: MainAxisSize.min,          SnackBar(content: Text('${widget.file.name} 下载完成')),        onProgress: (received, total) {

                    children: [

                      Icon(        );          LogService.instance.debug('Video download progress: ${((received / total) * 100).toStringAsFixed(1)}%', 'LivePhotoViewer');

                        _isPlayingVideo ? Icons.motion_photos_on : Icons.motion_photos_paused,

                        color: _isPlayingVideo ? Colors.blue : Colors.white70,      }        },

                        size: 16,

                      ),    } catch (e) {      );

                      const SizedBox(width: 4),

                      Text(      LogService.instance.error('Download failed: $e', 'LivePhotoViewer');      

                        'LIVE',

                        style: TextStyle(      if (mounted) {      if (mounted) {

                          color: _isPlayingVideo ? Colors.blue : Colors.white70,

                          fontSize: 12,        ScaffoldMessenger.of(context).showSnackBar(        ScaffoldMessenger.of(context).showSnackBar(

                          fontWeight: FontWeight.bold,

                        ),          SnackBar(          SnackBar(content: Text('${widget.videoFile!.name} 下载完成')),

                      ),

                    ],            content: Text('下载失败: $e'),        );

                  ),

                ),            backgroundColor: Colors.red,      }

              ),

            ),          ),    } catch (e) {

        ],

      ),        );      LogService.instance.error('Video download failed: $e', 'LivePhotoViewer');

    );

  }      }      if (mounted) {

}
    }        ScaffoldMessenger.of(context).showSnackBar(

  }          SnackBar(

              content: Text('视频下载失败: $e'),

  Future<void> _downloadVideoFile() async {            backgroundColor: Colors.red,

    if (widget.videoFile == null) return;          ),

            );

    try {      }

      final downloadUrl = await widget.apiClient.getDownloadUrl(widget.videoFile!);    }

        }

      await FileDownloadService.instance.downloadFile(  

        url: downloadUrl,  Future<void> _downloadFile() async {

        fileName: widget.videoFile!.name,    try {

        onProgress: (received, total) {      final downloadUrl = await widget.apiClient.getDownloadUrl(widget.file);

          LogService.instance.debug('Video download progress: ${((received / total) * 100).toStringAsFixed(1)}%', 'LivePhotoViewer');      

        },      await FileDownloadService.instance.downloadFile(

      );          url: downloadUrl,

                fileName: widget.file.name,

      if (mounted) {          onProgress: (received, total) {

        ScaffoldMessenger.of(context).showSnackBar(            LogService.instance.debug('Download progress: ${((received / total) * 100).toStringAsFixed(1)}%', 'LivePhotoViewer');

          SnackBar(content: Text('${widget.videoFile!.name} 下载完成')),          },

        );        );

      }      

    } catch (e) {      if (mounted) {

      LogService.instance.error('Video download failed: $e', 'LivePhotoViewer');        ScaffoldMessenger.of(context).showSnackBar(

      if (mounted) {          SnackBar(content: Text('${widget.file.name} 下载完成')),

        ScaffoldMessenger.of(context).showSnackBar(        );

          SnackBar(      }

            content: Text('视频下载失败: $e'),    } catch (e) {

            backgroundColor: Colors.red,      LogService.instance.error('Download failed: $e', 'LivePhotoViewer');

          ),      if (mounted) {

        );        ScaffoldMessenger.of(context).showSnackBar(

      }          SnackBar(content: Text('下载失败: $e')),

    }        );

  }      }

      }

  Future<String> _getImageUrl() async {  }

    return await widget.apiClient.getDownloadUrl(widget.file);  

  }  Widget _buildPhotoContent() {

      if (_videoError) {

  Widget _buildPhotoContent() {      return Container(

    if (_videoError) {        color: Colors.black,

      return Container(        child: Center(

        color: Colors.black,          child: Column(

        child: Center(            mainAxisAlignment: MainAxisAlignment.center,

          child: Column(            children: [

            mainAxisAlignment: MainAxisAlignment.center,              const Icon(

            children: [                Icons.error_outline,

              const Icon(                color: Colors.red,

                Icons.error_outline,                size: 48,

                color: Colors.red,              ),

                size: 48,              const SizedBox(height: 16),

              ),              const Text(

              const SizedBox(height: 16),                '动态照片加载失败',

              const Text(                style: TextStyle(

                '动态照片加载失败',                  color: Colors.white,

                style: TextStyle(                  fontSize: 18,

                  color: Colors.white,                ),

                  fontSize: 18,              ),

                ),              const SizedBox(height: 8),

              ),              if (_errorMessage != null)

              const SizedBox(height: 8),                Padding(

              if (_errorMessage != null)                  padding: const EdgeInsets.symmetric(horizontal: 32),

                Padding(                  child: Text(

                  padding: const EdgeInsets.symmetric(horizontal: 32),                    _errorMessage!,

                  child: Text(                    style: const TextStyle(

                    _errorMessage!,                      color: Colors.white70,

                    style: const TextStyle(                      fontSize: 14,

                      color: Colors.white70,                    ),

                      fontSize: 14,                    textAlign: TextAlign.center,

                    ),                  ),

                    textAlign: TextAlign.center,                ),

                  ),            ],

                ),          ),

            ],        ),

          ),      );

        ),    }

      );

    }    if (_isPlayingVideo && _videoController != null && _videoInitialized) {

      return Container(

    if (_isPlayingVideo && _videoController != null && _videoInitialized) {        color: Colors.black,

      return Container(        child: Center(

        color: Colors.black,          child: AspectRatio(

        child: Center(            aspectRatio: _videoController!.value.aspectRatio.isNaN 

          child: AspectRatio(                ? 16 / 9 

            aspectRatio: _videoController!.value.aspectRatio.isNaN                 : _videoController!.value.aspectRatio,

                ? 16 / 9             child: VideoPlayer(_videoController!),

                : _videoController!.value.aspectRatio,          ),

            child: VideoPlayer(_videoController!),        ),

          ),      );

        ),    }

      );

    }    return FutureBuilder<String>(

      future: _getImageUrl(),

    return FutureBuilder<String>(      builder: (context, snapshot) {

      future: _getImageUrl(),        if (snapshot.hasData) {

      builder: (context, snapshot) {          return PhotoView(

        if (snapshot.hasData) {            imageProvider: CachedNetworkImageProvider(

          return PhotoView(              snapshot.data!,

            imageProvider: CachedNetworkImageProvider(              cacheManager: MediaCacheManager.instance.originalCache,

              snapshot.data!,            ),

              cacheManager: MediaCacheManager.instance.cache,            initialScale: PhotoViewComputedScale.contained,

            ),            minScale: PhotoViewComputedScale.contained * 0.5,

            initialScale: PhotoViewComputedScale.contained,            maxScale: PhotoViewComputedScale.covered * 3.0,

            minScale: PhotoViewComputedScale.contained * 0.5,            heroAttributes: PhotoViewHeroAttributes(

            maxScale: PhotoViewComputedScale.covered * 3.0,              tag: 'live_photo_${widget.file.name}',

            heroAttributes: PhotoViewHeroAttributes(            ),

              tag: 'live_photo_${widget.file.name}',            loadingBuilder: (context, event) => Container(

            ),              color: Colors.black,

            loadingBuilder: (context, event) => Container(              child: Center(

              color: Colors.black,                child: Column(

              child: Center(                  mainAxisAlignment: MainAxisAlignment.center,

                child: Column(                  children: [

                  mainAxisAlignment: MainAxisAlignment.center,                    const CircularProgressIndicator(

                  children: [                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),

                    const CircularProgressIndicator(                    ),

                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),                    const SizedBox(height: 16),

                    ),                    if (event != null)

                    const SizedBox(height: 16),                      Text(

                    if (event != null)                        '${((event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1)) * 100).toStringAsFixed(0)}%',

                      Text(                        style: const TextStyle(color: Colors.white70),

                        '${((event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1)) * 100).toStringAsFixed(0)}%',                      ),

                        style: const TextStyle(color: Colors.white70),                  ],

                      ),                ),

                  ],              ),

                ),            ),

              ),            errorBuilder: (context, error, stackTrace) => Container(

            ),              color: Colors.black,

            errorBuilder: (context, error, stackTrace) => Container(              child: const Center(

              color: Colors.black,                child: Column(

              child: const Center(                  mainAxisAlignment: MainAxisAlignment.center,

                child: Column(                  children: [

                  mainAxisAlignment: MainAxisAlignment.center,                    Icon(

                  children: [                      Icons.error_outline,

                    Icon(                      color: Colors.red,

                      Icons.error_outline,                      size: 48,

                      color: Colors.red,                    ),

                      size: 48,                    SizedBox(height: 16),

                    ),                    Text(

                    SizedBox(height: 16),                      '无法加载照片',

                    Text(                      style: TextStyle(

                      '无法加载照片',                        color: Colors.white,

                      style: TextStyle(                        fontSize: 16,

                        color: Colors.white,                      ),

                        fontSize: 16,                    ),

                      ),                  ],

                    ),                ),

                  ],              ),

                ),            ),

              ),            backgroundDecoration: const BoxDecoration(

            ),              color: Colors.black,

            backgroundDecoration: const BoxDecoration(            ),

              color: Colors.black,          );

            ),        } else if (snapshot.hasError) {

          );          return Container(

        } else if (snapshot.hasError) {            color: Colors.black,

          return Container(            child: const Center(

            color: Colors.black,              child: Column(

            child: const Center(                mainAxisAlignment: MainAxisAlignment.center,

              child: Column(                children: [

                mainAxisAlignment: MainAxisAlignment.center,                  Icon(

                children: [                    Icons.error_outline,

                  Icon(                    color: Colors.red,

                    Icons.error_outline,                    size: 48,

                    color: Colors.red,                  ),

                    size: 48,                  SizedBox(height: 16),

                  ),                  Text(

                  SizedBox(height: 16),                    '加载失败',

                  Text(                    style: TextStyle(

                    '加载失败',                      color: Colors.white,

                    style: TextStyle(                      fontSize: 16,

                      color: Colors.white,                    ),

                      fontSize: 16,                  ),

                    ),                ],

                  ),              ),

                ],            ),

              ),          );

            ),        } else {

          );          return Container(

        } else {            color: Colors.black,

          return Container(            child: const Center(

            color: Colors.black,              child: CircularProgressIndicator(

            child: const Center(                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),

              child: CircularProgressIndicator(              ),

                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),            ),

              ),          );

            ),        }

          );      },

        }    );

      },  }

    );  

  }  Future<String> _getImageUrl() async {

      if (widget.file.rawUrl?.isNotEmpty == true) {

  @override      return widget.apiClient.getFullUrl(widget.file.rawUrl!);

  Widget build(BuildContext context) {    } else {

    return Scaffold(      return await widget.apiClient.getDownloadUrl(widget.file);

      backgroundColor: Colors.black,    }

      appBar: _showAppBar  }

          ? AppBar(  

              backgroundColor: Colors.black.withOpacity(0.7),  @override

              foregroundColor: Colors.white,  Widget build(BuildContext context) {

              title: Text(    return Scaffold(

                widget.file.name,      backgroundColor: Colors.black,

                style: const TextStyle(color: Colors.white),      appBar: _showAppBar

                overflow: TextOverflow.ellipsis,          ? AppBar(

              ),              backgroundColor: Colors.black.withOpacity(0.7),

              centerTitle: true,              foregroundColor: Colors.white,

              elevation: 0,              title: const Text(

              actions: [                'Live Photo',

                if (widget.videoFile != null)                style: TextStyle(color: Colors.white),

                  IconButton(              ),

                    icon: Icon(_isPlayingVideo ? Icons.pause : Icons.play_arrow),              centerTitle: true,

                    onPressed: _togglePlayback,              elevation: 0,

                    tooltip: _isPlayingVideo ? '暂停' : '播放动态照片',              actions: [

                  ),                IconButton(

                IconButton(                  icon: const Icon(Icons.download),

                  icon: const Icon(Icons.download),                  onPressed: _downloadFile,

                  onPressed: _downloadFile,                  tooltip: '下载到本地',

                  tooltip: '下载照片',                ),

                ),              ],

                if (widget.videoFile != null)            )

                  IconButton(          : null,

                    icon: const Icon(Icons.video_file),      body: Stack(

                    onPressed: _downloadVideoFile,        children: [

                    tooltip: '下载视频文件',          // 背景图片或视频

                  ),          Positioned.fill(

              ],            child: Stack(

            )              children: [

          : null,                // 主要内容区域

      body: Stack(                GestureDetector(

        children: [                  onTap: _toggleAppBar,

          // 背景图片或视频                  onLongPress: widget.videoFile != null ? _togglePlayback : null,

          Positioned.fill(                  child: _buildPhotoContent(),

            child: GestureDetector(                ),

              onTap: _toggleAppBar,                

              onLongPress: widget.videoFile != null ? _togglePlayback : null,                // Live Photo 指示器

              child: _buildPhotoContent(),                if (widget.videoFile != null)

            ),                  Positioned(

          ),                    top: 16,

                              right: 16,

          // Live Photo 指示器                    child: AnimatedOpacity(

          if (widget.videoFile != null)                      opacity: _showAppBar ? 1.0 : 0.3,

            Positioned(                      duration: const Duration(milliseconds: 300),

              top: 16,                      child: Container(

              right: 16,                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

              child: AnimatedOpacity(                        decoration: BoxDecoration(

                opacity: _showAppBar ? 1.0 : 0.3,                          color: Colors.black54,

                duration: const Duration(milliseconds: 300),                          borderRadius: BorderRadius.circular(20),

                child: Container(                        ),

                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),                        child: Row(

                  decoration: BoxDecoration(                          mainAxisSize: MainAxisSize.min,

                    color: Colors.black54,                          children: [

                    borderRadius: BorderRadius.circular(20),                            Icon(

                  ),                              _isPlayingVideo ? Icons.motion_photos_on : Icons.motion_photos_paused,

                  child: Row(                              color: _isPlayingVideo ? Colors.blue : Colors.white70,

                    mainAxisSize: MainAxisSize.min,                              size: 16,

                    children: [                            ),

                      Icon(                            const SizedBox(width: 4),

                        _isPlayingVideo ? Icons.motion_photos_on : Icons.motion_photos_paused,                            Text(

                        color: _isPlayingVideo ? Colors.blue : Colors.white70,                              'LIVE',

                        size: 16,                              style: TextStyle(

                      ),                                color: _isPlayingVideo ? Colors.blue : Colors.white70,

                      const SizedBox(width: 4),                                fontSize: 12,

                      Text(                                fontWeight: FontWeight.bold,

                        'LIVE',                              ),

                        style: TextStyle(                            ),

                          color: _isPlayingVideo ? Colors.blue : Colors.white70,                          ],

                          fontSize: 12,                        ),

                          fontWeight: FontWeight.bold,                      ),

                        ),                    ),

                      ),                  ),

                    ],                

                  ),                // 播放/暂停按钮覆盖层（仅在显示 UI 时）

                ),                if (widget.videoFile != null && _showAppBar && !_isPlayingVideo)

              ),                  Positioned.fill(

            ),                    child: Center(

        ],                      child: Container(

      ),                        decoration: const BoxDecoration(

    );                          color: Colors.black38,

  }                          shape: BoxShape.circle,

}                        ),
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