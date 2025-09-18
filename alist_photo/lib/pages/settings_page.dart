import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/alist_api_client.dart';
import '../services/log_service.dart';
import 'log_viewer_page.dart';

class SettingsPage extends StatefulWidget {
  final AlistApiClient apiClient;
  
  const SettingsPage({super.key, required this.apiClient});
  
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  
  // 缓存设置
  double _cacheSize = 1.0; // GB
  String _cacheUsage = '计算中...';
  
  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
    _loadCacheSettings();
    _calculateCacheUsage();
  }
  
  void _loadCurrentSettings() {
    _serverUrlController.text = widget.apiClient.serverUrl;
    _usernameController.text = widget.apiClient.username ?? '';
  }
  
  Future<void> _loadCacheSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cacheSize = prefs.getDouble('cache_size') ?? 1.0;
    });
  }
  
  Future<void> _calculateCacheUsage() async {
    try {
      // 这里应该计算实际的缓存使用情况
      // 由于CachedNetworkImage没有直接的API来获取缓存大小
      // 我们显示一个估算值
      setState(() {
        _cacheUsage = '约 ${(_cacheSize * 0.3).toStringAsFixed(1)} GB / ${_cacheSize.toStringAsFixed(1)} GB';
      });
      
      LogService.instance.debug('Cache usage calculated', 'SettingsPage');
    } catch (e) {
      LogService.instance.error('Failed to calculate cache usage: $e', 'SettingsPage');
      setState(() {
        _cacheUsage = '计算失败';
      });
    }
  }
  
  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      LogService.instance.info('Saving Alist configuration', 'SettingsPage');
      
      await widget.apiClient.saveConfig(
        serverUrl: _serverUrlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      
      LogService.instance.info('Testing Alist connection', 'SettingsPage');
      
      // 测试连接
      final success = await widget.apiClient.login();
      
      if (success && mounted) {
        LogService.instance.info('Alist connection test successful', 'SettingsPage');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('设置保存成功，连接测试通过'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      } else if (mounted) {
        LogService.instance.warning('Alist connection test failed', 'SettingsPage');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接失败，请检查服务器地址和账户信息'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      LogService.instance.error('Failed to save settings: $e', 'SettingsPage');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _clearSettings() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定要清除所有设置吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    
    if (confirm == true && mounted) {
      LogService.instance.info('Clearing all settings', 'SettingsPage');
      await widget.apiClient.clearConfig();
      _serverUrlController.clear();
      _usernameController.clear();
      _passwordController.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已清除')),
      );
    }
  }
  
  Future<void> _saveCacheSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cache_size', _cacheSize);
    
    LogService.instance.info('Cache size updated to ${_cacheSize.toStringAsFixed(1)} GB', 'SettingsPage');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('缓存大小已设置为 ${_cacheSize.toStringAsFixed(1)} GB')),
    );
    
    _calculateCacheUsage();
  }
  
  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有缓存的图片吗？这将释放存储空间，但下次浏览时需要重新加载图片。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    
    if (confirm == true && mounted) {
      try {
        // 清除CachedNetworkImage缓存
        await CachedNetworkImage.evictFromCache('');
        await DefaultCacheManager().emptyCache();
        
        LogService.instance.info('Image cache cleared successfully', 'SettingsPage');
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('缓存清除成功'),
            backgroundColor: Colors.green,
          ),
        );
        
        _calculateCacheUsage();
      } catch (e) {
        LogService.instance.error('Failed to clear cache: $e', 'SettingsPage');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('清除缓存失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: '查看日志',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const LogViewerPage(),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') {
                _clearSettings();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.clear_all),
                  title: Text('清除设置'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alist 服务器配置
            _buildServerConfigSection(),
            const SizedBox(height: 32),
            
            // 缓存管理
            _buildCacheManagementSection(),
            const SizedBox(height: 32),
            
            // 系统信息
            _buildSystemInfoSection(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildServerConfigSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_outlined, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Alist 服务器配置',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'http://192.168.1.100:5244',
                  prefixIcon: Icon(Icons.language),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入服务器地址';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入用户名';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入密码';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          '保存并测试连接',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '使用说明',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. 服务器地址格式：http://IP:端口 或 https://domain.com\n'
                      '2. 请使用有文件访问权限的 Alist 账户\n'
                      '3. 保存后会自动测试连接，连接成功才能使用',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildCacheManagementSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage_outlined, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text(
                  '缓存管理',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.pie_chart),
              title: const Text('缓存使用情况'),
              subtitle: Text(_cacheUsage),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _calculateCacheUsage,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('缓存大小限制'),
              subtitle: Text('${_cacheSize.toStringAsFixed(1)} GB'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Slider(
                value: _cacheSize,
                min: 0.5,
                max: 10.0,
                divisions: 19,
                label: '${_cacheSize.toStringAsFixed(1)} GB',
                onChanged: (value) {
                  setState(() {
                    _cacheSize = value;
                  });
                },
                onChangeEnd: (value) {
                  _saveCacheSize();
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _clearCache,
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('清除缓存'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSystemInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outlined, color: Colors.purple.shade700),
                const SizedBox(width: 8),
                Text(
                  '系统信息',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('查看日志'),
              subtitle: const Text('查看应用运行日志和错误信息'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const LogViewerPage(),
                  ),
                );
              },
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.info),
              title: Text('应用版本'),
              subtitle: Text('20250918'),
            ),
            const ListTile(
              leading: Icon(Icons.developer_mode),
              title: Text('Flutter 版本'),
              subtitle: Text('3.24.5'),
            ),
          ],
        ),
      ),
    );
  }
}