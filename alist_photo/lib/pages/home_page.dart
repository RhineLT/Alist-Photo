import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/alist_api_client.dart';
import '../pages/settings_page.dart';
import '../pages/photo_viewer_page.dart';

class HomePage extends StatefulWidget {
  final AlistApiClient apiClient;
  
  const HomePage({super.key, required this.apiClient});
  
  @override
  _HomePageState createState() => _HomePageState();
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
    _checkConfigAndLoad();
  }
  
  Future<void> _checkConfigAndLoad() async {
    await widget.apiClient.initialize();
    if (!widget.apiClient.isConfigured) {
      _openSettings();
    } else {
      _loadFiles();
    }
  }
  
  Future<void> _loadFiles() async {
    if (!widget.apiClient.isConfigured) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final files = await widget.apiClient.getFileList(_currentPath);
      if (files != null) {
        setState(() {
          _files = files;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载文件失败，请检查网络连接和服务器设置')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载文件失败：$e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  void _openSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(apiClient: widget.apiClient),
      ),
    );
    
    if (result == true) {
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
      return Card(
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