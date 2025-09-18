import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'log_service.dart';

class MediaCacheManager {
  static MediaCacheManager? _instance;
  static MediaCacheManager get instance => _instance ??= MediaCacheManager._();
  
  late final CacheManager _thumbnailCache;
  late final CacheManager _imageCache;
  late final CacheManager _videoCache;
  
  MediaCacheManager._() {
    _initializeCaches();
  }
  
  void _initializeCaches() {
    // 缩略图缓存 - 较小的文件，保存较长时间，数量较多
    _thumbnailCache = CacheManager(
      Config(
        'thumbnail_cache',
        maxNrOfCacheObjects: 1000, // 保存1000个缩略图
        stalePeriod: const Duration(days: 30), // 30天过期
      ),
    );
    
    // 原图缓存 - 较大的文件，根据存储空间动态管理
    _imageCache = CacheManager(
      Config(
        'image_cache',
        maxNrOfCacheObjects: 200, // 保存200个原图
        stalePeriod: const Duration(days: 7), // 7天过期
      ),
    );
    
    // 视频缓存 - 最大的文件，保存数量较少
    _videoCache = CacheManager(
      Config(
        'video_cache',
        maxNrOfCacheObjects: 50, // 保存50个视频
        stalePeriod: const Duration(days: 3), // 3天过期
      ),
    );
    
    LogService.instance.info('Media cache managers initialized', 'MediaCacheManager');
  }
  
  /// 获取缩略图缓存管理器
  CacheManager get thumbnailCache => _thumbnailCache;
  
  /// 获取图片缓存管理器
  CacheManager get imageCache => _imageCache;
  
  /// 获取视频缓存管理器
  CacheManager get videoCache => _videoCache;
  
  /// 根据URL获取合适的缓存管理器
  CacheManager getCacheManagerForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return _imageCache;
    
    final path = uri.path.toLowerCase();
    
    // 缩略图URL通常包含特定标识
    if (path.contains('thumb') || path.contains('preview') || url.contains('thumbnail')) {
      return _thumbnailCache;
    }
    
    // 视频文件
    if (path.endsWith('.mp4') || path.endsWith('.avi') || path.endsWith('.mov') ||
        path.endsWith('.wmv') || path.endsWith('.flv') || path.endsWith('.webm') ||
        path.endsWith('.mkv') || path.endsWith('.m4v')) {
      return _videoCache;
    }
    
    // 默认使用图片缓存
    return _imageCache;
  }
  
  /// 预加载文件到缓存
  Future<void> preloadFile(String url, {String? cacheKey}) async {
    try {
      final cacheManager = getCacheManagerForUrl(url);
      await cacheManager.downloadFile(url, key: cacheKey);
      LogService.instance.debug('Preloaded file to cache: $url', 'MediaCacheManager');
    } catch (e) {
      LogService.instance.warning('Failed to preload file: $url, error: $e', 'MediaCacheManager');
    }
  }
  
  /// 批量预加载文件
  Future<void> preloadFiles(List<String> urls) async {
    for (final url in urls) {
      // 添加小延迟避免同时下载太多文件
      await Future.delayed(const Duration(milliseconds: 100));
      preloadFile(url);
    }
  }
  
  /// 检查文件是否已缓存
  Future<bool> isCached(String url, {String? cacheKey}) async {
    try {
      final cacheManager = getCacheManagerForUrl(url);
      final fileInfo = await cacheManager.getFileFromCache(cacheKey ?? url);
      return fileInfo != null && fileInfo.file.existsSync();
    } catch (e) {
      return false;
    }
  }
  
  /// 获取缓存文件
  Future<File?> getCachedFile(String url, {String? cacheKey}) async {
    try {
      final cacheManager = getCacheManagerForUrl(url);
      final fileInfo = await cacheManager.getFileFromCache(cacheKey ?? url);
      return fileInfo?.file;
    } catch (e) {
      LogService.instance.warning('Failed to get cached file: $url, error: $e', 'MediaCacheManager');
      return null;
    }
  }
  
  /// 获取缓存统计信息
  Future<CacheStats> getCacheStats() async {
    final thumbnailStats = await _getCacheManagerStats(_thumbnailCache);
    final imageStats = await _getCacheManagerStats(_imageCache);
    final videoStats = await _getCacheManagerStats(_videoCache);
    
    return CacheStats(
      thumbnailCount: thumbnailStats['count'] ?? 0,
      thumbnailSize: thumbnailStats['size'] ?? 0,
      imageCount: imageStats['count'] ?? 0,
      imageSize: imageStats['size'] ?? 0,
      videoCount: videoStats['count'] ?? 0,
      videoSize: videoStats['size'] ?? 0,
    );
  }
  
  Future<Map<String, int>> _getCacheManagerStats(CacheManager cacheManager) async {
    try {
      int count = 0;
      int totalSize = 0;
      
      // Use FileSystem to get cache directory
      final cacheDir = await cacheManager.getFileSystem().directory();
      if (await cacheDir.exists()) {
        await for (final entity in cacheDir.list()) {
          if (entity is File) {
            count++;
            totalSize += await entity.length();
          }
        }
      }
      
      return {'count': count, 'size': totalSize};
    } catch (e) {
      LogService.instance.warning('Failed to get cache stats: $e', 'MediaCacheManager');
      return {'count': 0, 'size': 0};
    }
  }
  
  /// 清理指定类型的缓存
  Future<void> clearCache(CacheType type) async {
    try {
      switch (type) {
        case CacheType.thumbnail:
          await _thumbnailCache.emptyCache();
          LogService.instance.info('Thumbnail cache cleared', 'MediaCacheManager');
          break;
        case CacheType.image:
          await _imageCache.emptyCache();
          LogService.instance.info('Image cache cleared', 'MediaCacheManager');
          break;
        case CacheType.video:
          await _videoCache.emptyCache();
          LogService.instance.info('Video cache cleared', 'MediaCacheManager');
          break;
        case CacheType.all:
          await _thumbnailCache.emptyCache();
          await _imageCache.emptyCache();
          await _videoCache.emptyCache();
          LogService.instance.info('All caches cleared', 'MediaCacheManager');
          break;
      }
    } catch (e) {
      LogService.instance.error('Failed to clear cache: $e', 'MediaCacheManager');
    }
  }
  
  /// 清理过期缓存
  Future<void> cleanupExpiredCache() async {
    try {
      // Flutter Cache Manager 会自动处理过期文件
      // 这里我们手动触发清理过程
      await _thumbnailCache.emptyCache();
      await _imageCache.emptyCache();
      await _videoCache.emptyCache();
      
      LogService.instance.info('Expired cache cleaned up', 'MediaCacheManager');
    } catch (e) {
      LogService.instance.error('Failed to cleanup expired cache: $e', 'MediaCacheManager');
    }
  }
  
  /// 获取缓存目录大小
  Future<int> getCacheDirSize() async {
    try {
      int totalSize = 0;
      final cacheManagers = [_thumbnailCache, _imageCache, _videoCache];
      
      for (final manager in cacheManagers) {
        // Use FileSystem to get cache directory
        final dir = await manager.getFileSystem().directory();
        if (await dir.exists()) {
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              totalSize += await entity.length();
            }
          }
        }
      }
      
      return totalSize;
    } catch (e) {
      LogService.instance.error('Failed to get cache directory size: $e', 'MediaCacheManager');
      return 0;
    }
  }
}

class CacheStats {
  final int thumbnailCount;
  final int thumbnailSize;
  final int imageCount;
  final int imageSize;
  final int videoCount;
  final int videoSize;
  
  CacheStats({
    required this.thumbnailCount,
    required this.thumbnailSize,
    required this.imageCount,
    required this.imageSize,
    required this.videoCount,
    required this.videoSize,
  });
  
  int get totalCount => thumbnailCount + imageCount + videoCount;
  int get totalSize => thumbnailSize + imageSize + videoSize;
  
  String get formattedTotalSize {
    if (totalSize < 1024) return '${totalSize}B';
    if (totalSize < 1024 * 1024) return '${(totalSize / 1024).toStringAsFixed(1)}KB';
    if (totalSize < 1024 * 1024 * 1024) return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}

enum CacheType { thumbnail, image, video, all }