import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/agenda/agenda_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/auth/welcome_screen.dart';
import '../../features/gifts/gifts_screen.dart';
import '../../features/groups/group_detail_screen.dart';
import '../../features/groups/group_form_screen.dart';
import '../../features/groups/invite_links.dart';
import '../../features/groups/join_group_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/messages/message_screen.dart';
import '../../features/people/import_contacts_screen.dart';
import '../../features/people/people_screen.dart';
import '../../features/people/person_detail_screen.dart';
import '../../features/people/person_form_screen.dart';
import '../../features/profile/categories_screen.dart';
import '../../features/profile/payment_details_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/shell/main_shell.dart';
import '../providers.dart';
import '../utils/errors.dart';
import '../widgets/common.dart';

const _publicRoutes = {'/welcome', '/login', '/register', '/forgot-password'};

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final refresh = _AuthRefresh(auth.changes);
  ref.onDispose(refresh.dispose);

  // Convite aberto sem sessão: retomado depois de entrar ou criar conta.
  String? pendingInvite;

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = auth.current != null;
      final loc = state.matchedLocation;
      final public = _publicRoutes.contains(loc);
      if (!loggedIn && !public) {
        if (loc.startsWith('/join/')) pendingInvite = loc;
        return '/welcome';
      }
      if (loggedIn && public) {
        final next = pendingInvite ?? '/home';
        pendingInvite = null;
        return next;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(
        path: '/join/:code',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => JoinGroupScreen(code: s.pathParameters['code']!),
      ),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/reset-password', builder: (_, _) => const ResetPasswordScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/agenda', builder: (_, _) => const AgendaScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/people', builder: (_, _) => const PeopleScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/gifts', builder: (_, _) => const GiftsScreen())],
          ),
        ],
      ),
      GoRoute(path: '/person/new', parentNavigatorKey: _rootKey, builder: (_, _) => const PersonFormScreen()),
      GoRoute(path: '/import', parentNavigatorKey: _rootKey, builder: (_, _) => const ImportContactsScreen()),
      GoRoute(
        path: '/person/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => PersonDetailScreen(personId: s.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            parentNavigatorKey: _rootKey,
            builder: (_, s) => PersonFormScreen(personId: s.pathParameters['id']),
          ),
          GoRoute(
            path: 'message',
            parentNavigatorKey: _rootKey,
            builder: (_, s) => MessageScreen(personId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/groups/new',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => GroupFormScreen(personId: s.uri.queryParameters['personId']),
      ),
      GoRoute(
        path: '/groups/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => GroupDetailScreen(groupId: s.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            parentNavigatorKey: _rootKey,
            builder: (_, s) => GroupFormScreen(groupId: s.pathParameters['id']),
          ),
        ],
      ),
      GoRoute(
        path: '/profile',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ProfileScreen(),
        routes: [
          GoRoute(path: 'categories', parentNavigatorKey: _rootKey, builder: (_, _) => const CategoriesScreen()),
          GoRoute(path: 'payments', parentNavigatorKey: _rootKey, builder: (_, _) => const PaymentDetailsScreen()),
        ],
      ),
    ],
  );

  // O link do email de recuperação abre a app com uma sessão temporária.
  final recovery = auth.passwordRecovery.listen((_) => router.go('/reset-password'));
  ref.onDispose(recovery.cancel);

  // Links de convite e de recuperação de palavra-passe (com a app fechada ou aberta).
  Future<void> openLink(Uri? uri) async {
    if (uri == null) return;
    try {
      if (await auth.handleAuthLink(uri)) return;
    } catch (e) {
      final context = _rootKey.currentContext;
      if (context != null && context.mounted) showMessage(context, friendlyError(e));
      return;
    }
    final code = InviteLinks.codeFrom(uri);
    if (code != null) router.go('/join/${code.toUpperCase()}');
  }

  final links = AppLinks();
  links.getInitialLink().then(openLink).catchError((_) {});
  final linkSub = links.uriLinkStream.listen(openLink, onError: (_) {});
  ref.onDispose(linkSub.cancel);
  return router;
});

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<Object?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
