import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(_serverUrlKey);
    _username = prefs.getString(_usernameKey);
    _password = prefs.getString(_passwordKey);
    _token = prefs.getString(_tokenKey);
  }
  
  // 保存服务器配置
  Future<void> saveConfig({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
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
    if (!isConfigured) return false;
    
    try {
      // 根据Alist API文档，需要在密码后添加后缀再进行SHA256
      final hashedPassword = sha256.convert(utf8.encode('$_password-https://github.com/alist-org/alist')).toString();
      
      final response = await http.post(
        Uri.parse('$_serverUrl/api/auth/login/hash'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _username!,
          'password': hashedPassword,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 200) {
          _token = data['data']['token'];
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_tokenKey, _token!);
          return true;
        }
      }
    } catch (e) {
      // Handle login error silently or log to analytics  
    }
    
    return false;
  }
  
  // 获取文件列表
  Future<List<AlistFile>?> getFileList(String path) async {
    if (_token == null) {
      final success = await login();
      if (!success) return null;
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
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 200) {
          final content = data['data']['content'] as List?;
          if (content != null) {
            return content.map((item) => AlistFile.fromJson(item)).toList();
          }
        }
      }
    } catch (e) {
      // Handle get file list error silently or log to analytics
    }
    
    return null;
  }
  
  // 检查token是否有效
  Future<bool> checkToken() async {
    if (_token == null) return false;
    
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
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  // 获取单个文件信息（包含下载链接）
  Future<AlistFile?> getFile(String path) async {
    if (_token == null) {
      final success = await login();
      if (!success) return null;
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
          return AlistFile.fromJson(data['data']);
        }
      }
    } catch (e) {
      // Handle get file error silently or log to analytics
    }
    
    return null;
  }
  
  // 获取完整的文件URL（包含服务器地址）
  String getFullUrl(String path) {
    return '$_serverUrl$path';
  }
  
  // 获取缩略图URL
  String? getThumbnailUrl(AlistFile file) {
    if (file.thumb?.isNotEmpty == true) {
      return getFullUrl(file.thumb!);
    }
    return null;
  }
  
  // 获取下载URL
  String getDownloadUrl(AlistFile file) {
    // 优先使用raw_url，如果没有则使用传统方式
    if (file.rawUrl != null && file.rawUrl!.isNotEmpty) {
      return file.rawUrl!;
    }
    // 后备方案：使用/d路径
    return '$_serverUrl/d${file.path}/${file.name}';
  }
  
  // 清除配置和 token
  Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serverUrlKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_passwordKey);
    await prefs.remove(_tokenKey);
    
    _serverUrl = null;
    _username = null;
    _password = null;
    _token = null;
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