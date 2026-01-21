import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/db/db_provider.dart';
import 'package:intl/intl.dart';

class SyncLogsPage extends ConsumerWidget {
  final int sourceId;
  final String sourceName;
  const SyncLogsPage({super.key, required this.sourceId, required this.sourceName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDbProvider);

    return Scaffold(
      appBar: AppBar(title: Text('同步日志 - $sourceName')),
      body: StreamBuilder(
        stream: db.watchSyncLogsBySource(sourceId, limit: 50),
        builder: (context, snapshot) {
          final list = snapshot.data ?? const [];
          if (list.isEmpty) return const Center(child: Text('暂无同步记录'));
          final fmt = DateFormat('MM-dd HH:mm:ss');

          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final log = list[i];
              final title = '${log.status}'
                  '${log.httpStatus != null ? ' · HTTP ${log.httpStatus}' : ''}'
                  '${log.itemCount != null ? ' · ${log.itemCount}条' : ''}'
                  '${log.durationMs != null ? ' · ${log.durationMs}ms' : ''}';

              final time = '${fmt.format(log.startedAt)}'
                  '${log.finishedAt != null ? ' → ${fmt.format(log.finishedAt!)}' : ''}';

              return ListTile(
                title: Text(title),
                subtitle: Text([time, if (log.message != null && log.message!.isNotEmpty) log.message!].join('\n')),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}
