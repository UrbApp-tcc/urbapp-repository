import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/app_session.dart';
import '../../app/institutional_intent.dart';
import '../../app/routes.dart';
import '../../services/institutional_service.dart';
import '../../services/notifications_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/urb/urb_bottom_nav.dart';
import '../home/home_screen.dart';
import '../institutional/access_request_screen.dart';
import '../profile/profile_screen.dart';
import '../search/search_screen.dart';
import '../transparency/transparency_screen.dart';

/// Estrutura principal: Início · Buscar · Relatar · Transparência · Perfil.
/// Alertas ficam no sino dos cabeçalhos (spec §44.5).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  static AppShellState? of(BuildContext context) => context.findAncestorStateOfType<AppShellState>();

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  final _notifications = NotificationsService();
  final _searchKey = GlobalKey<SearchScreenState>();
  StreamSubscription<Uri>? _deepLinks;
  UrbTab _tab = UrbTab.home;
  final Set<UrbTab> _visited = {UrbTab.home};

  @override
  void initState() {
    super.initState();
    AppSession.instance.init().then((_) {
      if (mounted) setState(() {});
      _resumeInstitutionalIntent();
    });
    _notifications.refreshUnreadCount();
    _notifications.listen();
    _setupDeepLinks();
  }

  @override
  void dispose() {
    _deepLinks?.cancel();
    _notifications.dispose();
    super.dispose();
  }

  /// Quem escolheu "Acesso institucional" antes de entrar segue direto para a
  /// solicitação, sem procurar a opção nas configurações.
  Future<void> _resumeInstitutionalIntent() async {
    final kind = await InstitutionalIntent.consume();
    if (kind == null || !mounted) return;
    try {
      final access = await InstitutionalService().fetchMyAccess();
      if (access.hasInstitutionalRole) return;
    } catch (_) {
      // Sem confirmação do acesso atual, a solicitação ainda pode ser aberta.
    }
    if (mounted) Navigator.of(context).push(urbRoute(AccessRequestScreen(initialKind: kind)));
  }

  void selectTab(UrbTab tab) {
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
  }

  /// Abre a aba Buscar já no modo mapa (atalho da Home).
  void openSearchMap() {
    selectTab(UrbTab.search);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchKey.currentState?.showMap());
  }

  void _setupDeepLinks() {
    try {
      final appLinks = AppLinks();
      appLinks.getInitialLink().then((uri) {
        if (uri != null) _handleDeepLink(uri);
      });
      _deepLinks = appLinks.uriLinkStream.listen(_handleDeepLink, onError: (_) {});
    } catch (_) {
      // Plataformas sem suporte a deep link seguem normalmente.
    }
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.scheme != 'urbapp') return;
    final id = int.tryParse(uri.pathSegments.firstOrNull ?? '');
    if (id == null || !mounted) return;
    var occurrenceId = id;
    if (uri.host == 'posts') {
      final row = await Supabase.instance.client.from('post_feed_rows').select('occurrence_id').eq('id', id).maybeSingle();
      final resolved = (row?['occurrence_id'] as num?)?.toInt();
      if (resolved == null) return;
      occurrenceId = resolved;
    } else if (uri.host != 'occurrences') {
      return;
    }
    if (mounted) await openOccurrence(context, occurrenceId: occurrenceId);
  }

  Widget _page(UrbTab tab) {
    if (!_visited.contains(tab)) return const SizedBox.shrink();
    return switch (tab) {
      UrbTab.home => const HomeScreen(),
      UrbTab.search => SearchScreen(key: _searchKey),
      UrbTab.transparency => const TransparencyScreen(),
      UrbTab.profile => const ProfileScreen(isTab: true),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      body: IndexedStack(
        index: UrbTab.values.indexOf(_tab),
        children: [for (final tab in UrbTab.values) _page(tab)],
      ),
      bottomNavigationBar: UrbBottomNav(
        current: _tab,
        onSelect: selectTab,
        onCreate: () => openReportFlow(context),
      ),
    );
  }
}
