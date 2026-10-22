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
import '../../features/cards/card_links.dart';
import '../../features/cards/card_screen.dart';
import '../../features/cards/album_screen.dart';
import '../../features/cards/wall_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chat/chat_settings_screen.dart';
import '../../features/chat/conversation_info_screen.dart';
import '../../features/chat/safety.dart';
import '../../features/chat/friends_screen.dart';
import '../../features/gifts/gifts_screen.dart';
import '../../features/groups/group_detail_screen.dart';
import '../../features/groups/group_form_screen.dart';
import '../../features/groups/invite_links.dart';
import '../../features/groups/join_group_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/messages/message_screen.dart';
import '../../features/people/people_screen.dart';
import '../../features/people/history_screen.dart';
import '../../features/people/import_contacts_screen.dart';
import '../../features/people/onboarding.dart';
import '../../features/people/pending_answers_screen.dart';
import '../../features/people/person_detail_screen.dart';
import '../../features/people/person_form_screen.dart';
import '../../features/profile/categories_screen.dart';
import '../../features/profile/payment_details_screen.dart';
import '../../features/profile/accessibility_screen.dart';
import '../../features/profile/legal.dart';
import '../../features/profile/plans_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../services/deferred_link.dart';
import '../../services/notification_service.dart';
import '../../services/reminder_copy.dart';
import '../providers.dart';
import '../utils/errors.dart';
import '../widgets/common.dart';

const _publicRoutes = {'/welcome', '/login', '/register', '/forgot-password'};

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final refresh = _AuthRefresh(auth.changes);
  ref.onDispose(refresh.dispose);

  // Convite ou cartão aberto sem sessão: retomado depois de entrar ou criar conta.
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
        // O cartão lê-se sem conta; para responder, entra-se e volta-se a ele.
        if (loc.startsWith('/card/')) {
          pendingInvite = loc;
          return null;
        }
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
      GoRoute(
        path: '/card/:token',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => CardScreen(token: s.pathParameters['token']!),
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
      GoRoute(
        path: '/chats/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ChatScreen(conversationId: s.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'info',
            parentNavigatorKey: _rootKey,
            builder: (_, s) => ConversationInfoScreen(conversationId: s.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/wall',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const WallScreen(),
        routes: [
          GoRoute(
            path: 'album/:year',
            parentNavigatorKey: _rootKey,
            builder: (_, s) => AlbumScreen(year: int.parse(s.pathParameters['year']!)),
          ),
        ],
      ),
      GoRoute(path: '/friends', parentNavigatorKey: _rootKey, builder: (_, _) => const FriendsScreen()),
      GoRoute(
        path: '/chat-settings',
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ChatSettingsScreen(),
        routes: [
          GoRoute(path: 'blocked', parentNavigatorKey: _rootKey, builder: (_, _) => const BlockedUsersScreen()),
        ],
      ),
      GoRoute(path: '/person/new', parentNavigatorKey: _rootKey, builder: (_, _) => const PersonFormScreen()),
      GoRoute(path: '/people/requests', parentNavigatorKey: _rootKey, builder: (_, _) => const PendingAnswersScreen()),
      GoRoute(
        path: '/people/import',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ImportContactsScreen(
          welcome: s.uri.queryParameters['welcome'] == '1',
          fromCalendar: s.uri.queryParameters['from'] == 'calendar',
        ),
      ),
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
          GoRoute(
            path: 'history',
            parentNavigatorKey: _rootKey,
            builder: (_, s) => HistoryScreen(personId: s.pathParameters['id']!),
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
          GoRoute(path: 'plans', parentNavigatorKey: _rootKey, builder: (_, _) => const PlansScreen()),
          GoRoute(path: 'privacy', parentNavigatorKey: _rootKey, builder: (_, _) => const PrivacyRightsScreen()),
          GoRoute(path: 'accessibility', parentNavigatorKey: _rootKey, builder: (_, _) => const AccessibilityScreen()),
        ],
      ),
    ],
  );

  // O link do email de recuperação abre a app com uma sessão temporária.
  final recovery = auth.passwordRecovery.listen((_) => router.go('/reset-password'));
  ref.onDispose(recovery.cancel);

  // Links de convite, de cartões e de recuperação de palavra-passe (com a app fechada ou aberta).
  Future<void> openLink(Uri? uri) async {
    if (uri == null) return;
    try {
      if (await auth.handleAuthLink(uri)) return;
    } catch (e) {
      final context = _rootKey.currentContext;
      if (context != null && context.mounted) showMessage(context, friendlyError(e));
      return;
    }
    final card = CardLinks.tokenFrom(uri);
    if (card != null) {
      router.go('/card/$card');
      return;
    }
    final code = InviteLinks.codeFrom(uri);
    if (code != null) router.go('/join/${code.toUpperCase()}');
  }

  // Tocar numa notificação abre a conversa, a pessoa, a mensagem ou a prenda em grupo.
  void openPayload(String? payload) {
    if (payload == null || auth.current == null) return;
    final route = ReminderCopy.route(payload);
    if (route != null) router.push(route);
  }

  final taps = NotificationService.instance.taps.listen(openPayload);
  ref.onDispose(taps.cancel);
  Future.microtask(() => openPayload(NotificationService.instance.takeLaunchPayload()));

  // Primeira entrada numa conta sem aniversários: abre logo "Adicionar dos
  // contactos" (uma vez por conta neste telemóvel; ver onboardingFor).
  void maybeOnboard() {
    final user = auth.current;
    if (user == null) return;
    final prefs = ref.read(sharedPrefsProvider);
    final key = onboardingKey(user.id);
    final decision = onboardingFor(
      seen: prefs.getBool(key) ?? false,
      data: ref.read(appDataProvider).value,
      location: router.routerDelegate.currentConfiguration.uri.path,
    );
    if (decision == Onboarding.wait) return;
    prefs.setBool(key, true);
    if (decision == Onboarding.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => router.push('/people/import?welcome=1'));
    }
  }

  ref.listen(appDataProvider, (_, _) => maybeOnboard());
  router.routerDelegate.addListener(maybeOnboard);
  ref.onDispose(() => router.routerDelegate.removeListener(maybeOnboard));

  final links = AppLinks();
  links.getInitialLink().then(openLink).catchError((_) {});
  final linkSub = links.uriLinkStream.listen(openLink, onError: (_) {});
  ref.onDispose(linkSub.cancel);

  // Instalada a partir de um cartão: abre-o logo na primeira vez (ver DeferredLink).
  if (ref.read(cardsRepositoryProvider) != null) {
    DeferredLink.takeCardToken(ref.read(sharedPrefsProvider)).then((token) {
      if (token != null) router.go('/card/$token');
    });
  }
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
