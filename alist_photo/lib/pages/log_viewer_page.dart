import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/log_service.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  LogLevel? _selectedLevel;
  String? _selectedSource;
  late List<LogEntry> _filteredLogs;
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _updateFilteredLogs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateFilteredLogs() {
    setState(() {
      _filteredLogs = LogService.instance.getFilteredLogs(
        minLevel: _selectedLevel,
        source: _selectedSource,
      );
    });
    
    if (_autoScroll && _filteredLogs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  Set<String> get _availableSources {
    final sources = LogService.instance.logs
        .map((e) => e.source)
        .where((source) => source != null)
        .cast<String>()
        .toSet();
    sources.add('All');
    return sources;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志查看'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'refresh':
                  _updateFilteredLogs();
                  break;
                case 'clear':
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('确认清除'),
                      content: const Text('确定要清除所有日志吗？此操作无法撤销。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('确认'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await LogService.instance.clearLogs();
                    _updateFilteredLogs();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('日志已清除')),
                      );
                    }
                  }
                  break;
                case 'export':
                  final logs = await LogService.instance.exportLogs();
                  await Share.share(logs, subject: 'Alist Photo 日志');
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('刷新'),
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.clear_all),
                  title: Text('清除日志'),
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.share),
                  title: Text('导出日志'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 过滤器
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<LogLevel?>(
                    initialValue: _selectedLevel,
                    decoration: const InputDecoration(
                      labelText: '日志级别',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<LogLevel?>(
                        value: null,
                        child: Text('全部'),
                      ),
                      ...LogLevel.values.map((level) => DropdownMenuItem(
                        value: level,
                        child: Row(
                          children: [
                            Text(LogEntry(
                              timestamp: DateTime.now(),
                              level: level,
                              message: '',
                            ).levelIcon),
                            const SizedBox(width: 8),
                            Text(level.name.toUpperCase()),
                          ],
                        ),
                      )),
                    ],
                    onChanged: (value) {
                      _selectedLevel = value;
                      _updateFilteredLogs();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedSource == 'All' ? null : _selectedSource,
                    decoration: const InputDecoration(
                      labelText: '来源',
                      border: OutlineInputBorder(),
                    ),
                    items: _availableSources.map((source) => DropdownMenuItem(
                      value: source == 'All' ? null : source,
                      child: Text(source),
                    )).toList(),
                    onChanged: (value) {
                      _selectedSource = value;
                      _updateFilteredLogs();
                    },
                  ),
                ),
              ],
            ),
          ),
          // 自动滚动开关
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Checkbox(
                  value: _autoScroll,
                  onChanged: (value) {
                    setState(() {
                      _autoScroll = value ?? false;
                    });
                  },
                ),
                const Text('自动滚动到底部'),
                const Spacer(),
                Text('共 ${_filteredLogs.length} 条'),
              ],
            ),
          ),
          const Divider(height: 1),
          // 日志列表
          Expanded(
            child: _filteredLogs.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.description, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('暂无日志', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _filteredLogs.length,
                    itemBuilder: (context, index) {
                      final entry = _filteredLogs[index];
                      return _buildLogItem(entry);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _autoScroll
          ? null
          : FloatingActionButton.small(
              onPressed: () {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                  );
                }
              },
              child: const Icon(Icons.keyboard_arrow_down),
            ),
    );
  }

  Widget _buildLogItem(LogEntry entry) {
    final levelColor = _getLevelColor(entry.level);
    
    return InkWell(
      onLongPress: () {
        // 长按复制日志内容
        final logText = '[${entry.timestamp.toIso8601String()}] ${entry.level.name.toUpperCase()} ${entry.source ?? 'APP'}: ${entry.message}';
        Clipboard.setData(ClipboardData(text: logText));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('日志已复制到剪贴板')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: levelColor,
              width: 4,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  entry.levelIcon,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.level.name.toUpperCase(),
                  style: TextStyle(
                    color: levelColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                if (entry.source != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      entry.source!,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  entry.formattedTimestamp,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              entry.message,
              style: const TextStyle(fontSize: 14),
            ),
            if (entry.extra != null && entry.extra!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.extra.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}