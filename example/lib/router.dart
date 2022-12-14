import 'package:go_router/go_router.dart';

import 'pages/home_page.dart';
import 'pages/conversation_page.dart';

/// Create the [GoRouter] for navigating within the app.
GoRouter createRouter() => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          name: 'home',
          builder: (context, state) => const HomePage(),
          routes: [
            GoRoute(
              path: 'conversation/:topic',
              name: 'conversation',
              builder: (context, state) => ConversationPage(
                topic: state.params['topic']!,
              ),
            ),
          ],
        ),
      ],
    );
