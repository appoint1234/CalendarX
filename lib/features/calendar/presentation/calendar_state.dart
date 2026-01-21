import 'package:flutter_riverpod/legacy.dart';

enum CalendarTab { month, week, day }

final calendarTabProvider = StateProvider<CalendarTab>((ref) => CalendarTab.month);

final visibleDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

