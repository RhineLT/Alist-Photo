import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/alist_api_client.dart';
import '../services/log_service.dart';
import '../services/file_download_service.dart';
import '../pages/settings_page.dart';
import '../pages/photo_viewer_page.dart';

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
    });
    
    _loadFiles();
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
      // 显示下载进度对话框
      bool isDownloading = true;
      double progress = 0.0;
      String? downloadPath;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('下载文件'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('正在下载: ${file.name}'),
                const SizedBox(height: 16),
                if (isDownloading) ...[
                  LinearProgressIndicator(value: progress > 0 ? progress : null),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).toStringAsFixed(1)}%'),
                ] else ...[
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
                  const SizedBox(height: 8),
                  const Text('下载完成！'),
                  if (downloadPath != null) Text('保存至: $downloadPath'),
                ],
              ],
            ),
            actions: [
              if (!isDownloading) ...[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('确定'),
                ),
              ] else ...[
                TextButton(
                  onPressed: () {
                    // TODO: 实现取消下载功能
                    Navigator.pop(context);
                  },
                  child: const Text('取消'),
                ),
              ],
            ],
          ),
        ),
      );

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
        onProgress: (received, total) {
          if (total > 0) {
            final newProgress = received / total;
            if ((newProgress - progress).abs() > 0.01) { // 只在进度变化超过1%时更新UI
              progress = newProgress;
              if (context.mounted) {
                // 触发对话框重建
                (context as Element).markNeedsBuild();
              }
            }
          }
        },
      );

      // 更新下载状态
      isDownloading = false;
      downloadPath = filePath;
      
      if (filePath != null) {
        LogService.instance.info('File downloaded successfully', 'HomePage', {
          'file_name': file.name,
          'local_path': filePath,
        });
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('文件下载完成: ${file.name}'),
              action: SnackBarAction(
                label: '查看',
                onPressed: () {
                  // TODO: 打开文件管理器或查看文件
                },
              ),
            ),
          );
        }
      } else {
        LogService.instance.error('File download failed', 'HomePage', {
          'file_name': file.name,
        });
        
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('文件下载失败: ${file.name}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      LogService.instance.error('Download error: $e', 'HomePage');
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载出错: $e'),
            backgroundColor: Colors.red,
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

  void _openPhoto(AlistFile file, int index) {
    // 获取所有图片文件
    final imageFiles = _files.where((f) => !f.isDir && f.isImage).toList();
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
    } else if (file.isImage) {
      final thumbnailUrl = widget.apiClient.getThumbnailUrl(file);
      
      return GestureDetector(
        onTap: () => _openPhoto(file, index),
        onLongPress: () => _showFileMenu(file),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: thumbnailUrl,
                        fit: BoxFit.cover,
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
                              const Icon(Icons.image, size: 48, color: Colors.grey),
                              const SizedBox(height: 8),
                              Text(
                                '无缩略图',
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
                            const Icon(Icons.image, size: 48, color: Colors.grey),
                            const SizedBox(height: 8),
                            Text(
                              '无缩略图',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
        title: const Text('Alist Photo'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
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