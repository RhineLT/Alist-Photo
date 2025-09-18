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
      // 先检查/请求存储权限（Android <= 29 需要；>=30 写 app-scoped 目录不强制，但这里统一 gating）
      bool granted = true;
      if (Platform.isAndroid) {
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          final req = await Permission.storage.request();
          granted = req.isGranted;
        }
      }

      if (!granted) {
        LogService.instance.warning('Storage permission not granted. App will request again later.', 'Main');
      }

      await _apiClient.initialize();
      // 初始化外部文件缓存（内部也会最小化处理权限）
      await MediaCacheManager.instance.initialize();
      
      setState(() {
        _isInitialized = true;
      });
      
      LogService.instance.info('App initialization completed', 'Main');
    } catch (e) {
      LogService.instance.error('App initialization failed: $e', 'Main');
      setState(() {
        _isInitialized = true; // 继续加载，即使初始化失败
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
