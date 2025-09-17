import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'log_service.dart';

class FileDownloadService {
  static final FileDownloadService _instance = FileDownloadService._internal();
  factory FileDownloadService() => _instance;
  FileDownloadService._internal();

  static FileDownloadService get instance => _instance;

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

  // 获取下载目录
  Future<String> getDownloadDirectory() async {
    if (Platform.isAndroid) {
      // Android 使用公共下载目录
      final directory = Directory('/storage/emulated/0/Download/AlistPhoto');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        LogService.instance.info('Created download directory: ${directory.path}', 'FileDownloadService');
      }
      return directory.path;
    } else {
      // iOS 使用应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${directory.path}/Downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
        LogService.instance.info('Created download directory: ${downloadDir.path}', 'FileDownloadService');
      }
      return downloadDir.path;
    }
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