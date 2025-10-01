import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/alist_api_client.dart';
import '../services/file_upload_service.dart';
import '../services/log_service.dart';

class UploadPage extends StatefulWidget {
  final AlistApiClient apiClient;
  final String currentPath;
  
  const UploadPage({
    super.key,
    required this.apiClient,
    required this.currentPath,
  });
  
  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  late FileUploadService _uploadService;
  final ImagePicker _imagePicker = ImagePicker();
  
  @override
  void initState() {
    super.initState();
    _uploadService = FileUploadService(widget.apiClient);
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _uploadService,
      builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('上传文件'),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: _uploadService.uploadTasks.any((t) => 
              t.status == UploadStatus.pending || t.status == UploadStatus.paused
            ) ? () => _uploadService.startAllUploads() : null,
            tooltip: '开始所有上传',
          ),
          IconButton(
            icon: const Icon(Icons.pause),
            onPressed: _uploadService.uploadTasks.any((t) => 
              t.status == UploadStatus.uploading
            ) ? () => _uploadService.pauseAllUploads() : null,
            tooltip: '暂停所有上传',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'clear_completed':
                  setState(() {
                    _uploadService.clearCompletedTasks();
                  });
                  break;
                case 'retry_failed':
                  _confirmRetryFailed();
                  break;
                case 'clear_all':
                  _confirmClearAll();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_completed',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services, size: 20),
                    SizedBox(width: 8),
                    Text('清除已完成'),
                  ],
                ),
              ),
              if (_uploadService.failedCount > 0)
                const PopupMenuItem(
                  value: 'retry_failed',
                  child: Row(
                    children: [
                      Icon(Icons.refresh, size: 20),
                      SizedBox(width: 8),
                      Text('重试失败项'),
                    ],
                  ),
                ),
              if (_uploadService.uploadTasks.isNotEmpty)
                const PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.clear_all, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('清除所有任务', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 上传统计
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard('待上传', _uploadService.pendingCount, Colors.grey),
                _buildStatCard('上传中', _uploadService.uploadingCount, Colors.blue),
                _buildStatCard('已完成', _uploadService.completedCount, Colors.green),
                _buildStatCard('失败', _uploadService.failedCount, Colors.red),
              ],
            ),
          ),
          
          // 添加文件按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.file_upload),
                    label: const Text('选择文件'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.photo),
                    label: const Text('选择图片'),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 上传任务列表
          Expanded(
            child: _uploadService.uploadTasks.isEmpty
                ? const Center(
                    child: Text(
                      '暂无上传任务\n点击上方按钮选择要上传的文件',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _uploadService.uploadTasks.length,
                    itemBuilder: (context, index) {
                      final task = _uploadService.uploadTasks[index];
                      return _buildUploadTaskItem(task);
                    },
                  ),
          ),
        ],
      ),
    ),
  );
  }
  
  Widget _buildStatCard(String title, int count, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildUploadTaskItem(UploadTask task) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: _getStatusIcon(task.status),
        title: Text(
          task.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${task.formattedSize} • ${_getStatusText(task.status)}'),
            if (task.status == UploadStatus.uploading || task.status == UploadStatus.completed)
              LinearProgressIndicator(
                value: task.progress,
                backgroundColor: Colors.grey.shade300,
              ),
            if (task.error != null)
              Text(
                task.error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (task.status == UploadStatus.pending)
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => _uploadService.startUpload(task.id),
                tooltip: '开始上传',
              ),
            if (task.status == UploadStatus.uploading)
              IconButton(
                icon: const Icon(Icons.pause),
                onPressed: () => _uploadService.pauseUpload(task.id),
                tooltip: '暂停上传',
              ),
            if (task.status == UploadStatus.paused)
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => _uploadService.resumeUpload(task.id),
                tooltip: '继续上传',
              ),
            if (task.status == UploadStatus.failed)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _uploadService.startUpload(task.id),
                tooltip: '重试上传',
              ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _removeTask(task),
              tooltip: '移除任务',
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _getStatusIcon(UploadStatus status) {
    switch (status) {
      case UploadStatus.pending:
        return const Icon(Icons.schedule, color: Colors.grey);
      case UploadStatus.uploading:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case UploadStatus.paused:
        return const Icon(Icons.pause_circle, color: Colors.orange);
      case UploadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case UploadStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      case UploadStatus.cancelled:
        return const Icon(Icons.cancel, color: Colors.grey);
    }
  }
  
  String _getStatusText(UploadStatus status) {
    switch (status) {
      case UploadStatus.pending:
        return '等待上传';
      case UploadStatus.uploading:
        return '上传中';
      case UploadStatus.paused:
        return '已暂停';
      case UploadStatus.completed:
        return '已完成';
      case UploadStatus.failed:
        return '上传失败';
      case UploadStatus.cancelled:
        return '已取消';
    }
  }
  
  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      
      if (result != null && result.files.isNotEmpty) {
        for (final file in result.files) {
          if (file.path != null) {
            final taskId = _uploadService.addUploadTask(
              filePath: file.path!,
              targetPath: widget.currentPath,
            );
            
            // 添加回调以更新UI
            _uploadService.addProgressCallback(taskId, (task) {
              if (mounted) setState(() {});
            });
            _uploadService.addStatusCallback(taskId, (task) {
              if (mounted) setState(() {});
            });
          }
        }
        
        setState(() {});
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已添加 ${result.files.length} 个文件到上传队列'),
            action: SnackBarAction(
              label: '开始上传',
              onPressed: () => _uploadService.startAllUploads(),
            ),
          ),
        );
      }
    } catch (e) {
      LogService.instance.error('Failed to pick files: $e', 'UploadPage');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件选择失败: $e')),
        );
      }
    }
  }
  
  Future<void> _pickImages() async {
    try {
      final images = await _imagePicker.pickMultipleMedia();
      
      if (images.isNotEmpty) {
        for (final image in images) {
          final taskId = _uploadService.addUploadTask(
            filePath: image.path,
            targetPath: widget.currentPath,
          );
          
          // 添加回调以更新UI
          _uploadService.addProgressCallback(taskId, (task) {
            if (mounted) setState(() {});
          });
          _uploadService.addStatusCallback(taskId, (task) {
            if (mounted) setState(() {});
          });
        }
        
        setState(() {});
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已添加 ${images.length} 个图片到上传队列'),
            action: SnackBarAction(
              label: '开始上传',
              onPressed: () => _uploadService.startAllUploads(),
            ),
          ),
        );
      }
    } catch (e) {
      LogService.instance.error('Failed to pick images: $e', 'UploadPage');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片选择失败: $e')),
        );
      }
    }
  }
  
  void _removeTask(UploadTask task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要移除上传任务 "${task.fileName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                if (task.status == UploadStatus.uploading) {
                  _uploadService.cancelUpload(task.id);
                }
                _uploadService.removeUploadTask(task.id);
              });
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
  
  void _confirmRetryFailed() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重试失败项'),
        content: Text('确定要重试 ${_uploadService.failedCount} 个失败的上传任务吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _uploadService.retryFailedUploads();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已重新开始 ${_uploadService.failedCount} 个失败任务'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
  
  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所有任务'),
        content: const Text('确定要清除所有上传任务吗？\n\n正在上传的任务将被取消，所有任务将被移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final taskCount = _uploadService.uploadTasks.length;
              _uploadService.clearAllTasks();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已清除 $taskCount 个上传任务'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }
}