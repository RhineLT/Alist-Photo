import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/alist_api_client.dart';
import '../services/log_service.dart';
import '../services/file_download_service.dart';
import '../services/media_type_helper.dart';
import '../services/media_cache_manager.dart';
import '../pages/settings_page.dart';
import '../pages/photo_viewer_page.dart';
import '../pages/video_viewer_page.dart';
import '../pages/live_photo_viewer_page.dart';
import '../pages/upload_page.dart';

class HomePage extends StatefulWidget {
  final AlistApiClient apiClient;
  
  const HomePage({super.key, required this.apiClient});
  
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _currentPath = '/';
  List<AlistFile> _files = [];
  bool _isLoading = false;
  bool _isGridView = true;
  final List<String> _pathHistory = ['/'];
  
  // 多选相关状态
  bool _isSelectionMode = false;
  final Set<String> _selectedFiles = <String>{};
  
  @override
  void initState() {
    super.initState();
    LogService.instance.info('Home page initialized', 'HomePage');
    _checkConfigAndLoad();
  }
  
  Future<void> _checkConfigAndLoad() async {
    LogService.instance.info('Checking configuration and loading files', 'HomePage');
    
    if (!widget.apiClient.isConfigured) {
      LogService.instance.warning('Alist not configured, opening settings', 'HomePage');
      _openSettings();
    } else {
      LogService.instance.info('Configuration valid, loading files', 'HomePage');
      _loadFiles();
    }
  }
  
  Future<void> _loadFiles() async {
    if (!widget.apiClient.isConfigured) {
      LogService.instance.warning('Cannot load files: Alist not configured', 'HomePage');
      return;
    }
    
    LogService.instance.info('Loading files from path: $_currentPath', 'HomePage');
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final files = await widget.apiClient.getFileList(_currentPath);
      if (files != null) {
        LogService.instance.info('Successfully loaded ${files.length} files', 'HomePage', {
          'path': _currentPath,
          'file_count': files.length,
        });
        setState(() {
          _files = files;
        });
      } else {
        LogService.instance.error('Failed to load files from path: $_currentPath', 'HomePage');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('加载文件失败，请检查网络连接和服务器设置')),
          );
        }
      }
    } catch (e) {
      LogService.instance.error('Exception while loading files: $e', 'HomePage', {
        'path': _currentPath,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载文件失败：$e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _openUploadPage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UploadPage(
          apiClient: widget.apiClient,
          currentPath: _currentPath,
        ),
      ),
    );
    
    // 如果有文件上传成功，刷新文件列表
    if (result == true) {
      _loadFiles();
    }
  }

  Future<void> _openSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(apiClient: widget.apiClient),
      ),
    );
    
    if (result == true && mounted) {
      _loadFiles();
    }
  }
  
  void _navigateToFolder(AlistFile folder) {
    final newPath = _currentPath == '/' 
        ? '/${folder.name}' 
        : '$_currentPath/${folder.name}';
    
    setState(() {
      _currentPath = newPath;
      _pathHistory.add(newPath);
      _exitSelectionMode(); // 切换文件夹时退出选择模式
    });
    
    _loadFiles();
  }
  
  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
      _selectedFiles.clear();
    });
  }
  
  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedFiles.clear();
    });
  }
  
  void _toggleFileSelection(AlistFile file) {
    setState(() {
      if (_selectedFiles.contains(file.name)) {
        _selectedFiles.remove(file.name);
      } else {
        _selectedFiles.add(file.name);
      }
      
      // 如果没有选中任何文件，退出选择模式
      if (_selectedFiles.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }
  
  void _selectAllFiles() {
    setState(() {
      _selectedFiles.clear();
      for (final file in _files) {
        if (!file.isDir) {
          _selectedFiles.add(file.name);
        }
      }
    });
  }
  
  Future<void> _batchDownload() async {
    final selectedFiles = _files.where((f) => _selectedFiles.contains(f.name)).toList();
    
    if (selectedFiles.isEmpty) return;
    
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('开始下载 ${selectedFiles.length} 个文件')),
    );
    
    int completed = 0;
    int failed = 0;
    
    for (final file in selectedFiles) {
      try {
        final downloadUrl = await widget.apiClient.getDownloadUrl(file);
        await FileDownloadService.downloadFile(
          downloadUrl,
          file.name,
          onProgress: (progress) {
            // 可以添加全局进度显示
          },
        );
        completed++;
      } catch (e) {
        failed++;
        LogService.instance.error('Batch download failed for ${file.name}: $e', 'HomePage');
      }
    }
    
    _exitSelectionMode();
    
    messenger.showSnackBar(
      SnackBar(
        content: Text('批量下载完成：成功 $completed 个，失败 $failed 个'),
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  Future<void> _batchCopy() async {
    // 这里需要一个文件夹选择器
    _showFolderPicker(isMove: false);
  }
  
  Future<void> _batchMove() async {
    // 这里需要一个文件夹选择器
    _showFolderPicker(isMove: true);
  }
  
  void _showFolderPicker({required bool isMove}) {
    // 简化版本：显示输入对话框让用户输入目标路径
    showDialog(
      context: context,
      builder: (context) {
        String targetPath = _currentPath;
        return AlertDialog(
          title: Text(isMove ? '移动到文件夹' : '复制到文件夹'),
          content: TextField(
            decoration: const InputDecoration(
              labelText: '目标文件夹路径',
              hintText: '/path/to/target',
            ),
            onChanged: (value) => targetPath = value,
            controller: TextEditingController(text: targetPath),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (isMove) {
                  _performBatchMove(targetPath);
                } else {
                  _performBatchCopy(targetPath);
                }
              },
              child: Text(isMove ? '移动' : '复制'),
            ),
          ],
        );
      },
    );
  }
  
  Future<void> _performBatchCopy(String targetPath) async {
    final selectedFiles = _files.where((f) => _selectedFiles.contains(f.name)).toList();
    
    // 这里应该调用Alist API进行批量复制
    // 由于API文档中没有看到批量复制的接口，这里先显示提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('复制 ${selectedFiles.length} 个文件到 $targetPath（功能开发中）'),
      ),
    );
    
    _exitSelectionMode();
  }
  
  Future<void> _performBatchMove(String targetPath) async {
    final selectedFiles = _files.where((f) => _selectedFiles.contains(f.name)).toList();
    
    // 这里应该调用Alist API进行批量移动
    // 由于API文档中没有看到批量移动的接口，这里先显示提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('移动 ${selectedFiles.length} 个文件到 $targetPath（功能开发中）'),
      ),
    );
    
    _exitSelectionMode();
  }
  
  void _navigateUp() {
    if (_pathHistory.length > 1) {
      _pathHistory.removeLast();
      setState(() {
        _currentPath = _pathHistory.last;
      });
      _loadFiles();
    }
  }
  
  void _showFileMenu(AlistFile file) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('详细信息'),
            onTap: () {
              Navigator.pop(context);
              _showFileInfo(file);
            },
          ),
          if (!file.isDir) ...[
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('下载'),
              onTap: () {
                Navigator.pop(context);
                _downloadFile(file);
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('重命名'),
            onTap: () {
              Navigator.pop(context);
              _renameFile(file);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('删除'),
            onTap: () {
              Navigator.pop(context);
              _deleteFile(file);
            },
          ),
        ],
      ),
    );
  }

  void _showFileInfo(AlistFile file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('类型: ${file.isDir ? '文件夹' : file.isImage ? '图像' : '文件'}'),
            const SizedBox(height: 8),
            if (!file.isDir) ...[
              Text('大小: ${file.formattedSize}'),
              const SizedBox(height: 8),
            ],
            Text('创建时间: ${file.created.toString().split('.')[0]}'),
            const SizedBox(height: 8),
            Text('修改时间: ${file.modified.toString().split('.')[0]}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _downloadFile(AlistFile file) async {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('复制下载链接'),
            onTap: () async {
              final downloadUrl = await widget.apiClient.getDownloadUrl(file);
              await Clipboard.setData(ClipboardData(text: downloadUrl));
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('下载链接已复制到剪贴板')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.open_in_browser),
            title: const Text('在浏览器中打开'),
            onTap: () async {
              final downloadUrl = await widget.apiClient.getDownloadUrl(file);
              final uri = Uri.parse(downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              if (mounted) {
                Navigator.pop(context);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('下载到本地'),
            onTap: () async {
              Navigator.pop(context);
              await _downloadFileToLocal(file);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _downloadFileToLocal(AlistFile file) async {
    try {
      // 显示简单的下载提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('开始下载: ${file.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // 获取下载URL
      LogService.instance.info('Getting download URL for file: ${file.name}', 'HomePage');
      final downloadUrl = await widget.apiClient.getDownloadUrl(file);
      
      // 开始下载
      LogService.instance.info('Starting local download', 'HomePage', {
        'file_name': file.name,
        'download_url': downloadUrl,
      });
      
      final downloadService = FileDownloadService.instance;
      final filePath = await downloadService.downloadFile(
        url: downloadUrl,
        fileName: file.name,
      );

      if (filePath != null) {
        LogService.instance.info('File downloaded successfully', 'HomePage', {
          'file_name': file.name,
          'local_path': filePath,
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('下载完成，保存至: Downloads/${file.name}'),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: '确定',
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
            ),
          );
        }
      } else {
        LogService.instance.error('File download failed', 'HomePage');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('下载失败: ${file.name}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      LogService.instance.error('Download error: $e', 'HomePage');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载出错: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _renameFile(AlistFile file) {
    final controller = TextEditingController(text: file.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '新名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != file.name) {
                Navigator.pop(context);
                
                final filePath = _currentPath == '/' 
                    ? '/${file.name}' 
                    : '$_currentPath/${file.name}';
                
                final success = await widget.apiClient.renameFile(filePath, newName);
                if (success) {
                  _loadFiles();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('重命名成功')),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('重命名失败')),
                    );
                  }
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _deleteFile(AlistFile file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${file.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              
              final success = await widget.apiClient.deleteFiles(
                _currentPath, 
                [file.name]
              );
              
              if (success) {
                _loadFiles();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('删除成功')),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('删除失败')),
                  );
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _createNewFolder() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '文件夹名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final folderName = controller.text.trim();
              if (folderName.isNotEmpty) {
                Navigator.pop(context);
                
                final newFolderPath = _currentPath == '/' 
                    ? '/$folderName' 
                    : '$_currentPath/$folderName';
                
                final success = await widget.apiClient.createFolder(newFolderPath);
                if (success) {
                  _loadFiles();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('文件夹创建成功')),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('文件夹创建失败')),
                    );
                  }
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _openMediaFile(AlistFile file, int index) {
    final mediaType = MediaType.getMediaType(file.name);
    
    switch (mediaType) {
      case 'image':
        _openPhoto(file, index);
        break;
      case 'video':
        _openVideo(file, index);
        break;
      case 'live_photo':
        _openLivePhoto(file, index);
        break;
      default:
        _showFileOperations(file);
        break;
    }
  }

  void _openPhoto(AlistFile file, int index) {
    // 获取所有图片文件
    final imageFiles = _files.where((f) => !f.isDir && MediaType.isImage(f.name)).toList();
    final imageIndex = imageFiles.indexOf(file);
    
    if (imageIndex >= 0) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PhotoViewerPage(
            apiClient: widget.apiClient,
            files: imageFiles,
            initialIndex: imageIndex,
          ),
        ),
      );
    }
  }
  
  void _openVideo(AlistFile file, int index) {
    // 获取所有视频文件
    final videoFiles = _files.where((f) => !f.isDir && MediaType.isVideo(f.name)).toList();
    final videoIndex = videoFiles.indexOf(file);
    
    if (videoIndex >= 0) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoViewerPage(
            apiClient: widget.apiClient,
            files: videoFiles,
            initialIndex: videoIndex,
          ),
        ),
      );
    }
  }
  
  void _openLivePhoto(AlistFile file, int index) {
    // 检查是否有对应的视频文件（小米动态照片的伴随视频）
    AlistFile? videoFile;
    final baseName = file.name.toLowerCase().replaceAll(RegExp(r'\.[^.]*$'), '');
    
    // 寻找对应的视频文件
    for (final f in _files) {
      if (!f.isDir && MediaType.isVideo(f.name)) {
        final videoBaseName = f.name.toLowerCase().replaceAll(RegExp(r'\.[^.]*$'), '');
        if (videoBaseName == baseName || videoBaseName.startsWith(baseName)) {
          videoFile = f;
          break;
        }
      }
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LivePhotoViewerPage(
          apiClient: widget.apiClient,
          file: file,
          videoFile: videoFile,
        ),
      ),
    );
  }
  
  Widget _buildBreadcrumb() {
    final pathParts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _currentPath = '/';
                _pathHistory.clear();
                _pathHistory.add('/');
              });
              _loadFiles();
            },
            child: const Icon(Icons.home, color: Colors.blue),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < pathParts.length; i++) ...[
                    const Icon(Icons.chevron_right, size: 16),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        final targetPath = '/${pathParts.take(i + 1).join('/')}';
                        setState(() {
                          _currentPath = targetPath;
                          _pathHistory.removeWhere((path) => 
                              path.split('/').length > targetPath.split('/').length);
                        });
                        _loadFiles();
                      },
                      child: Text(
                        pathParts[i],
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFileGridItem(AlistFile file, int index) {
    if (file.isDir) {
      return GestureDetector(
        onTap: () => _navigateToFolder(file),
        onLongPress: () => _showFileMenu(file),
        child: Card(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder, size: 48, color: Colors.orange),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  file.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    } else if (MediaType.isMediaFile(file.name)) {
      final thumbnailUrl = widget.apiClient.getThumbnailUrl(file);
      final mediaType = MediaType.getMediaType(file.name);
      
      return GestureDetector(
        onTap: () => _isSelectionMode 
            ? _toggleFileSelection(file) 
            : _openMediaFile(file, index),
        onLongPress: () => _isSelectionMode 
            ? null 
            : () {
                _enterSelectionMode();
                _toggleFileSelection(file);
              }(),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: thumbnailUrl,
                            fit: BoxFit.cover,
                            cacheManager: MediaCacheManager.instance.thumbnailCache,
                            placeholder: (context, url) => Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade200,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    mediaType == 'video' ? Icons.video_file : Icons.image,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    mediaType == 'video' ? '视频' : '无缩略图',
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Container(
                            color: Colors.grey.shade200,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  mediaType == 'video' ? Icons.video_file : Icons.image,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  mediaType == 'video' ? '视频' : '无缩略图',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                  ),
                  // 移除缩略图的文件名和大小显示，提高信息密度
                ],
              ),
              
              // 选择状态覆盖层
              if (_isSelectionMode)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _selectedFiles.contains(file.name)
                          ? Colors.green.withOpacity(0.3)
                          : Colors.black.withOpacity(0.1),
                      border: _selectedFiles.contains(file.name)
                          ? Border.all(color: Colors.green, width: 3)
                          : null,
                    ),
                  ),
                ),
              
              // 选择状态指示器
              if (_isSelectionMode)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _selectedFiles.contains(file.name)
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: _selectedFiles.contains(file.name)
                          ? Colors.green
                          : Colors.grey,
                      size: 24,
                    ),
                  ),
                ),
              
              // 快速下载按钮 (只在非选择模式显示)
              if (!_isSelectionMode)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _downloadFile(file),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.download,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              // 媒体类型指示器
              if (mediaType == 'video' && !_isSelectionMode)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              if (mediaType == 'live_photo' && !_isSelectionMode)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      Icons.motion_photos_on,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      return GestureDetector(
        onLongPress: () => _showFileMenu(file),
        child: Card(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.insert_drive_file, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  file.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                file.formattedSize,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  
  Widget _buildFileListItem(AlistFile file, int index) {
    return ListTile(
      leading: file.isDir
          ? const Icon(Icons.folder, color: Colors.orange)
          : file.isImage
              ? const Icon(Icons.image, color: Colors.blue)
              : const Icon(Icons.insert_drive_file, color: Colors.grey),
      title: Text(file.name),
      subtitle: file.isDir 
          ? const Text('文件夹')
          : Text('${file.formattedSize} • ${file.modified.toString().split('.')[0]}'),
      onTap: () {
        if (file.isDir) {
          _navigateToFolder(file);
        } else if (file.isImage) {
          _openPhoto(file, index);
        }
      },
      onLongPress: () => _showFileMenu(file),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode 
            ? Text('已选择 ${_selectedFiles.length} 个文件')
            : const Text('Alist Photo'),
        backgroundColor: _isSelectionMode ? Colors.green : Colors.blue,
        foregroundColor: Colors.white,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: _selectAllFiles,
                  tooltip: '全选',
                ),
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: _selectedFiles.isNotEmpty ? _batchDownload : null,
                  tooltip: '批量下载',
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: _selectedFiles.isNotEmpty ? _batchCopy : null,
                  tooltip: '批量复制',
                ),
                IconButton(
                  icon: const Icon(Icons.drive_file_move),
                  onPressed: _selectedFiles.isNotEmpty ? _batchMove : null,
                  tooltip: '批量移动',
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.checklist),
                  onPressed: _enterSelectionMode,
                  tooltip: '批量选择',
                ),
                IconButton(
                  icon: const Icon(Icons.upload),
                  onPressed: _openUploadPage,
                  tooltip: '上传文件',
                ),
                IconButton(
                  icon: const Icon(Icons.add_box),
                  onPressed: _createNewFolder,
                  tooltip: '新建文件夹',
                ),
                IconButton(
                  icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
                  onPressed: () {
                    setState(() {
                      _isGridView = !_isGridView;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: _openSettings,
                ),
              ],
      ),
      body: Column(
        children: [
          if (_pathHistory.length > 1)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _navigateUp,
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          _buildBreadcrumb(),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              widget.apiClient.isConfigured 
                                  ? '此文件夹是空的'
                                  : '请先配置 Alist 服务器',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            if (!widget.apiClient.isConfigured) ...[
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _openSettings,
                                child: const Text('打开设置'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadFiles,
                        child: _isGridView
                            ? MasonryGridView.count(
                                crossAxisCount: 2,
                                padding: const EdgeInsets.all(8),
                                itemCount: _files.length,
                                itemBuilder: (context, index) =>
                                    _buildFileGridItem(_files[index], index),
                              )
                            : ListView.builder(
                                itemCount: _files.length,
                                itemBuilder: (context, index) =>
                                    _buildFileListItem(_files[index], index),
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}