import "package:flutter/material.dart";
import "services/alist_api_client.dart";
import "services/log_service.dart";
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
      await _apiClient.initialize();
      
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
