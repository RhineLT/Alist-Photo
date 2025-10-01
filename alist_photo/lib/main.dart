import "package:flutter/material.dart";
import "services/alist_api_client.dart";
import "services/log_service.dart";
import "services/media_cache_manager.dart";
import 'dart:io';
import "package:permission_handler/permission_handler.dart";
import "pages/home_page.dart";

void main() async {
  // 确保Flutter绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化日志服务
  await LogService.instance.initialize();
  LogService.instance.info('Alist Photo app starting', 'Main');
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AlistApiClient _apiClient = AlistApiClient();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      LogService.instance.info('Initializing Alist API client', 'Main');
      
      // iOS 不需要显式请求存储权限（文件访问权限通过系统选择器自动处理）
      // Android 才需要请求存储权限
      bool granted = true;
      if (Platform.isAndroid) {
        try {
          final status = await Permission.storage.status;
          if (!status.isGranted) {
            final req = await Permission.storage.request();
            granted = req.isGranted;
          }
        } catch (e) {
          LogService.instance.warning('Failed to check storage permission: $e', 'Main');
          // 即使权限检查失败也继续初始化
        }
      }

      if (!granted) {
        LogService.instance.warning('Storage permission not granted. App will request again later.', 'Main');
      }

      // 初始化 API 客户端
      await _apiClient.initialize();
      
      // 初始化媒体缓存管理器
      await MediaCacheManager.instance.initialize();
      
      setState(() {
        _isInitialized = true;
      });
      
      LogService.instance.info('App initialization completed', 'Main');
    } catch (e, stackTrace) {
      LogService.instance.error('App initialization failed: $e\n$stackTrace', 'Main');
      // 即使初始化失败也要继续，让用户可以看到界面
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Alist Photo",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
        ),
      ),
      home: _isInitialized 
          ? HomePage(apiClient: _apiClient)
          : const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在初始化...'),
                  ],
                ),
              ),
            ),
    );
  }
}
