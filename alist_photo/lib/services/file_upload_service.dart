import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
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
  DateTime createdAt;
  DateTime? startedAt;
  DateTime? completedAt;
  
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
  }) : createdAt = DateTime.now();
  
  String get formattedSize {
    if (fileSize < 1024) return '${fileSize}B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    if (fileSize < 1024 * 1024 * 1024) return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
  
  String get statusText {
    switch (status) {
      case UploadStatus.pending:
        return '等待中';
      case UploadStatus.uploading:
        return '上传中 ${(progress * 100).toStringAsFixed(0)}%';
      case UploadStatus.paused:
        return '已暂停';
      case UploadStatus.completed:
        return '已完成';
      case UploadStatus.failed:
        return '失败${retryCount > 0 ? ' (重试 $retryCount/${FileUploadService.maxRetries})' : ''}';
      case UploadStatus.cancelled:
        return '已取消';
    }
  }
}

class FileUploadService extends ChangeNotifier {
  static const int maxRetries = 3;
  static const int maxConcurrentUploads = 3;
  static const int chunkSize = 1024 * 1024; // 1MB chunks for large files
  
  final AlistApiClient _apiClient;
  final List<UploadTask> _uploadTasks = [];
  int _activeUploads = 0;
  
  FileUploadService(this._apiClient);
  
  List<UploadTask> get uploadTasks => List.unmodifiable(_uploadTasks);
  
  // 统计信息
  int get pendingCount => _uploadTasks.where((t) => t.status == UploadStatus.pending).length;
  int get uploadingCount => _uploadTasks.where((t) => t.status == UploadStatus.uploading).length;
  int get completedCount => _uploadTasks.where((t) => t.status == UploadStatus.completed).length;
  int get failedCount => _uploadTasks.where((t) => t.status == UploadStatus.failed).length;
  int get pausedCount => _uploadTasks.where((t) => t.status == UploadStatus.paused).length;
  
  bool get hasActiveUploads => _activeUploads > 0;
  
  // 批量添加上传任务
  List<String> addUploadTasks(List<String> filePaths, String targetPath) {
    final taskIds = <String>[];
    
    for (final filePath in filePaths) {
      try {
        final taskId = addUploadTask(filePath: filePath, targetPath: targetPath);
        taskIds.add(taskId);
      } catch (e) {
        LogService.instance.error('Failed to add upload task for $filePath: $e', 'FileUploadService');
      }
    }
    
    LogService.instance.info('Added ${taskIds.length} upload tasks', 'FileUploadService');
    return taskIds;
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
      id: '${DateTime.now().millisecondsSinceEpoch}_${_uploadTasks.length}',
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
    
    notifyListeners();
    return task.id;
  }
  
  /// 添加进度回调
  void addProgressCallback(String taskId, Function(UploadTask) callback) {
    // 使用ChangeNotifier模式，回调通过notifyListeners触发
    // UI层可以监听整个服务的变化
  }
  
  /// 添加状态回调
  void addStatusCallback(String taskId, Function(UploadTask) callback) {
    // 使用ChangeNotifier模式，回调通过notifyListeners触发
    // UI层可以监听整个服务的变化
  }
  
  Future<void> startUpload(String taskId) async {
    final taskIndex = _uploadTasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    
    final task = _uploadTasks[taskIndex];
    
    if (task.status == UploadStatus.uploading) {
      LogService.instance.warning('Task already uploading: $taskId', 'FileUploadService');
      return;
    }
    
    // 检查并发限制
    if (_activeUploads >= maxConcurrentUploads) {
      LogService.instance.info('Max concurrent uploads reached, queuing task: ${task.fileName}', 'FileUploadService');
      task.status = UploadStatus.pending;
      notifyListeners();
      return;
    }
    
    task.status = UploadStatus.uploading;
    task.startedAt = DateTime.now();
    task.cancelToken = CancelToken();
    task.error = null;
    _activeUploads++;
    
    notifyListeners();
    
    try {
      await _performUpload(task);
      task.completedAt = DateTime.now();
    } catch (e) {
      if (!task.cancelToken!.isCancelled) {
        task.status = UploadStatus.failed;
        task.error = e.toString();
        LogService.instance.error('Upload failed: ${task.fileName}, error: $e', 'FileUploadService');
        
        // 自动重试
        if (task.retryCount < maxRetries) {
          task.retryCount++;
          LogService.instance.info('Scheduling retry (${task.retryCount}/$maxRetries): ${task.fileName}', 'FileUploadService');
          
          // 延迟重试
          Future.delayed(Duration(seconds: task.retryCount * 2), () {
            if (task.status == UploadStatus.failed && task.retryCount <= maxRetries) {
              task.status = UploadStatus.pending;
              startUpload(taskId);
            }
          });
        }
      }
    } finally {
      _activeUploads--;
      notifyListeners();
      
      // 启动下一个待上传的任务
      _processQueue();
    }
  }
  
  void _processQueue() {
    if (_activeUploads < maxConcurrentUploads) {
      final nextTask = _uploadTasks.where((t) => t.status == UploadStatus.pending).take(1).toList();
      if (nextTask.isNotEmpty) {
        startUpload(nextTask.first.id);
      }
    }
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
    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.sendTimeout = const Duration(minutes: 10);
    dio.options.receiveTimeout = const Duration(seconds: 30);
    
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
          if (total > 0) {
            task.progress = sent / total;
            notifyListeners();
          }
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
    final taskIndex = _uploadTasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    
    final task = _uploadTasks[taskIndex];
    if (task.status == UploadStatus.uploading) {
      task.cancelToken?.cancel();
      task.status = UploadStatus.paused;
      _activeUploads--;
      notifyListeners();
      LogService.instance.info('Upload paused: ${task.fileName}', 'FileUploadService');
      
      // 处理队列中的下一个任务
      _processQueue();
    }
  }
  
  void resumeUpload(String taskId) {
    final taskIndex = _uploadTasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    
    final task = _uploadTasks[taskIndex];
    if (task.status == UploadStatus.paused) {
      task.status = UploadStatus.pending;
      startUpload(taskId);
    }
  }
  
  void cancelUpload(String taskId) {
    final taskIndex = _uploadTasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    
    final task = _uploadTasks[taskIndex];
    if (task.status == UploadStatus.uploading) {
      _activeUploads--;
    }
    
    task.cancelToken?.cancel();
    task.status = UploadStatus.cancelled;
    notifyListeners();
    LogService.instance.info('Upload cancelled: ${task.fileName}', 'FileUploadService');
    
    // 处理队列中的下一个任务
    _processQueue();
  }
  
  void removeUploadTask(String taskId) {
    final taskIndex = _uploadTasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    
    final task = _uploadTasks[taskIndex];
    if (task.status == UploadStatus.uploading) {
      task.cancelToken?.cancel();
      _activeUploads--;
    }
    
    _uploadTasks.removeAt(taskIndex);
    notifyListeners();
    
    // 处理队列中的下一个任务
    _processQueue();
  }
  
  void clearCompletedTasks() {
    _uploadTasks.removeWhere((t) => 
      t.status == UploadStatus.completed || 
      t.status == UploadStatus.cancelled
    );
    notifyListeners();
  }
  
  Future<void> startAllUploads() async {
    final pendingTasks = _uploadTasks.where((t) => 
      t.status == UploadStatus.pending || 
      t.status == UploadStatus.paused
    ).toList();
    
    LogService.instance.info('Starting ${pendingTasks.length} uploads', 'FileUploadService');
    
    for (final task in pendingTasks) {
      if (task.status == UploadStatus.paused) {
        task.status = UploadStatus.pending;
      }
    }
    
    // 启动并发上传
    for (int i = 0; i < maxConcurrentUploads && i < pendingTasks.length; i++) {
      final task = pendingTasks[i];
      if (task.status == UploadStatus.pending) {
        startUpload(task.id);
      }
    }
    
    notifyListeners();
  }
  
  void pauseAllUploads() {
    final uploadingTasks = _uploadTasks.where((t) => 
      t.status == UploadStatus.uploading
    ).toList();
    
    LogService.instance.info('Pausing ${uploadingTasks.length} uploads', 'FileUploadService');
    
    for (final task in uploadingTasks) {
      pauseUpload(task.id);
    }
  }
  
  void retryFailedUploads() {
    final failedTasks = _uploadTasks.where((t) => 
      t.status == UploadStatus.failed
    ).toList();
    
    LogService.instance.info('Retrying ${failedTasks.length} failed uploads', 'FileUploadService');
    
    for (final task in failedTasks) {
      task.status = UploadStatus.pending;
      task.error = null;
      task.retryCount = 0;
      task.progress = 0.0;
    }
    
    startAllUploads();
  }
  
  // 获取总的上传进度
  double get totalProgress {
    if (_uploadTasks.isEmpty) return 0.0;
    
    final totalSize = _uploadTasks.fold<int>(0, (sum, task) => sum + task.fileSize);
    if (totalSize == 0) return 0.0;
    
    final uploadedSize = _uploadTasks.fold<double>(0, (sum, task) => sum + (task.fileSize * task.progress));
    return uploadedSize / totalSize;
  }
}