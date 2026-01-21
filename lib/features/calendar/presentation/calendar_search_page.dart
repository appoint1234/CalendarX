import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/db_provider.dart';

class CalendarSearchPage extends ConsumerStatefulWidget {
  const CalendarSearchPage({super.key});

  @override
  ConsumerState<CalendarSearchPage> createState() => _CalendarSearchPageState();
}

enum SearchRangePreset { today, thisWeek, thisMonth, custom }

class _CalendarSearchPageState extends ConsumerState<CalendarSearchPage> {
  final _ctrl = TextEditingController();

  SearchRangePreset _preset = SearchRangePreset.thisWeek;
  DateTimeRange? _customRange;

  bool _onlySubscribed = false;
  bool _allDayOnly = false;
  bool _hasReminderOnly = false;

  DateTimeRange _resolveRange() {
    final now = DateTime.now();
    DateTime start;
    DateTime end;

    switch (_preset) {
      case SearchRangePreset.today:
        start = DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
        break;
      case SearchRangePreset.thisWeek:
        final d = DateTime(now.year, now.month, now.day);
        final monday = d.subtract(Duration(days: d.weekday - DateTime.monday));
        start = DateTime(monday.year, monday.month, monday.day);
        end = start.add(const Duration(days: 7));
        break;
      case SearchRangePreset.thisMonth:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 1);
        break;
      case SearchRangePreset.custom:
        final r = _customRange;
        if (r != null) {
          start = DateTime(r.start.year, r.start.month, r.start.day);
          // end 做成 [start, end)
          end = DateTime(r.end.year, r.end.month, r.end.day).add(const Duration(days: 1));
        } else {
          start = DateTime(now.year, now.month, now.day);
          end = start.add(const Duration(days: 7));
        }
        break;
    }
    return DateTimeRange(start: start, end: end);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: _customRange ?? DateTimeRange(start: now, end: now.add(const Duration(days: 7))),
    );
    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _preset = SearchRangePreset.custom;
    });
  }

  String _presetLabel() {
    switch (_preset) {
      case SearchRangePreset.today:
        return '今天';
      case SearchRangePreset.thisWeek:
        return '本周';
      case SearchRangePreset.thisMonth:
        return '本月';
      case SearchRangePreset.custom:
        return '自定义';
    }
  }

  String _rangeText(DateTimeRange r) {
    final f = DateFormat('MM/dd');
    final s = f.format(r.start);
    final e = f.format(r.end.subtract(const Duration(days: 1)));
    return '$s - $e';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDbProvider);
    final range = _resolveRange();
    final keyword = _ctrl.text;

    return Scaffold(
      appBar: AppBar(title: const Text('搜索日程')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '标题/描述/订阅源',
                suffixIcon: keyword.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        onPressed: () => setState(() => _ctrl.clear()),
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: Text('${_presetLabel()} · ${_rangeText(range)}'),
                  avatar: const Icon(Icons.calendar_month, size: 18),
                  onPressed: () async {
                    final v = await showModalBottomSheet<SearchRangePreset>(
                      context: context,
                      showDragHandle: true,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              title: const Text('今天'),
                              trailing: _preset == SearchRangePreset.today ? const Icon(Icons.check) : null,
                              onTap: () => Navigator.pop(ctx, SearchRangePreset.today),
                            ),
                            ListTile(
                              title: const Text('本周'),
                              trailing: _preset == SearchRangePreset.thisWeek ? const Icon(Icons.check) : null,
                              onTap: () => Navigator.pop(ctx, SearchRangePreset.thisWeek),
                            ),
                            ListTile(
                              title: const Text('本月'),
                              trailing: _preset == SearchRangePreset.thisMonth ? const Icon(Icons.check) : null,
                              onTap: () => Navigator.pop(ctx, SearchRangePreset.thisMonth),
                            ),
                            ListTile(
                              title: const Text('自定义…'),
                              trailing: _preset == SearchRangePreset.custom ? const Icon(Icons.check) : null,
                              onTap: () => Navigator.pop(ctx, SearchRangePreset.custom),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    );

                    if (v == null) return;
                    if (v == SearchRangePreset.custom) {
                      await _pickCustomRange();
                    } else {
                      setState(() => _preset = v);
                    }
                  },
                ),
                FilterChip(
                  label: const Text('仅订阅'),
                  selected: _onlySubscribed,
                  onSelected: (v) => setState(() => _onlySubscribed = v),
                ),
                FilterChip(
                  label: const Text('全天'),
                  selected: _allDayOnly,
                  onSelected: (v) => setState(() => _allDayOnly = v),
                ),
                FilterChip(
                  label: const Text('有提醒'),
                  selected: _hasReminderOnly,
                  onSelected: (v) => setState(() => _hasReminderOnly = v),
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            Expanded(
              child: FutureBuilder<List<EventSearchRow>>(
                future: db.searchEvents(
                  keyword: keyword,
                  from: range.start,
                  to: range.end,
                  onlySubscribed: _onlySubscribed ? true : null,
                  allDay: _allDayOnly ? true : null,
                  hasReminder: _hasReminderOnly ? true : null,
                  limit: 200,
                ),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) return Center(child: Text('搜索失败：${snap.error}'));

                  final list = snap.data ?? const [];
                  if (list.isEmpty) {
                    return Center(
                      child: Text(
                        keyword.trim().isEmpty ? '没有符合条件的日程' : '没有搜索到结果',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 8),
                    itemBuilder: (_, i) {
                      final row = list[i];
                      final e = row.event;
                      final time = DateFormat('MM/dd HH:mm').format(e.startAt);
                      final end = DateFormat('HH:mm').format(e.endAt);
                      final subtitle = <String>[
                        '$time-$end',
                        if (row.sourceName != null) '订阅：${row.sourceName}',
                        if (e.allDay) '全天',
                        if ((e.remindBeforeMinutes ?? 0) > 0) '提醒：提前${e.remindBeforeMinutes}min',
                      ].join(' · ');

                      return ListTile(
                        leading: const Icon(Icons.event_note),
                        title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(context, row),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
