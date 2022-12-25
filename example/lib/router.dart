import 'package:go_router/go_router.dart';

import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/conversation_page.dart';
import 'session.dart';

/// Create the [GoRouter] for navigating within the app.
GoRouter createRouter() => GoRouter(
      // Listen to session changes to re-evaluate whether we need to login.
      refreshListenable: session,
      // When the session is not initialized go to the login page.
      redirect: (context, state) => session.initialized ? null : '/login',
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
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (context, state) => const LoginPage(),
        ),
      ],
    );
