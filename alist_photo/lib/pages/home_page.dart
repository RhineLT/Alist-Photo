import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:io';
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
  // 复制/移动状态
  String? _pendingOperation; // 'copy' or 'move'
  List<String> _pendingNames = [];
  String? _operationSrcDir;
  bool _isChoosingTarget = false; // 选择目标目录模式
  
  // 退出确认相关状态
  DateTime? _lastBackPressed;
  static const Duration _backPressedThreshold = Duration(seconds: 2);
  
  // 月份分组相关状态
  Map<String, List<AlistFile>> _groupedFiles = {};
  bool _enableMonthGrouping = true; // 是否启用月份分组
  
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
  
  Future<void> _loadFiles({bool refresh = false}) async {
    if (!widget.apiClient.isConfigured) {
      LogService.instance.warning('Cannot load files: Alist not configured', 'HomePage');
      return;
    }
    
    LogService.instance.info('Loading files from path: $_currentPath', 'HomePage');
    
    setState(() {
      _isLoading = true;
      _files = []; // 清空旧数据，避免加载过程中误触导致路径错位
    });
    
    try {
  final files = await widget.apiClient.getFileList(_currentPath, refresh: refresh);
      if (files != null) {
        LogService.instance.info('Successfully loaded ${files.length} files', 'HomePage', {
          'path': _currentPath,
          'file_count': files.length,
        });
        setState(() {
          _files = files;
        });
        // 对文件进行月份分组
        _groupFilesByMonth();
        // 同步缓存目录结构（当前路径与子目录）
        try {
          await MediaCacheManager.instance.syncDirectoryStructure(_currentPath, files);
        } catch (e) {
          LogService.instance.warning('Sync cache dir structure failed: $e', 'HomePage');
        }
        // 异步后台预加载（不阻塞首屏显示）
        unawaited(Future(() async {
          try {
            await MediaCacheManager.instance.preloadThumbnails(widget.apiClient, files);
          } catch (e) {
            LogService.instance.warning('Preload thumbnails failed (background): $e', 'HomePage');
          }
        }));
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
  
  // 按月份对文件进行分组
  void _groupFilesByMonth() {
    if (!_enableMonthGrouping) {
      _groupedFiles = {'所有文件': _files};
      return;
    }
    
    final Map<String, List<AlistFile>> grouped = {};
    
    // 首先添加所有目录（不分组）
    final folders = _files.where((file) => file.isDir).toList();
    if (folders.isNotEmpty) {
      grouped['文件夹'] = folders;
    }
    
    // 然后按月份分组文件
    final files = _files.where((file) => !file.isDir).toList();
    for (final file in files) {
      final date = file.created;
      final monthKey = '${date.year}年${date.month.toString().padLeft(2, '0')}月';
      
      if (!grouped.containsKey(monthKey)) {
        grouped[monthKey] = [];
      }
      grouped[monthKey]!.add(file);
    }
    
    // 按时间倒序排列月份（最新的在前面）
    final sortedKeys = grouped.keys.where((key) => key != '文件夹').toList();
    sortedKeys.sort((a, b) {
      if (a == '文件夹') return -1;
      if (b == '文件夹') return 1;
      return b.compareTo(a); // 倒序排列
    });
    
    _groupedFiles = {};
    // 先添加文件夹
    if (grouped.containsKey('文件夹')) {
      _groupedFiles['文件夹'] = grouped['文件夹']!;
    }
    // 再按时间顺序添加月份分组
    for (final key in sortedKeys) {
      _groupedFiles[key] = grouped[key]!;
    }
    
    LogService.instance.debug('Files grouped by month: ${_groupedFiles.keys.toList()}', 'HomePage');
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
    if (_isLoading) return; // 加载中禁止继续导航，防止错位
    final newPath = _currentPath == '/' 
        ? '/${folder.name}' 
        : '$_currentPath/${folder.name}';
    // 避免重复进入同名子目录（例如 /a/b/b）
    final parts = _currentPath.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.isNotEmpty && parts.last == folder.name) {
      return;
    }
    
    setState(() {
      _currentPath = newPath;
      _pathHistory.add(newPath);
      if (!_isChoosingTarget) {
        _exitSelectionMode();
      }
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
        await FileDownloadService.instance.downloadFile(
          url: downloadUrl,
          fileName: file.name,
          onProgress: (received, total) {
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
    final names = _files.where((f) => _selectedFiles.contains(f.name)).map((f) => f.name).toList();
    if (names.isEmpty) return;
    setState(() {
      _pendingOperation = 'copy';
      _pendingNames = names;
      _operationSrcDir = _currentPath;
      _isChoosingTarget = true;
      _isSelectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('请选择目标目录，然后点击右上角粘贴 (${names.length} 项)')),
    );
  }

  Future<void> _batchMove() async {
    final names = _files.where((f) => _selectedFiles.contains(f.name)).map((f) => f.name).toList();
    if (names.isEmpty) return;
    setState(() {
      _pendingOperation = 'move';
      _pendingNames = names;
      _operationSrcDir = _currentPath;
      _isChoosingTarget = true;
      _isSelectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('请选择目标目录，然后点击右上角粘贴 (${names.length} 项)')),
    );
  }

  void _cancelPendingOperation() {
    setState(() {
      _pendingOperation = null;
      _pendingNames = [];
      _operationSrcDir = null;
      _isChoosingTarget = false;
    });
  }

  Future<void> _executePendingOperation() async {
    if (_pendingOperation == null || _operationSrcDir == null) return;
    final op = _pendingOperation!;
    final srcDir = _operationSrcDir!;
    final dstDir = _currentPath;
    if (srcDir == dstDir) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('目标目录不能与源目录相同')));
      return;
    }
    // 由于当前 UI 只允许选择文件（目录不会进入多选集合），无需对子目录进行阻断。
    // 如果后续允许目录参与操作，可在此加入：判断若 names 中包含某目录且 dstDir 位于该目录子树下则阻断。
    final names = List<String>.from(_pendingNames);
    setState(() { _isLoading = true; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${op=='copy'?'复制':'移动'}中：${names.length} 项...')));
    bool success = false;
    if (op == 'copy') {
      success = await widget.apiClient.copyFiles(srcDir: srcDir, dstDir: dstDir, names: names);
    } else {
      success = await widget.apiClient.moveFiles(srcDir: srcDir, dstDir: dstDir, names: names);
    }
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${op=='copy'?'复制':'移动'}成功')));
      }
      _loadFiles(refresh: true);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${op=='copy'?'复制':'移动'}失败'), backgroundColor: Colors.red));
      }
    }
    setState(() { _isLoading = false; });
    _cancelPendingOperation();
  }
  
  // 处理返回键逻辑
  Future<bool> _handleBackPress() async {
    // 如果当前在选择模式，退出选择模式
    if (_isSelectionMode) {
      _exitSelectionMode();
      return false;
    }
    
    // 如果不在根目录，返回上一级目录
    if (_pathHistory.length > 1) {
      _navigateUp();
      return false;
    }
    
    // 如果在根目录，显示退出确认
    final now = DateTime.now();
    if (_lastBackPressed == null || 
        now.difference(_lastBackPressed!) > _backPressedThreshold) {
      _lastBackPressed = now;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('再次按返回键退出应用'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
    
    // 允许退出应用
    return true;
  }
  
  void _navigateUp() {
    if (_pathHistory.length > 1) {
      _pathHistory.removeLast();
      setState(() {
        _currentPath = _pathHistory.last;
        if (!_isChoosingTarget) {
          _exitSelectionMode();
        }
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
        _showFileMenu(file);
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
          margin: EdgeInsets.zero, // 移除 Card 的默认 margin
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder, size: 32, color: Colors.orange), // 缩小图标
              const SizedBox(height: 4), // 减少间距
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4), // 减少内边距
                child: Text(
                  file.name,
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12), // 缩小字体
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
          margin: EdgeInsets.zero, // 移除 Card 的默认 margin
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: FutureBuilder<File?>(
                  future: MediaCacheManager.instance.getOrFetchThumbnail(widget.apiClient, file),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        color: Colors.grey.shade200,
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    }
                    final f = snapshot.data;
                    if (f != null && f.existsSync()) {
                      return Image.file(f, fit: BoxFit.cover);
                    }
                    return Container(
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
                    );
                  },
                ),
              ),
              
              // 选择状态覆盖层
              if (_isSelectionMode)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
            color: _selectedFiles.contains(file.name)
              ? Colors.green.withAlpha((0.3 * 255).round())
              : Colors.black.withAlpha((0.1 * 255).round()),
                      border: _selectedFiles.contains(file.name)
                          ? Border.all(color: Colors.green, width: 3)
                          : null,
                    ),
                  ),
                ),
              
              // 选择状态指示器
              if (_isSelectionMode)
                Positioned(
                  top: 4,
                  left: 4,
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
                      size: 18, // 减小尺寸
                    ),
                  ),
                ),
              
              // 媒体类型指示器
              if (mediaType == 'video' && !_isSelectionMode)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha((0.6 * 255).round()),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
              if (mediaType == 'live_photo' && !_isSelectionMode)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha((0.6 * 255).round()),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Icon(
                      Icons.motion_photos_on,
                      color: Colors.white,
                      size: 12,
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
          margin: EdgeInsets.zero, // 移除 Card 的默认 margin
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.insert_drive_file, size: 32, color: Colors.grey), // 缩小图标
              const SizedBox(height: 4), // 减少间距
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4), // 减少内边距
                child: Text(
                  file.name,
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11), // 缩小字体
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2), // 减少间距
              Text(
                file.formattedSize,
                style: TextStyle(
                  fontSize: 10, // 缩小字体
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
    return PopScope(
      canPop: false, // 始终拦截返回键
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return; // 如果已经弹出，不再处理
        
        final shouldPop = await _handleBackPress();
        if (shouldPop) {
          // 退出整个应用
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isChoosingTarget
              ? Text('${_pendingOperation == 'copy' ? '复制' : '移动'}到: $_currentPath')
              : _isSelectionMode
                  ? Text('已选择 ${_selectedFiles.length} 个文件')
                  : const Text('Alist Photo'),
          backgroundColor: _isChoosingTarget
              ? Colors.orange
              : _isSelectionMode ? Colors.green : Colors.blue,
          foregroundColor: Colors.white,
          leading: _isChoosingTarget
              ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '取消',
                  onPressed: _cancelPendingOperation,
                )
              : _isSelectionMode
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _exitSelectionMode,
                    )
                  : null,
          actions: _isChoosingTarget
              ? [
                  IconButton(
                    icon: const Icon(Icons.paste),
                    tooltip: '粘贴到此',
                    onPressed: _executePendingOperation,
                  ),
                ]
              : _isSelectionMode
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
                          setState(() { _isGridView = !_isGridView; });
                        },
                        tooltip: _isGridView ? '列表视图' : '网格视图',
                      ),
                      IconButton(
                        icon: Icon(_enableMonthGrouping ? Icons.calendar_view_month : Icons.view_agenda),
                        onPressed: () {
                          setState(() { 
                            _enableMonthGrouping = !_enableMonthGrouping;
                            _groupFilesByMonth(); // 重新分组
                          });
                        },
                        tooltip: _enableMonthGrouping ? '取消月份分组' : '按月份分组',
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
                        onRefresh: () => _loadFiles(refresh: true),
                        child: _isGridView
                            ? _buildGroupedGridView()
                            : ListView.builder(
                                itemCount: _files.length,
                                itemBuilder: (context, index) =>
                                    _buildFileListItem(_files[index], index),
                              ),
                      ),
          ),
        ],
      ),
    ),
    );
  }
  
  // 构建按月份分组的网格视图
  Widget _buildGroupedGridView() {
    if (_groupedFiles.isEmpty) {
      return const Center(child: Text('没有文件'));
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(4),
      itemCount: _groupedFiles.length,
      itemBuilder: (context, groupIndex) {
        final groupName = _groupedFiles.keys.elementAt(groupIndex);
        final groupFiles = _groupedFiles[groupName]!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 月份标题
            if (groupName != '所有文件')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      groupName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${groupFiles.length} 项',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            // 该月份的文件网格
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
                childAspectRatio: 1,
              ),
              itemCount: groupFiles.length,
              itemBuilder: (context, fileIndex) {
                final file = groupFiles[fileIndex];
                // 计算在整个文件列表中的索引（用于媒体查看器）
                final globalIndex = _files.indexOf(file);
                return _buildFileGridItem(file, globalIndex);
              },
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}