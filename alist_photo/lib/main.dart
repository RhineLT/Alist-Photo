import "package:flutter/material.dart";
import "services/alist_api_client.dart";
import "pages/home_page.dart";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final AlistApiClient _apiClient = AlistApiClient();

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
      home: HomePage(apiClient: _apiClient),
    );
  }
}
