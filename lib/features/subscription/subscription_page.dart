import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/db/db_provider.dart';
import 'subscription_sync_service.dart';
import 'sync_logs_page.dart';


class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDbProvider);
    final sourcesStream = db.watchSources();
    final sync = SubscriptionSyncService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('订阅管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              final sources = await db.select(db.calendarSources).get();
              for (final s in sources) {
                await sync.syncSource(db, sourceId: s.id);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已刷新所有订阅')),
                );
              }
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          final nameCtrl = TextEditingController();
          final urlCtrl = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('添加订阅'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称')),
                  TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'ICS URL')),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('添加')),
              ],
            ),
          );

          if (ok == true) {
            await sync.addSourceAndSync(
              db,
              name: nameCtrl.text.trim().isEmpty ? '订阅' : nameCtrl.text.trim(),
              url: urlCtrl.text.trim(),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已添加并同步')),
              );
            }
          }
        },
      ),
      body: StreamBuilder(
        stream: sourcesStream,
        builder: (context, snapshot) {
          final list = snapshot.data ?? const [];
          if (list.isEmpty) {
            return const Center(child: Text('暂无订阅'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = list[i];
              return ListTile(
                title: Text(s.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    StreamBuilder(
                      stream: db.watchSyncLogsBySource(s.id, limit: 1),
                      builder: (context, snap) {
                        final last = (snap.data ?? const []).isNotEmpty ? snap.data!.first : null;
                        if (last == null) return const Text('最近同步：暂无记录');
                        final text = '最近同步：${last.status}'
                            '${last.httpStatus != null ? ' · HTTP ${last.httpStatus}' : ''}'
                            '${last.itemCount != null ? ' · ${last.itemCount}条' : ''}'
                            '${last.durationMs != null ? ' · ${last.durationMs}ms' : ''}';
                        return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
                      },
                    ),
                  ],
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '日志',
                      icon: const Icon(Icons.receipt_long),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SyncLogsPage(sourceId: s.id, sourceName: s.name),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async => db.deleteSourceById(s.id),
                    ),
                  ],
                ),
                onTap: () async {
                  await sync.syncSource(db, sourceId: s.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已刷新：${s.name}')),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
