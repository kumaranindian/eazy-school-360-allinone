import 'package:go_router/go_router.dart';

import 'pages/conversation_page.dart';
import 'pages/conversations_page.dart';
import 'pages/new_conversation_page.dart';

/// `/messages/**` share one shell branch. `new` precedes the parameter.
List<RouteBase> messageRoutes() => [
  GoRoute(
    path: '/messages',
    builder: (context, state) => const ConversationsPage(),
    routes: [
      GoRoute(
        path: 'new',
        builder: (context, state) => const NewConversationPage(),
      ),
      GoRoute(
        path: ':conversationId',
        builder: (context, state) => ConversationPage(
          conversationId: state.pathParameters['conversationId']!,
          branchId: state.uri.queryParameters['branchId'],
        ),
      ),
    ],
  ),
];
