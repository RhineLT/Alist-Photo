import 'dart:io';
import 'package:path_provider/path_provider.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error,
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? source;
  final Map<String, dynamic>? extra;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.source,
    this.extra,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'message': message,
      'source': source,
      'extra': extra,
    };
  }

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.parse(json['timestamp']),
      level: LogLevel.values.firstWhere((e) => e.name == json['level']),
      message: json['message'],
      source: json['source'],
      extra: json['extra'],
    );
  }

  String get levelIcon {
    switch (level) {
      case LogLevel.debug:
        return '🐛';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }

  String get formattedTimestamp {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
           '${timestamp.minute.toString().padLeft(2, '0')}:'
           '${timestamp.second.toString().padLeft(2, '0')}';
  }
}

class LogService {
  static LogService? _instance;
  static LogService get instance {
    _instance ??= LogService._();
    return _instance!;
  }
  
  LogService._();

  final List<LogEntry> _logs = [];
  final int _maxLogs = 1000; // 最多保存1000条日志
  final bool _enableFileLogging = true;
  File? _logFile;

  List<LogEntry> get logs => List.unmodifiable(_logs);

  Future<void> initialize() async {
    if (_enableFileLogging) {
      try {
        final directory = await getApplicationDocumentsDirectory();
        _logFile = File('${directory.path}/alist_photo.log');
        await _loadLogsFromFile();
      } catch (e) {
        _log(LogLevel.warning, 'Failed to initialize file logging: $e', 'LogService');
      }
    }
    
    _log(LogLevel.info, 'LogService initialized', 'LogService');
  }

  void debug(String message, [String? source, Map<String, dynamic>? extra]) {
    _log(LogLevel.debug, message, source, extra);
  }

  void info(String message, [String? source, Map<String, dynamic>? extra]) {
    _log(LogLevel.info, message, source, extra);
  }

  void warning(String message, [String? source, Map<String, dynamic>? extra]) {
    _log(LogLevel.warning, message, source, extra);
  }

  void error(String message, [String? source, Map<String, dynamic>? extra]) {
    _log(LogLevel.error, message, source, extra);
  }

  void _log(LogLevel level, String message, [String? source, Map<String, dynamic>? extra]) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      source: source,
      extra: extra,
    );

    _logs.add(entry);
    
    // 保持日志数量在限制范围内
    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }

    // 写入文件
    if (_enableFileLogging && _logFile != null) {
      _writeToFile(entry);
    }

    // 在调试模式下打印到控制台
    if (level == LogLevel.error || level == LogLevel.warning) {
      print('[${entry.formattedTimestamp}] ${entry.levelIcon} $message');
    }
  }

  Future<void> _writeToFile(LogEntry entry) async {
    try {
      final logLine = '[${entry.timestamp.toIso8601String()}] ${entry.level.name.toUpperCase()} ${entry.source ?? 'APP'}: ${entry.message}\n';
      await _logFile!.writeAsString(logLine, mode: FileMode.append);
    } catch (e) {
      // 忽略文件写入错误，避免无限循环
    }
  }

  Future<void> _loadLogsFromFile() async {
    if (_logFile == null || !await _logFile!.exists()) return;

    try {
      final content = await _logFile!.readAsString();
      final lines = content.split('\n').where((line) => line.trim().isNotEmpty).toList();
      
      // 只加载最近的日志条目
      final recentLines = lines.length > _maxLogs ? lines.sublist(lines.length - _maxLogs) : lines;
      
      for (final line in recentLines) {
        try {
          final match = RegExp(r'^\[(.*?)\] (\w+) (.*?): (.*)$').firstMatch(line);
          if (match != null) {
            final timestamp = DateTime.parse(match.group(1)!);
            final levelStr = match.group(2)!.toLowerCase();
            final source = match.group(3);
            final message = match.group(4)!;
            
            final level = LogLevel.values.firstWhere(
              (e) => e.name == levelStr,
              orElse: () => LogLevel.info,
            );
            
            _logs.add(LogEntry(
              timestamp: timestamp,
              level: level,
              message: message,
              source: source,
            ));
          }
        } catch (e) {
          // 忽略解析错误的行
        }
      }
    } catch (e) {
      // 忽略文件读取错误
    }
  }

  Future<void> clearLogs() async {
    _logs.clear();
    if (_logFile != null && await _logFile!.exists()) {
      try {
        await _logFile!.writeAsString('');
      } catch (e) {
        // 忽略文件清理错误
      }
    }
    _log(LogLevel.info, 'Logs cleared', 'LogService');
  }

  List<LogEntry> getFilteredLogs({
    LogLevel? minLevel,
    String? source,
    DateTime? since,
  }) {
    return _logs.where((entry) {
      if (minLevel != null && entry.level.index < minLevel.index) {
        return false;
      }
      if (source != null && entry.source != source) {
        return false;
      }
      if (since != null && entry.timestamp.isBefore(since)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<String> exportLogs() async {
    final buffer = StringBuffer();
    for (final entry in _logs) {
      buffer.writeln('[${entry.timestamp.toIso8601String()}] ${entry.level.name.toUpperCase()} ${entry.source ?? 'APP'}: ${entry.message}');
    }
    return buffer.toString();
  }
}