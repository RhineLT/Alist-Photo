import 'dart:io';
import 'dart:convert';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';

class MediaCacheManager {
  static MediaCacheManager? _instance;
  static MediaCacheManager get instance => _instance ??= MediaCacheManager._();
  
  late final CacheManager _thumbnailCache;
  late final CacheManager _originalCache;
  late final CacheManager _videoCache;
  
  // 缓存统计
  final Map<String, CacheAccessInfo> _accessLog = {};
  
  static const String _accessLogKey = 'cache_access_log';
  
  // 提供公共访问器
  CacheManager get thumbnailCache => _thumbnailCache;
  CacheManager get originalCache => _originalCache;
  CacheManager get videoCache => _videoCache;
  
  MediaCacheManager._() {
    _initializeCaches();
    _loadAccessLog();
  }
  
  void _initializeCaches() {
    // 缩略图缓存 - 小文件，长期保存，数量多
    _thumbnailCache = CacheManager(
      Config(
        'alist_thumbnail_cache',
        maxNrOfCacheObjects: 1500, // 保存1500个缩略图
        stalePeriod: const Duration(days: 30), // 30天过期
        repo: JsonCacheInfoRepository(databaseName: 'thumbnail_cache.db'),
        fileService: HttpFileService(),
      ),
    );
    
    // 原图缓存 - 大文件，中期保存
    _originalCache = CacheManager(
      Config(
        'alist_original_cache', 
        maxNrOfCacheObjects: 300, // 保存300个原图
        stalePeriod: const Duration(days: 7), // 7天过期
        repo: JsonCacheInfoRepository(databaseName: 'original_cache.db'),
        fileService: HttpFileService(),
      ),
    );
    
    // 视频缓存 - 超大文件，短期保存
    _videoCache = CacheManager(
      Config(
        'alist_video_cache',
        maxNrOfCacheObjects: 30, // 保存30个视频
        stalePeriod: const Duration(days: 2), // 2天过期
        repo: JsonCacheInfoRepository(databaseName: 'video_cache.db'),
        fileService: HttpFileService(),
      ),
    );
    
    LogService.instance.info('Media cache managers initialized', 'MediaCacheManager');
  }
  
  /// 加载访问日志
  Future<void> _loadAccessLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logData = prefs.getString(_accessLogKey);
      if (logData != null) {
        final Map<String, dynamic> data = jsonDecode(logData);
        data.forEach((key, value) {
          _accessLog[key] = CacheAccessInfo.fromMap(value);
        });
      }
    } catch (e) {
      LogService.instance.error('Failed to load cache access log: $e', 'MediaCacheManager');
    }
  }
  
  /// 保存访问日志
  Future<void> _saveAccessLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _accessLog.map((key, value) => MapEntry(key, value.toMap()));
      await prefs.setString(_accessLogKey, jsonEncode(data));
    } catch (e) {
      LogService.instance.error('Failed to save cache access log: $e', 'MediaCacheManager');
    }
  }
  
  /// 记录文件访问
  void _recordAccess(String url, CacheType type) {
    _accessLog[url] = CacheAccessInfo(
      url: url,
      type: type,
      lastAccessed: DateTime.now(),
      accessCount: (_accessLog[url]?.accessCount ?? 0) + 1,
    );
    
    // 定期清理旧的访问记录
    if (_accessLog.length > 5000) {
      _cleanupOldAccessRecords();
    }
    
    // 异步保存访问日志
    _saveAccessLog();
  }
  
  /// 清理旧的访问记录
  void _cleanupOldAccessRecords() {
    final cutoffDate = DateTime.now().subtract(const Duration(days: 60));
    _accessLog.removeWhere((key, value) => value.lastAccessed.isBefore(cutoffDate));
  }
  
  /// 根据URL获取合适的缓存管理器
  CacheManager getCacheManagerForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return _originalCache;
    
    final path = uri.path.toLowerCase();
    final query = uri.query.toLowerCase();
    
    // 缩略图URL检测
    if (path.contains('thumb') || path.contains('preview') || 
        url.contains('thumbnail') || query.contains('thumb') ||
        query.contains('width') || query.contains('height')) {
      _recordAccess(url, CacheType.thumbnail);
      return _thumbnailCache;
    }
    
    // 视频文件检测
    if (path.endsWith('.mp4') || path.endsWith('.avi') || path.endsWith('.mov') ||
        path.endsWith('.wmv') || path.endsWith('.flv') || path.endsWith('.webm') ||
        path.endsWith('.mkv') || path.endsWith('.m4v') || path.endsWith('.3gp') ||
        path.endsWith('.m3u8') || path.endsWith('.ts')) {
      _recordAccess(url, CacheType.video);
      return _videoCache;
    }
    
    // 默认使用原图缓存
    _recordAccess(url, CacheType.original);
    return _originalCache;
  }
  
  /// 智能预加载 - 根据访问模式预加载相关文件
  Future<void> smartPreload(String currentUrl, List<String> relatedUrls) async {
    try {
      // 首先预加载当前文件的缩略图（如果不同）
      if (!currentUrl.contains('thumb')) {
        final thumbUrl = _generateThumbnailUrl(currentUrl);
        if (thumbUrl != null) {
          preloadFile(thumbUrl, priority: CachePriority.high);
        }
      }
      
      // 预加载相关文件的缩略图（低优先级）
      for (int i = 0; i < relatedUrls.length && i < 10; i++) {
        final relatedUrl = relatedUrls[i];
        final thumbUrl = _generateThumbnailUrl(relatedUrl);
        if (thumbUrl != null) {
          preloadFile(thumbUrl, priority: CachePriority.low);
        }
        
        // 添加延迟以避免网络拥塞
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      LogService.instance.debug('Smart preload completed for ${relatedUrls.length} related files', 'MediaCacheManager');
    } catch (e) {
      LogService.instance.error('Smart preload failed: $e', 'MediaCacheManager');
    }
  }
  
  /// 生成缩略图URL（如果可能）
  String? _generateThumbnailUrl(String originalUrl) {
    try {
      final uri = Uri.parse(originalUrl);
      // 这里应该根据 Alist API 的规则生成缩略图URL
      // 临时实现，实际应该根据 Alist 的 API 文档调整
      if (uri.path.contains('/api/fs/get/')) {
        return originalUrl.replaceFirst('/api/fs/get/', '/api/fs/thumb/');
      }
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// 预加载文件到缓存
  Future<void> preloadFile(String url, {String? cacheKey, CachePriority priority = CachePriority.normal}) async {
    try {
      final cacheManager = getCacheManagerForUrl(url);
      
      // 检查是否已经缓存
      final isCached = await this.isCached(url, cacheKey: cacheKey);
      if (isCached) {
        LogService.instance.debug('File already cached: $url', 'MediaCacheManager');
        return;
      }
      
      // 根据优先级决定是否立即下载
      if (priority == CachePriority.high) {
        await cacheManager.downloadFile(url, key: cacheKey);
        LogService.instance.debug('High priority preload completed: $url', 'MediaCacheManager');
      } else {
        // 低优先级异步下载
        cacheManager.downloadFile(url, key: cacheKey).catchError((e) {
          LogService.instance.warning('Background preload failed: $url, error: $e', 'MediaCacheManager');
          throw e; // 重新抛出错误而不是返回 null
        });
        LogService.instance.debug('Background preload started: $url', 'MediaCacheManager');
      }
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
    try {
      final thumbnailStats = await _getCacheManagerStats(_thumbnailCache, 'thumbnail');
      final originalStats = await _getCacheManagerStats(_originalCache, 'original');
      final videoStats = await _getCacheManagerStats(_videoCache, 'video');
      
      return CacheStats(
        thumbnailCount: thumbnailStats['count'] ?? 0,
        thumbnailSize: thumbnailStats['size'] ?? 0,
        originalCount: originalStats['count'] ?? 0,
        originalSize: originalStats['size'] ?? 0,
        videoCount: videoStats['count'] ?? 0,
        videoSize: videoStats['size'] ?? 0,
      );
    } catch (e) {
      LogService.instance.error('Failed to get cache stats: $e', 'MediaCacheManager');
      return CacheStats(
        thumbnailCount: 0,
        thumbnailSize: 0,
        originalCount: 0,
        originalSize: 0,
        videoCount: 0,
        videoSize: 0,
      );
    }
  }
  
  Future<Map<String, int>> _getCacheManagerStats(CacheManager cacheManager, String type) async {
    try {
      // 简化实现 - 只返回估算值
      return {'count': 0, 'size': 0};
    } catch (e) {
      LogService.instance.warning('Failed to get cache manager stats for $type: $e', 'MediaCacheManager');
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
        case CacheType.original:
          await _originalCache.emptyCache();
          LogService.instance.info('Original image cache cleared', 'MediaCacheManager');
          break;
        case CacheType.video:
          await _videoCache.emptyCache();
          LogService.instance.info('Video cache cleared', 'MediaCacheManager');
          break;
        case CacheType.all:
          await _thumbnailCache.emptyCache();
          await _originalCache.emptyCache();
          await _videoCache.emptyCache();
          _accessLog.clear();
          await _saveAccessLog();
          LogService.instance.info('All caches cleared', 'MediaCacheManager');
          break;
      }
    } catch (e) {
      LogService.instance.error('Failed to clear cache: $e', 'MediaCacheManager');
    }
  }
  
  /// 智能清理缓存 - 基于访问频率和时间
  Future<void> smartCleanup({double targetFreeSpaceRatio = 0.3}) async {
    try {
      LogService.instance.info('Starting smart cache cleanup', 'MediaCacheManager');
      
      // 获取当前缓存统计
      final stats = await getCacheStats();
      final totalSize = stats.totalSize;
      
      if (totalSize == 0) return;
      
      // 按照访问时间排序，删除最久未访问的文件
      final sortedAccess = _accessLog.values.toList()
        ..sort((a, b) => a.lastAccessed.compareTo(b.lastAccessed));
      
      int cleanedSize = 0;
      final targetCleanSize = (totalSize * targetFreeSpaceRatio).round();
      
      for (final accessInfo in sortedAccess) {
        if (cleanedSize >= targetCleanSize) break;
        
        try {
          final cacheManager = _getCacheManagerForType(accessInfo.type);
          await cacheManager.removeFile(accessInfo.url);
          _accessLog.remove(accessInfo.url);
          cleanedSize += 1024 * 1024; // 估算大小
        } catch (e) {
          // 忽略单个文件清理失败
        }
      }
      
      await _saveAccessLog();
      LogService.instance.info('Smart cleanup completed, estimated cleaned size: $cleanedSize bytes', 'MediaCacheManager');
    } catch (e) {
      LogService.instance.error('Smart cleanup failed: $e', 'MediaCacheManager');
    }
  }
  
  CacheManager _getCacheManagerForType(CacheType type) {
    switch (type) {
      case CacheType.thumbnail:
        return _thumbnailCache;
      case CacheType.original:
        return _originalCache;
      case CacheType.video:
        return _videoCache;
      case CacheType.all:
        return _originalCache; // 默认
    }
  }
  
  /// 获取最常访问的文件
  List<CacheAccessInfo> getMostAccessedFiles({int limit = 20}) {
    final sortedByAccess = _accessLog.values.toList()
      ..sort((a, b) => b.accessCount.compareTo(a.accessCount));
    
    return sortedByAccess.take(limit).toList();
  }
  
  /// 获取最近访问的文件
  List<CacheAccessInfo> getRecentlyAccessedFiles({int limit = 20}) {
    final sortedByTime = _accessLog.values.toList()
      ..sort((a, b) => b.lastAccessed.compareTo(a.lastAccessed));
    
    return sortedByTime.take(limit).toList();
  }
}

class CacheStats {
  final int thumbnailCount;
  final int thumbnailSize;
  final int originalCount;
  final int originalSize;
  final int videoCount;
  final int videoSize;
  
  CacheStats({
    required this.thumbnailCount,
    required this.thumbnailSize,
    required this.originalCount,
    required this.originalSize,
    required this.videoCount,
    required this.videoSize,
  });
  
  int get totalCount => thumbnailCount + originalCount + videoCount;
  int get totalSize => thumbnailSize + originalSize + videoSize;
  
  String get formattedTotalSize {
    if (totalSize < 1024) return '${totalSize}B';
    if (totalSize < 1024 * 1024) return '${(totalSize / 1024).toStringAsFixed(1)}KB';
    if (totalSize < 1024 * 1024 * 1024) return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
  
  String formatSize(int sizeInBytes) {
    if (sizeInBytes < 1024) return '${sizeInBytes}B';
    if (sizeInBytes < 1024 * 1024) return '${(sizeInBytes / 1024).toStringAsFixed(1)}KB';
    if (sizeInBytes < 1024 * 1024 * 1024) return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}

class CacheAccessInfo {
  final String url;
  final CacheType type;
  final DateTime lastAccessed;
  final int accessCount;
  
  CacheAccessInfo({
    required this.url,
    required this.type,
    required this.lastAccessed,
    required this.accessCount,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'type': type.index,
      'lastAccessed': lastAccessed.millisecondsSinceEpoch,
      'accessCount': accessCount,
    };
  }
  
  factory CacheAccessInfo.fromMap(Map<String, dynamic> map) {
    return CacheAccessInfo(
      url: map['url'] ?? '',
      type: CacheType.values[map['type'] ?? 0],
      lastAccessed: DateTime.fromMillisecondsSinceEpoch(map['lastAccessed'] ?? 0),
      accessCount: map['accessCount'] ?? 0,
    );
  }
}

enum CacheType { thumbnail, original, video, all }

enum CachePriority { low, normal, high }