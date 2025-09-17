import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';

class AlistApiClient {
  static const String _serverUrlKey = 'server_url';
  static const String _usernameKey = 'username';
  static const String _passwordKey = 'password';
  static const String _tokenKey = 'token';
  
  String? _serverUrl;
  String? _username;
  String? _password;
  String? _token;
  
  // 初始化客户端，从存储中加载配置
  Future<void> initialize() async {
    LogService.instance.info('Initializing Alist API client', 'AlistApiClient');
    
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(_serverUrlKey);
    _username = prefs.getString(_usernameKey);
    _password = prefs.getString(_passwordKey);
    _token = prefs.getString(_tokenKey);
    
    if (isConfigured) {
      LogService.instance.info('Alist configuration loaded: $_serverUrl', 'AlistApiClient');
    } else {
      LogService.instance.warning('Alist configuration incomplete', 'AlistApiClient');
    }
  }
  
  // 保存服务器配置
  Future<void> saveConfig({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    LogService.instance.info('Saving Alist configuration', 'AlistApiClient');
    
    final prefs = await SharedPreferences.getInstance();
    
    // 确保 URL 格式正确
    if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
      serverUrl = 'http://$serverUrl';
    }
    if (serverUrl.endsWith('/')) {
      serverUrl = serverUrl.substring(0, serverUrl.length - 1);
    }
    
    _serverUrl = serverUrl;
    _username = username;
    _password = password;
    
    await prefs.setString(_serverUrlKey, serverUrl);
    await prefs.setString(_usernameKey, username);
    await prefs.setString(_passwordKey, password);
    
    LogService.instance.info('Alist configuration saved', 'AlistApiClient', {
      'server_url': serverUrl,
      'username': username,
    });
  }
  
  // 检查是否已配置
  bool get isConfigured => 
      _serverUrl != null && 
      _username != null && 
      _password != null &&
      _serverUrl!.isNotEmpty &&
      _username!.isNotEmpty &&
      _password!.isNotEmpty;
  
  // 登录获取 token
  Future<bool> login() async {
    if (!isConfigured) {
      LogService.instance.warning('Cannot login: configuration incomplete', 'AlistApiClient');
      return false;
    }
    
    LogService.instance.info('Attempting to login to Alist server', 'AlistApiClient');
    
    try {
      // 根据Alist API文档，需要在密码后添加后缀再进行SHA256
      final hashedPassword = sha256.convert(utf8.encode('$_password-https://github.com/alist-org/alist')).toString();
      
      LogService.instance.debug('Sending login request to: $_serverUrl/api/auth/login/hash', 'AlistApiClient');
      
      final response = await http.post(
        Uri.parse('$_serverUrl/api/auth/login/hash'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _username!,
          'password': hashedPassword,
        }),
      );
      
      LogService.instance.debug('Login response status: ${response.statusCode}', 'AlistApiClient');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 200) {
          _token = data['data']['token'];
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_tokenKey, _token!);
          
          LogService.instance.info('Login successful', 'AlistApiClient');
          return true;
        } else {
          LogService.instance.error('Login failed: ${data['message'] ?? 'Unknown error'}', 'AlistApiClient', {
            'code': data['code'],
            'response': response.body,
          });
        }
      } else {
        LogService.instance.error('Login failed: HTTP ${response.statusCode}', 'AlistApiClient', {
          'status_code': response.statusCode,
          'response': response.body,
        });
      }
    } catch (e) {
      LogService.instance.error('Login exception: $e', 'AlistApiClient');
    }
    
    return false;
  }
  
  // 获取文件列表
  Future<List<AlistFile>?> getFileList(String path) async {
    LogService.instance.debug('Fetching file list for path: $path', 'AlistApiClient');
    
    if (_token == null) {
      LogService.instance.info('Token not available, attempting login', 'AlistApiClient');
      final success = await login();
      if (!success) {
        LogService.instance.error('Login failed, cannot fetch file list', 'AlistApiClient');
        return null;
      }
    }
    
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/fs/list'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _token!,
        },
        body: jsonEncode({
          'path': path,
          'password': '',
          'page': 1,
          'per_page': 0,
          'refresh': false,
        }),
      );
      
      LogService.instance.debug('File list response status: ${response.statusCode}', 'AlistApiClient');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 200) {
          final content = data['data']['content'] as List?;
          if (content != null) {
            final files = content.map((item) {
              // 确保每个文件都有正确的路径信息
              final file = AlistFile.fromJson(item);
              // 如果文件的path字段为空，使用当前目录路径
              if (file.path.isEmpty) {
                return AlistFile(
                  name: file.name,
                  size: file.size,
                  isDir: file.isDir,
                  modified: file.modified,
                  created: file.created,
                  thumb: file.thumb,
                  sign: file.sign,
                  type: file.type,
                  path: path, // 使用当前查询的路径
                  rawUrl: file.rawUrl,
                );
              }
              return file;
            }).toList();
            LogService.instance.info('Retrieved ${files.length} files from path: $path', 'AlistApiClient');
            return files;
          }
        } else {
          LogService.instance.error('File list API error: ${data['message']}', 'AlistApiClient', {
            'code': data['code'],
            'path': path,
          });
        }
      } else {
        LogService.instance.error('File list HTTP error: ${response.statusCode}', 'AlistApiClient', {
          'status_code': response.statusCode,
          'path': path,
          'response': response.body,
        });
      }
    } catch (e) {
      LogService.instance.error('File list exception: $e', 'AlistApiClient', {'path': path});
    }
    
    return null;
  }
  
  // 检查token是否有效
  Future<bool> checkToken() async {
    if (_token == null) {
      LogService.instance.debug('No token available for validation', 'AlistApiClient');
      return false;
    }
    
    LogService.instance.debug('Validating token', 'AlistApiClient');
    
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/fs/list'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _token!,
        },
        body: jsonEncode({
          'path': '/',
          'password': '',
          'page': 1,
          'per_page': 1,
          'refresh': false,
        }),
      );
      
      final isValid = response.statusCode == 200;
      LogService.instance.debug('Token validation result: $isValid', 'AlistApiClient');
      return isValid;
    } catch (e) {
      LogService.instance.warning('Token validation failed: $e', 'AlistApiClient');
      return false;
    }
  }
  
  // 获取单个文件信息（包含下载链接）
  Future<AlistFile?> getFile(String path) async {
    LogService.instance.debug('Fetching file info for: $path', 'AlistApiClient');
    
    if (_token == null) {
      final success = await login();
      if (!success) {
        LogService.instance.error('Login failed, cannot fetch file info', 'AlistApiClient');
        return null;
      }
    }
    
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/fs/get'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _token!,
        },
        body: jsonEncode({
          'path': path,
          'password': '',
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 200) {
          LogService.instance.debug('File info retrieved successfully', 'AlistApiClient');
          return AlistFile.fromJson(data['data']);
        } else {
          LogService.instance.error('File info API error: ${data['message']}', 'AlistApiClient', {
            'code': data['code'],
            'path': path,
          });
        }
      } else {
        LogService.instance.error('File info HTTP error: ${response.statusCode}', 'AlistApiClient', {
          'status_code': response.statusCode,
          'path': path,
        });
      }
    } catch (e) {
      LogService.instance.error('File info exception: $e', 'AlistApiClient', {'path': path});
    }
    
    return null;
  }
  
  // 获取完整的文件URL（包含服务器地址）
  String getFullUrl(String path) {
    final fullUrl = '$_serverUrl$path';
    LogService.instance.debug('Generated full URL: $fullUrl', 'AlistApiClient');
    return fullUrl;
  }
  
  // 获取缩略图URL
  String? getThumbnailUrl(AlistFile file) {
    if (file.thumb?.isNotEmpty == true) {
      String thumbUrl;
      // 如果thumb已经是完整URL（包含http或https），直接使用
      if (file.thumb!.startsWith('http://') || file.thumb!.startsWith('https://')) {
        thumbUrl = file.thumb!;
      } else {
        // 否则拼接服务器URL
        thumbUrl = getFullUrl(file.thumb!);
      }
      LogService.instance.debug('Generated thumbnail URL for ${file.name}: $thumbUrl', 'AlistApiClient');
      return thumbUrl;
    }
    
    // 如果没有缩略图，对于图片文件尝试使用原图作为缩略图
    if (file.isImage) {
      final imageUrl = getDownloadUrlSync(file);
      LogService.instance.debug('Using image URL as thumbnail for ${file.name}: $imageUrl', 'AlistApiClient');
      return imageUrl;
    }
    
    LogService.instance.debug('No thumbnail available for ${file.name}', 'AlistApiClient');
    return null;
  }
  // 获取下载URL（增强版本，通过API获取正确的raw_url）
  Future<String> getDownloadUrl(AlistFile file) async {
    LogService.instance.debug('Getting download URL for ${file.name}', 'AlistApiClient');
    
    // 首先检查文件是否已经有raw_url
    if (file.rawUrl != null && file.rawUrl!.isNotEmpty) {
      String downloadUrl;
      if (file.rawUrl!.startsWith('http://') || file.rawUrl!.startsWith('https://')) {
        downloadUrl = file.rawUrl!;
      } else {
        downloadUrl = getFullUrl(file.rawUrl!);
      }
      LogService.instance.debug('Using existing raw_url for ${file.name}: $downloadUrl', 'AlistApiClient');
      return downloadUrl;
    }
    
    // 如果没有raw_url，通过API获取完整文件信息
    final fullPath = file.path.isEmpty ? '/${file.name}' : '${file.path}/${file.name}';
    LogService.instance.debug('Fetching file details for complete URL: $fullPath', 'AlistApiClient');
    
    final fileInfo = await getFile(fullPath);
    if (fileInfo?.rawUrl != null && fileInfo!.rawUrl!.isNotEmpty) {
      String downloadUrl;
      if (fileInfo.rawUrl!.startsWith('http://') || fileInfo.rawUrl!.startsWith('https://')) {
        downloadUrl = fileInfo.rawUrl!;
      } else {
        downloadUrl = getFullUrl(fileInfo.rawUrl!);
      }
      LogService.instance.debug('Retrieved raw_url via API for ${file.name}: $downloadUrl', 'AlistApiClient');
      return downloadUrl;
    }
    
    // 最后的后备方案：使用/d路径
    final fallbackUrl = '$_serverUrl/d$fullPath';
    LogService.instance.warning('Using fallback download URL for ${file.name}: $fallbackUrl', 'AlistApiClient');
    return fallbackUrl;
  }
  
  // 获取同步下载URL（用于UI显示，不进行API调用）
  String getDownloadUrlSync(AlistFile file) {
    if (file.rawUrl != null && file.rawUrl!.isNotEmpty) {
      String downloadUrl;
      if (file.rawUrl!.startsWith('http://') || file.rawUrl!.startsWith('https://')) {
        downloadUrl = file.rawUrl!;
      } else {
        downloadUrl = getFullUrl(file.rawUrl!);
      }
      LogService.instance.debug('Using raw_url for ${file.name}: $downloadUrl', 'AlistApiClient');
      return downloadUrl;
    }
    
    // 后备方案：使用/d路径，包含完整路径
    final fullPath = file.path.isEmpty ? '/${file.name}' : '${file.path}/${file.name}';
    final downloadUrl = '$_serverUrl/d$fullPath';
    LogService.instance.debug('Using fallback download URL for ${file.name}: $downloadUrl', 'AlistApiClient');
    return downloadUrl;
  }
  
  // 清除配置和 token
  Future<void> clearConfig() async {
    LogService.instance.info('Clearing Alist configuration', 'AlistApiClient');
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serverUrlKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_passwordKey);
    await prefs.remove(_tokenKey);
    
    _serverUrl = null;
    _username = null;
    _password = null;
    _token = null;
    
    LogService.instance.info('Alist configuration cleared', 'AlistApiClient');
  }

  // 重命名文件
  Future<bool> renameFile(String path, String newName) async {
    LogService.instance.info('Renaming file: $path -> $newName', 'AlistApiClient');
    
    if (_token == null) {
      final success = await login();
      if (!success) {
        LogService.instance.error('Login failed, cannot rename file', 'AlistApiClient');
        return false;
      }
    }

    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/fs/rename'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _token!,
        },
        body: jsonEncode({
          'path': path,
          'name': newName,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 200) {
          LogService.instance.info('File renamed successfully', 'AlistApiClient');
          return true;
        } else {
          LogService.instance.error('Rename failed: ${data['message']}', 'AlistApiClient', {
            'code': data['code'],
            'path': path,
            'new_name': newName,
          });
        }
      } else {
        LogService.instance.error('Rename HTTP error: ${response.statusCode}', 'AlistApiClient', {
          'status_code': response.statusCode,
          'response': response.body,
        });
      }
    } catch (e) {
      LogService.instance.error('Rename exception: $e', 'AlistApiClient', {
        'path': path,
        'new_name': newName,
      });
    }

    return false;
  }

  // 删除文件或文件夹
  Future<bool> deleteFiles(String dir, List<String> names) async {
    LogService.instance.info('Deleting files: ${names.join(', ')} from $dir', 'AlistApiClient');
    
    if (_token == null) {
      final success = await login();
      if (!success) {
        LogService.instance.error('Login failed, cannot delete files', 'AlistApiClient');
        return false;
      }
    }

    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/fs/remove'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _token!,
        },
        body: jsonEncode({
          'dir': dir,
          'names': names,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 200) {
          LogService.instance.info('Files deleted successfully', 'AlistApiClient');
          return true;
        } else {
          LogService.instance.error('Delete failed: ${data['message']}', 'AlistApiClient', {
            'code': data['code'],
            'dir': dir,
            'names': names,
          });
        }
      } else {
        LogService.instance.error('Delete HTTP error: ${response.statusCode}', 'AlistApiClient', {
          'status_code': response.statusCode,
          'response': response.body,
        });
      }
    } catch (e) {
      LogService.instance.error('Delete exception: $e', 'AlistApiClient', {
        'dir': dir,
        'names': names,
      });
    }

    return false;
  }

  // 创建文件夹
  Future<bool> createFolder(String path) async {
    LogService.instance.info('Creating folder: $path', 'AlistApiClient');
    
    if (_token == null) {
      final success = await login();
      if (!success) {
        LogService.instance.error('Login failed, cannot create folder', 'AlistApiClient');
        return false;
      }
    }

    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/fs/mkdir'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _token!,
        },
        body: jsonEncode({
          'path': path,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 200) {
          LogService.instance.info('Folder created successfully', 'AlistApiClient');
          return true;
        } else {
          LogService.instance.error('Create folder failed: ${data['message']}', 'AlistApiClient', {
            'code': data['code'],
            'path': path,
          });
        }
      } else {
        LogService.instance.error('Create folder HTTP error: ${response.statusCode}', 'AlistApiClient', {
          'status_code': response.statusCode,
          'response': response.body,
        });
      }
    } catch (e) {
      LogService.instance.error('Create folder exception: $e', 'AlistApiClient', {
        'path': path,
      });
    }

    return false;
  }

  // 搜索文件
  Future<List<AlistFile>?> searchFiles({
    required String parent,
    required String keywords,
    int scope = 0, // 0-全部 1-文件夹 2-文件
    int page = 1,
    int perPage = 30,
  }) async {
    LogService.instance.debug('Searching files: keywords="$keywords", scope=$scope', 'AlistApiClient');
    
    if (_token == null) {
      final success = await login();
      if (!success) {
        LogService.instance.error('Login failed, cannot search files', 'AlistApiClient');
        return null;
      }
    }

    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/api/fs/search'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _token!,
        },
        body: jsonEncode({
          'parent': parent,
          'keywords': keywords,
          'scope': scope,
          'page': page,
          'per_page': perPage,
          'password': '',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 200) {
          final content = data['data']['content'] as List?;
          if (content != null) {
            final files = content.map((item) => AlistFile.fromJson(item)).toList();
            LogService.instance.info('Found ${files.length} files matching "$keywords"', 'AlistApiClient');
            return files;
          }
        } else {
          LogService.instance.error('Search failed: ${data['message']}', 'AlistApiClient', {
            'code': data['code'],
            'keywords': keywords,
          });
        }
      } else {
        LogService.instance.error('Search HTTP error: ${response.statusCode}', 'AlistApiClient', {
          'status_code': response.statusCode,
          'response': response.body,
        });
      }
    } catch (e) {
      LogService.instance.error('Search exception: $e', 'AlistApiClient', {
        'keywords': keywords,
      });
    }

    return null;
  }
  
  // Getter 方法
  String? get serverUrl => _serverUrl;
  String? get username => _username;
  String? get token => _token;
}

// Alist 文件模型
class AlistFile {
  final String name;
  final int size;
  final bool isDir;
  final DateTime modified;
  final DateTime created;
  final String? thumb;
  final String sign;
  final int type;
  final String path;
  final String? rawUrl;
  
  AlistFile({
    required this.name,
    required this.size,
    required this.isDir,
    required this.modified,
    required this.created,
    this.thumb,
    required this.sign,
    required this.type,
    required this.path,
    this.rawUrl,
  });
  
  factory AlistFile.fromJson(Map<String, dynamic> json) {
    return AlistFile(
      name: json['name'] ?? '',
      size: json['size'] ?? 0,
      isDir: json['is_dir'] ?? false,
      modified: DateTime.tryParse(json['modified'] ?? '') ?? DateTime.now(),
      created: DateTime.tryParse(json['created'] ?? '') ?? DateTime.now(),
      thumb: json['thumb']?.isEmpty == true ? null : json['thumb'],
      sign: json['sign'] ?? '',
      type: json['type'] ?? 0,
      path: json['path'] ?? '',
      rawUrl: json['raw_url'],
    );
  }
  
  // 是否为图片文件
  bool get isImage {
    final ext = name.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].contains(ext);
  }
  
  // 格式化文件大小
  String get formattedSize {
    if (size == 0) return '0 B';
    
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double fileSize = size.toDouble();
    
    while (fileSize >= 1024 && i < suffixes.length - 1) {
      fileSize /= 1024;
      i++;
    }
    
    return '${fileSize.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
}