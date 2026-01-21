import 'package:go_router/go_router.dart';
import '../features/calendar/presentation/calendar_page.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const CalendarPage(),
    ),
  ],
);
