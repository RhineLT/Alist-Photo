import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'alist_api_client.dart';
import 'log_service.dart';

enum UploadStatus { pending, uploading, paused, completed, failed, cancelled }

class UploadTask {
  final String id;
  final String fileName;
  final String filePath;
  final String targetPath;
  final int fileSize;
  UploadStatus status;
  double progress;
  String? error;
  CancelToken? cancelToken;
  int retryCount;
  
  UploadTask({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.targetPath,
    required this.fileSize,
    this.status = UploadStatus.pending,
    this.progress = 0.0,
    this.error,
    this.retryCount = 0,
  });
  
  String get formattedSize {
    if (fileSize < 1024) return '${fileSize}B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    if (fileSize < 1024 * 1024 * 1024) return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}

class FileUploadService {
  static const int maxRetries = 3;
  static const int chunkSize = 1024 * 1024; // 1MB chunks for large files
  
  final AlistApiClient _apiClient;
  final List<UploadTask> _uploadTasks = [];
  final Map<String, Function(UploadTask)> _progressCallbacks = {};
  final Map<String, Function(UploadTask)> _statusCallbacks = {};
  
  FileUploadService(this._apiClient);
  
  List<UploadTask> get uploadTasks => List.unmodifiable(_uploadTasks);
  
  void addProgressCallback(String taskId, Function(UploadTask) callback) {
    _progressCallbacks[taskId] = callback;
  }
  
  void addStatusCallback(String taskId, Function(UploadTask) callback) {
    _statusCallbacks[taskId] = callback;
  }
  
  void removeCallbacks(String taskId) {
    _progressCallbacks.remove(taskId);
    _statusCallbacks.remove(taskId);
  }
  
  String addUploadTask({
    required String filePath,
    required String targetPath,
  }) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('File does not exist: $filePath');
    }
    
    final task = UploadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: path.basename(filePath),
      filePath: filePath,
      targetPath: targetPath,
      fileSize: file.lengthSync(),
    );
    
    _uploadTasks.add(task);
    LogService.instance.info('Added upload task: ${task.fileName}', 'FileUploadService', {
      'task_id': task.id,
      'file_size': task.fileSize,
      'target_path': targetPath,
    });
    
    return task.id;
  }
  
  Future<void> startUpload(String taskId) async {
    final task = _uploadTasks.firstWhere((t) => t.id == taskId);
    
    if (task.status == UploadStatus.uploading) {
      LogService.instance.warning('Task already uploading: $taskId', 'FileUploadService');
      return;
    }
    
    task.status = UploadStatus.uploading;
    task.cancelToken = CancelToken();
    _notifyStatusCallback(task);
    
    try {
      await _performUpload(task);
    } catch (e) {
      if (!task.cancelToken!.isCancelled) {
        task.status = UploadStatus.failed;
        task.error = e.toString();
        LogService.instance.error('Upload failed: ${task.fileName}, error: $e', 'FileUploadService');
        
        // 自动重试
        if (task.retryCount < maxRetries) {
          task.retryCount++;
          LogService.instance.info('Retrying upload (${task.retryCount}/$maxRetries): ${task.fileName}', 'FileUploadService');
          await Future.delayed(Duration(seconds: task.retryCount * 2));
          if (task.status != UploadStatus.cancelled) {
            await startUpload(taskId);
          }
          return;
        }
      }
    }
    
    _notifyStatusCallback(task);
  }
  
  Future<void> _performUpload(UploadTask task) async {
    final file = File(task.filePath);
    final bytes = await file.readAsBytes();
    final targetFilePath = '${task.targetPath.endsWith('/') ? task.targetPath : '${task.targetPath}/'}${task.fileName}';
    
    LogService.instance.info('Starting upload: ${task.fileName}', 'FileUploadService', {
      'target_path': targetFilePath,
      'file_size': task.fileSize,
    });
    
    final dio = Dio();
    
    // 配置请求头
    final headers = <String, String>{
      'Authorization': await _apiClient.getAuthorizationHeader(),
      'File-Path': Uri.encodeComponent(targetFilePath),
      'Content-Type': 'application/octet-stream',
      'Content-Length': task.fileSize.toString(),
    };
    
    // 如果文件较大，考虑添加As-Task头
    if (task.fileSize > 10 * 1024 * 1024) { // 10MB
      headers['As-Task'] = 'true';
    }
    
    try {
      final response = await dio.put(
        '${_apiClient.serverUrl}/api/fs/put',
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: headers,
          validateStatus: (status) => status! < 400,
        ),
        cancelToken: task.cancelToken,
        onSendProgress: (int sent, int total) {
          task.progress = sent / total;
          _notifyProgressCallback(task);
        },
      );
      
      if (response.statusCode == 200) {
        task.status = UploadStatus.completed;
        task.progress = 1.0;
        LogService.instance.info('Upload completed: ${task.fileName}', 'FileUploadService');
      } else {
        throw Exception('Upload failed with status: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        task.status = UploadStatus.cancelled;
        LogService.instance.info('Upload cancelled: ${task.fileName}', 'FileUploadService');
      } else {
        throw Exception('Network error: ${e.message}');
      }
    }
  }
  
  void pauseUpload(String taskId) {
    final task = _uploadTasks.firstWhere((t) => t.id == taskId);
    if (task.status == UploadStatus.uploading) {
      task.cancelToken?.cancel();
      task.status = UploadStatus.paused;
      _notifyStatusCallback(task);
      LogService.instance.info('Upload paused: ${task.fileName}', 'FileUploadService');
    }
  }
  
  void resumeUpload(String taskId) {
    final task = _uploadTasks.firstWhere((t) => t.id == taskId);
    if (task.status == UploadStatus.paused) {
      startUpload(taskId);
    }
  }
  
  void cancelUpload(String taskId) {
    final task = _uploadTasks.firstWhere((t) => t.id == taskId);
    task.cancelToken?.cancel();
    task.status = UploadStatus.cancelled;
    _notifyStatusCallback(task);
    LogService.instance.info('Upload cancelled: ${task.fileName}', 'FileUploadService');
  }
  
  void removeUploadTask(String taskId) {
    _uploadTasks.removeWhere((t) => t.id == taskId);
    removeCallbacks(taskId);
  }
  
  void clearCompletedTasks() {
    _uploadTasks.removeWhere((t) => 
      t.status == UploadStatus.completed || 
      t.status == UploadStatus.cancelled
    );
  }
  
  Future<void> startAllUploads() async {
    final pendingTasks = _uploadTasks.where((t) => 
      t.status == UploadStatus.pending || 
      t.status == UploadStatus.paused
    ).toList();
    
    for (final task in pendingTasks) {
      if (task.status != UploadStatus.cancelled) {
        startUpload(task.id);
        // 添加小延迟避免同时启动太多上传
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }
  
  void pauseAllUploads() {
    final uploadingTasks = _uploadTasks.where((t) => 
      t.status == UploadStatus.uploading
    ).toList();
    
    for (final task in uploadingTasks) {
      pauseUpload(task.id);
    }
  }
  
  void _notifyProgressCallback(UploadTask task) {
    _progressCallbacks[task.id]?.call(task);
  }
  
  void _notifyStatusCallback(UploadTask task) {
    _statusCallbacks[task.id]?.call(task);
  }
  
  int get pendingCount => _uploadTasks.where((t) => t.status == UploadStatus.pending).length;
  int get uploadingCount => _uploadTasks.where((t) => t.status == UploadStatus.uploading).length;
  int get completedCount => _uploadTasks.where((t) => t.status == UploadStatus.completed).length;
  int get failedCount => _uploadTasks.where((t) => t.status == UploadStatus.failed).length;
}