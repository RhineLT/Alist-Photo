import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';

class FileDownloadService {
  static final FileDownloadService _instance = FileDownloadService._internal();
  factory FileDownloadService() => _instance;
  FileDownloadService._internal();

  static FileDownloadService get instance => _instance;
  static const String _downloadPathKey = 'download_path';

  final Dio _dio = Dio();

  // 请求存储权限
  Future<bool> requestStoragePermission() async {
    LogService.instance.info('Requesting storage permission', 'FileDownloadService');
    
    if (Platform.isAndroid) {
      final deviceInfo = await _getAndroidVersion();
      
      if (deviceInfo >= 33) {
        // Android 13+ 使用新的权限模型
        final status = await Permission.photos.request();
        if (status.isGranted) {
          LogService.instance.info('Photos permission granted', 'FileDownloadService');
          return true;
        } else {
          LogService.instance.warning('Photos permission denied', 'FileDownloadService');
          return false;
        }
      } else if (deviceInfo >= 30) {
        // Android 11-12 使用 MANAGE_EXTERNAL_STORAGE
        final status = await Permission.manageExternalStorage.request();
        if (status.isGranted) {
          LogService.instance.info('Manage external storage permission granted', 'FileDownloadService');
          return true;
        } else {
          LogService.instance.warning('Manage external storage permission denied', 'FileDownloadService');
          return false;
        }
      } else {
        // Android 10 及以下使用传统权限
        final status = await Permission.storage.request();
        if (status.isGranted) {
          LogService.instance.info('Storage permission granted', 'FileDownloadService');
          return true;
        } else {
          LogService.instance.warning('Storage permission denied', 'FileDownloadService');
          return false;
        }
      }
    } else {
      // iOS 不需要额外权限
      return true;
    }
  }

  // 获取 Android 版本
  Future<int> _getAndroidVersion() async {
    if (Platform.isAndroid) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.version.sdkInt;
      } catch (e) {
        LogService.instance.warning('Failed to get Android version: $e', 'FileDownloadService');
        return 30; // 默认使用 Android 11 的权限模型
      }
    }
    return 0;
  }

  // 获取默认下载目录
  Future<String> _getDefaultDownloadDirectory() async {
    if (Platform.isAndroid) {
      // Android 使用公共下载目录
      return '/storage/emulated/0/Download/AlistPhoto';
    } else {
      // iOS 使用应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      return '${directory.path}/Downloads';
    }
  }
  
  // 获取下载目录（从设置中读取或使用默认值）
  Future<String> getDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    String? customPath = prefs.getString(_downloadPathKey);
    
    if (customPath == null || customPath.isEmpty) {
      customPath = await _getDefaultDownloadDirectory();
    }
    
    // 确保目录存在
    final directory = Directory(customPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      LogService.instance.info('Created download directory: ${directory.path}', 'FileDownloadService');
    }
    
    return directory.path;
  }
  
  // 设置自定义下载路径
  Future<bool> setDownloadDirectory(String path) async {
    try {
      // 验证路径
      final directory = Directory(path);
      
      // 尝试创建目录
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      // 测试是否有写入权限
      final testFile = File('${directory.path}/.test');
      await testFile.writeAsString('test');
      await testFile.delete();
      
      // 保存路径
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_downloadPathKey, path);
      
      LogService.instance.info('Download directory set to: $path', 'FileDownloadService');
      return true;
    } catch (e) {
      LogService.instance.error('Failed to set download directory: $e', 'FileDownloadService');
      return false;
    }
  }
  
  // 重置为默认下载路径
  Future<void> resetDownloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_downloadPathKey);
    LogService.instance.info('Download directory reset to default', 'FileDownloadService');
  }

  // 下载文件
  Future<String?> downloadFile({
    required String url,
    required String fileName,
    Function(int received, int total)? onProgress,
  }) async {
    try {
      LogService.instance.info('Starting download: $fileName', 'FileDownloadService', {
        'url': url,
        'file_name': fileName,
      });

      // 检查权限
      final hasPermission = await requestStoragePermission();
      if (!hasPermission) {
        LogService.instance.error('Storage permission required for download', 'FileDownloadService');
        return null;
      }

      // 获取下载目录
      final downloadPath = await getDownloadDirectory();
      final filePath = '$downloadPath/$fileName';

      LogService.instance.debug('Download path: $filePath', 'FileDownloadService');

      // 检查文件是否已存在
      final file = File(filePath);
      if (await file.exists()) {
        // 生成新文件名
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final parts = fileName.split('.');
        final name = parts.take(parts.length - 1).join('.');
        final ext = parts.last;
        final newFileName = '${name}_$timestamp.$ext';
        final newFilePath = '$downloadPath/$newFileName';
        
        LogService.instance.info('File exists, using new name: $newFileName', 'FileDownloadService');
        
        await _dio.download(
          url,
          newFilePath,
          onReceiveProgress: onProgress,
        );
        
        LogService.instance.info('Download completed: $newFileName', 'FileDownloadService');
        return newFilePath;
      } else {
        await _dio.download(
          url,
          filePath,
          onReceiveProgress: onProgress,
        );
        
        LogService.instance.info('Download completed: $fileName', 'FileDownloadService');
        return filePath;
      }
    } catch (e) {
      LogService.instance.error('Download failed: $e', 'FileDownloadService', {
        'url': url,
        'file_name': fileName,
      });
      return null;
    }
  }

  // 获取文件大小（用于显示下载进度）
  Future<int?> getFileSize(String url) async {
    try {
      final response = await _dio.head(url);
      final contentLength = response.headers.value('content-length');
      if (contentLength != null) {
        return int.tryParse(contentLength);
      }
    } catch (e) {
      LogService.instance.warning('Failed to get file size: $e', 'FileDownloadService');
    }
    return null;
  }
}