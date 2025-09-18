import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/alist_api_client.dart';
import 'log_service.dart';

/// 外部文件缓存管理：
/// - 舍弃哈希文件名，完全按 Alist 的 fs 路径映射
/// - Android: /storage/emulated/0/Android/data/<package>/cache/{thumbnail|original|video}/<alist_path>
/// - iOS/桌面: 临时/应用支持目录下同样的子目录结构
class MediaCacheManager {
  MediaCacheManager._internal();
  static MediaCacheManager? _instance;
  static MediaCacheManager get instance => _instance ??= MediaCacheManager._internal();

  // 目录名
  static const String _thumbnailDir = 'thumbnail';
  static const String _originalDir = 'original';
  static const String _videoDir = 'video';

  // 偏好键
  static const String _prefsKeyMaxBytes = 'media_cache_max_bytes';
  static const String _prefsKeyCleanupIntervalSec = 'media_cache_cleanup_interval_sec';

  // 默认：最大 8GB，总是允许临时超过
  int _maxCacheBytes = 8 * 1024 * 1024 * 1024;
  Duration _cleanupInterval = const Duration(minutes: 30);

  Directory? _baseCacheDir; // /.../Android/data/<package>/cache
  final Dio _dio = Dio();
  Timer? _cleanupTimer;
  // 全局下载并发限制
  static const int _globalMaxConcurrent = 7;
  int _inflight = 0;
  final List<Completer<void>> _waiters = [];

  Future<T> _withThrottle<T>(Future<T> Function() action) async {
    if (_inflight >= _globalMaxConcurrent) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _inflight++;
    try {
      return await action();
    } finally {
      _inflight--;
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      }
    }
  }

  Future<void> initialize() async {
    await _loadSettings();
    await ensurePermissions();
    _baseCacheDir = await _resolveBaseCacheDir();
    await _ensureSubDirs();
    _startPeriodicCleanup();
    LogService.instance.info('MediaCacheManager initialized at: ${_baseCacheDir?.path}', 'MediaCacheManager');
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _maxCacheBytes = prefs.getInt(_prefsKeyMaxBytes) ?? _maxCacheBytes;
      final sec = prefs.getInt(_prefsKeyCleanupIntervalSec);
      if (sec != null) _cleanupInterval = Duration(seconds: sec);
    } catch (e) {
      LogService.instance.warning('Load cache settings failed: $e', 'MediaCacheManager');
    }
  }

  Future<void> setMaxCacheBytes(int bytes) async {
    _maxCacheBytes = bytes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyMaxBytes, bytes);
  }

  Future<Directory> _resolveBaseCacheDir() async {
    if (Platform.isAndroid) {
      // 使用应用专属外部缓存目录，符合 /storage/emulated/0/Android/data/<package>/cache
      final dir = await getExternalCacheDirectories();
      final Directory base = (dir != null && dir.isNotEmpty) ? dir.first : await getTemporaryDirectory();
      return base;
    } else if (Platform.isIOS) {
      return await getTemporaryDirectory();
    } else {
      return await getTemporaryDirectory();
    }
  }

  Future<void> _ensureSubDirs() async {
    if (_baseCacheDir == null) return;
    for (final name in [_thumbnailDir, _originalDir, _videoDir]) {
      final d = Directory(p.join(_baseCacheDir!.path, name));
      if (!await d.exists()) {
        await d.create(recursive: true);
      }
    }
  }

  void _startPeriodicCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _cleanupIfNeeded());
  }

  Future<bool> ensurePermissions() async {
    // 写入应用专属外部缓存目录，一般无需权限；按需求仍申请最低必要权限
    try {
      if (!Platform.isAndroid) return true;
      final sdkInt = await _getAndroidSdkInt();
      if (sdkInt <= 29) {
        final status = await Permission.storage.request();
        return status.isGranted;
      }
      // Android 11+ 对应用专属目录不需要权限
      return true;
    } catch (e) {
      LogService.instance.warning('ensurePermissions failed: $e', 'MediaCacheManager');
      return true;
    }
  }

  Future<int> _getAndroidSdkInt() async {
    try {
      // 默认返回 30，权限最小化（应用专属目录通常不需要权限）
      return 30;
    } catch (_) {
      return 30;
    }
  }

  // 将 Alist 的文件（含 path/name）映射为缓存内路径
  String _alistRelativePath(AlistFile file) {
    // 构造严格的“相对路径”：移除 file.path 中的前导斜杠并按段拼接
    final rawPath = file.path;
    final segments = <String>[];
    if (rawPath.isNotEmpty) {
      for (final part in rawPath.split('/')) {
        if (part.isNotEmpty && part != '.' && part != '..') segments.add(part);
      }
    }
    if (file.name.isNotEmpty) segments.add(file.name);
    final rel = p.joinAll(segments);
    return rel; // 无前导分隔符，确保为相对路径
  }

  File _fileFor(CacheType type, String alistRelativePath) {
    final subDir = switch (type) {
      CacheType.thumbnail => _thumbnailDir,
      CacheType.original => _originalDir,
      CacheType.video => _videoDir,
      CacheType.all => _originalDir,
    };
    final safeRel = _ensureRelative(alistRelativePath);
    final fullPath = p.join(_baseCacheDir!.path, subDir, safeRel);
    return File(fullPath);
  }

  // 确保传入的 alistRelativePath 不会是绝对路径，且移除危险段（., ..）
  String _ensureRelative(String input) {
    var normalized = p.normalize(input);
    // 去除可能的前导分隔符（避免 p.join 被覆盖）
    while (normalized.startsWith('/') || normalized.startsWith('\\')) {
      normalized = normalized.substring(1);
    }
    // 丢弃 . 与 .. 段，避免路径逃逸
    final parts = p
        .split(normalized)
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .toList(growable: false);
    return p.joinAll(parts);
  }

  Future<File?> _downloadTo(File dest, String url) async {
    return _withThrottle<File?>(() async {
      try {
        await dest.parent.create(recursive: true);
        final tmp = File('${dest.path}.part');
        if (await tmp.exists()) await tmp.delete();
        await _dio.download(url, tmp.path);
        if (await dest.exists()) await dest.delete();
        await tmp.rename(dest.path);
        return dest;
      } catch (e) {
        LogService.instance.error('Download failed: $url -> ${dest.path}, error: $e', 'MediaCacheManager');
        return null;
      } finally {
        // 清理（若存在）
        final tmp = File('${dest.path}.part');
        if (await tmp.exists()) {
          try { await tmp.delete(); } catch (_) {}
        }
        // 下载后尝试清理容量
        unawaited(_cleanupIfNeeded());
      }
    });
  }

  Future<void> _touch(File f) async {
    try { await f.setLastModified(DateTime.now()); } catch (_) {}
  }

  // 对外：仅检查是否已有本地缩略图
  Future<File?> getLocalThumbnail(AlistFile file) async {
    await initializeIfNeeded();
    final rel = _alistRelativePath(file);
    final f = _fileFor(CacheType.thumbnail, rel);
    if (await f.exists()) {
      await _touch(f);
      LogService.instance.debug('Thumbnail cache hit: ${f.path}', 'MediaCacheManager', {
        'file': file.name,
        'path': file.path,
      });
      return f;
    }
    LogService.instance.debug('Thumbnail cache miss', 'MediaCacheManager', {
      'file': file.name,
      'path': file.path,
    });
    return null;
  }

  Future<File?> getLocalOriginal(AlistFile file) async {
    await initializeIfNeeded();
    final rel = _alistRelativePath(file);
    final f = _fileFor(CacheType.original, rel);
    if (await f.exists()) {
      await _touch(f);
      LogService.instance.debug('Original cache hit: ${f.path}', 'MediaCacheManager', {
        'file': file.name,
        'path': file.path,
      });
      return f;
    }
    LogService.instance.debug('Original cache miss', 'MediaCacheManager', {
      'file': file.name,
      'path': file.path,
    });
    return null;
  }

  Future<void> initializeIfNeeded() async {
    if (_baseCacheDir == null) {
      await initialize();
    }
  }

  // 获取或下载缩略图
  Future<File?> getOrFetchThumbnail(AlistApiClient api, AlistFile file) async {
    await initializeIfNeeded();
    final existing = await getLocalThumbnail(file);
    if (existing != null) return existing;
    final url = api.getThumbnailUrl(file);
    if (url == null) return null;
    final rel = _alistRelativePath(file);
    final dest = _fileFor(CacheType.thumbnail, rel);
    LogService.instance.info('Downloading thumbnail', 'MediaCacheManager', {
      'url': url,
      'dest': dest.path,
    });
    final res = await _downloadTo(dest, url);
    if (res != null) {
      LogService.instance.info('Thumbnail downloaded', 'MediaCacheManager', {
        'dest': res.path,
      });
    }
    return res;
  }

  // 获取或下载原图
  Future<File?> getOrFetchOriginal(AlistApiClient api, AlistFile file) async {
    await initializeIfNeeded();
    final existing = await getLocalOriginal(file);
    if (existing != null) return existing;
    final url = await api.getDownloadUrl(file);
    final rel = _alistRelativePath(file);
    final dest = _fileFor(CacheType.original, rel);
    LogService.instance.info('Downloading original', 'MediaCacheManager', {
      'url': url,
      'dest': dest.path,
    });
    final res = await _downloadTo(dest, url);
    if (res != null) {
      LogService.instance.info('Original downloaded', 'MediaCacheManager', {
        'dest': res.path,
      });
    }
    return res;
  }

  // 批量预加载指定目录下文件的缩略图
  Future<void> preloadThumbnails(AlistApiClient api, List<AlistFile> files, {int maxConcurrent = 7}) async {
    await initializeIfNeeded();
    final queue = <Future>[];
    for (final f in files) {
      if (f.isDir) continue;
      final url = api.getThumbnailUrl(f);
      if (url == null) continue;
      final rel = _alistRelativePath(f);
      final dest = _fileFor(CacheType.thumbnail, rel);
      if (await dest.exists()) continue;

      // 控制并发：达上限则等待任一完成，完成后在回调中剔除
      if (queue.length >= maxConcurrent) {
        await Future.any(queue);
      }
      final fut = _downloadTo(dest, url);
      queue.add(fut);
      fut.whenComplete(() {
        queue.remove(fut);
      });
      // 轻微错峰
      await Future.delayed(const Duration(milliseconds: 50));
    }
    await Future.wait(queue);
  }

  // 同步缓存目录结构，与 Alist 目录保持一致（仅创建目录，不创建文件）
  Future<void> syncDirectoryStructure(String path, List<AlistFile> files) async {
    await initializeIfNeeded();
    final safePath = _ensureRelative(path.startsWith('/') ? path.substring(1) : path);
    final dirsToEnsure = <String>{safePath};
    for (final f in files) {
      if (f.isDir) {
        final child = safePath.isEmpty ? f.name : p.join(safePath, f.name);
        dirsToEnsure.add(child);
      }
    }

    for (final rel in dirsToEnsure) {
      for (final type in [CacheType.thumbnail, CacheType.original, CacheType.video]) {
        final d = Directory(p.join(_baseCacheDir!.path, switch (type) {
          CacheType.thumbnail => _thumbnailDir,
          CacheType.original => _originalDir,
          CacheType.video => _videoDir,
          CacheType.all => _originalDir,
        }, rel));
        try { if (!await d.exists()) { await d.create(recursive: true); } } catch (_) {}
      }
    }
  }

  // 统计与清理
  Future<int> _dirSize(Directory dir) async {
    int total = 0;
    if (!await dir.exists()) return 0;
    try {
      await for (final ent in dir.list(recursive: true, followLinks: false)) {
        if (ent is File) {
          final stat = await ent.stat();
          total += stat.size;
        }
      }
    } catch (e) {
      LogService.instance.warning('dirSize failed: $e', 'MediaCacheManager');
    }
    return total;
  }

  Future<CacheStats> getCacheStats() async {
    await initializeIfNeeded();
    final thumbDir = Directory(p.join(_baseCacheDir!.path, _thumbnailDir));
    final origDir = Directory(p.join(_baseCacheDir!.path, _originalDir));
    final videoDir = Directory(p.join(_baseCacheDir!.path, _videoDir));

    // 仅统计大小；数量统计代价较高，简单遍历
    int tSize = await _dirSize(thumbDir);
    int oSize = await _dirSize(origDir);
    int vSize = await _dirSize(videoDir);
    return CacheStats(
      thumbnailCount: await _countFiles(thumbDir),
      thumbnailSize: tSize,
      originalCount: await _countFiles(origDir),
      originalSize: oSize,
      videoCount: await _countFiles(videoDir),
      videoSize: vSize,
    );
  }

  Future<int> _countFiles(Directory dir) async {
    if (!await dir.exists()) return 0;
    int c = 0;
    await for (final ent in dir.list(recursive: true, followLinks: false)) {
      if (ent is File) c++;
    }
    return c;
  }

  Future<void> clearCache(CacheType type) async {
    await initializeIfNeeded();
    Future<void> clearDir(Directory d) async {
      if (!await d.exists()) return;
      try { await d.delete(recursive: true); } catch (_) {}
      try { await d.create(recursive: true); } catch (_) {}
    }

    switch (type) {
      case CacheType.thumbnail:
        await clearDir(Directory(p.join(_baseCacheDir!.path, _thumbnailDir)));
        break;
      case CacheType.original:
        await clearDir(Directory(p.join(_baseCacheDir!.path, _originalDir)));
        break;
      case CacheType.video:
        await clearDir(Directory(p.join(_baseCacheDir!.path, _videoDir)));
        break;
      case CacheType.all:
        await clearDir(Directory(p.join(_baseCacheDir!.path, _thumbnailDir)));
        await clearDir(Directory(p.join(_baseCacheDir!.path, _originalDir)));
        await clearDir(Directory(p.join(_baseCacheDir!.path, _videoDir)));
        break;
    }
    LogService.instance.info('Cache cleared for $type', 'MediaCacheManager');
  }

  Future<void> _cleanupIfNeeded() async {
    try {
      await initializeIfNeeded();
      final base = _baseCacheDir!;
      final currentSize = await _dirSize(base);
      if (currentSize <= _maxCacheBytes) return;

      // 收集所有文件，按最后修改时间从旧到新清理
      final files = <File>[];
      await for (final ent in base.list(recursive: true, followLinks: false)) {
        if (ent is File && !ent.path.endsWith('.part')) files.add(ent);
      }

      // 因为 lastModified 是异步，先同步获取时间戳后再排序
      final fileWithTime = <MapEntry<File, DateTime>>[];
      for (final f in files) {
        try {
          final stat = await f.stat();
          fileWithTime.add(MapEntry(f, stat.modified));
        } catch (_) {}
      }
      fileWithTime.sort((a, b) => a.value.compareTo(b.value));

      int freed = 0;
      for (final entry in fileWithTime) {
        if (currentSize - freed <= _maxCacheBytes) break;
        try {
          final stat = await entry.key.stat();
          await entry.key.delete();
          freed += stat.size;
        } catch (_) {}
      }

  LogService.instance.info('Cleanup freed ~$freed bytes (target max: $_maxCacheBytes)', 'MediaCacheManager');
    } catch (e) {
      LogService.instance.warning('Cleanup failed: $e', 'MediaCacheManager');
    }
  }

  // 无额外比较函数（已用同步时间戳排序）
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

enum CacheType { thumbnail, original, video, all }