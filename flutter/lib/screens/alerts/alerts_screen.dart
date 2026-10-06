import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/routes.dart';
import '../../domain/models.dart';
import '../../services/notifications_service.dart';
import '../../services/occurrence_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

/// Alertas (sino com badge nos cabeçalhos principais, spec §44.5).
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final _notifications = NotificationsService();
  final _occurrences = OccurrenceService();

  List<AppNotification> _items = const [];
  Map<int, Occurrence> _occurrenceById = const {};
  Map<int, String> _agencyNames = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await _notifications.fetch();
      final occurrenceIds = items.map((item) => item.occurrenceId).whereType<int>();
      final agencyIds = items.where((item) => item.isOfficial).map((item) => item.agencyId).whereType<int>().toSet();
      final occurrences = await _occurrences.fetchByIds(occurrenceIds);
      final agencyNames = <int, String>{};
      if (agencyIds.isNotEmpty) {
        final rows = await Supabase.instance.client.from('public_agencies').select('id, name').inFilter('id', agencyIds.toList());
        for (final row in rows as List) {
          agencyNames[(row['id'] as num).toInt()] = row['name'] as String;
        }
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _occurrenceById = {for (final occurrence in occurrences) occurrence.id: occurrence};
        _agencyNames = agencyNames;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAll() async {
    try {
      await _notifications.markAllRead();
      if (mounted) setState(() => _items = [for (final item in _items) item.markRead()]);
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    }
  }

  Future<void> _open(AppNotification item) async {
    if (!item.read) {
      _notifications.markRead(item.id);
      setState(() => _items = [for (final value in _items) value.id == item.id ? value.markRead() : value]);
    }
    final occurrenceId = item.occurrenceId;
    if (occurrenceId == null) return;
    final occurrence = _occurrenceById[occurrenceId];
    if (item.isValidation && occurrence != null) {
      await openValidation(context, occurrence);
      return;
    }
    if (!mounted) return;
    await openOccurrence(
      context,
      occurrenceId: occurrenceId,
      initial: occurrence,
      anchor: item.isComment
          ? DetailAnchor.comments
          : (item.eventType == 'report_added' ? DetailAnchor.reports : DetailAnchor.top),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((item) => !item.read).length;
    final groups = <String, List<AppNotification>>{};
    for (final item in _items) {
      groups.putIfAbsent(alertGroupOf(item.createdAt), () => []).add(item);
    }
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 18),
            child: Row(
              children: [
                UrbSquareButton(icon: UrbIcons.close, tooltip: 'Fechar', size: 36, iconSize: 18, onPressed: () => Navigator.of(context).pop()),
                const SizedBox(width: 10),
                Expanded(child: Text('Alertas', style: UrbText.screenTitle)),
                if (unread > 0) UrbTextButton('Marcar como lidos', onPressed: _markAll),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const UrbLoadingView()
                : _error != null
                    ? UrbErrorState(message: _error!, onRetry: _load)
                    : _items.isEmpty
                        ? const Center(
                            child: UrbEmptyState(
                              icon: UrbIcons.bell,
                              title: 'Nenhum alerta por enquanto',
                              message: 'As novidades das ocorrências que você acompanha aparecerão aqui.',
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 40),
                              children: [
                                for (final group in groups.entries) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                                    child: UrbEyebrow(group.key, muted: true),
                                  ),
                                  for (var index = 0; index < group.value.length; index++)
                                    _AlertRow(
                                      item: group.value[index],
                                      first: index == 0,
                                      occurrenceTitle: _occurrenceById[group.value[index].occurrenceId]?.title ??
                                          group.value[index].occurrenceTitle,
                                      institution: _agencyNames[group.value[index].agencyId],
                                      onTap: () => _open(group.value[index]),
                                    ),
                                  const SizedBox(height: 6),
                                ],
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.item,
    required this.onTap,
    this.first = false,
    this.occurrenceTitle,
    this.institution,
  });

  final AppNotification item;
  final VoidCallback onTap;
  final bool first;
  final String? occurrenceTitle;
  final String? institution;

  @override
  Widget build(BuildContext context) {
    final muted = item.isResolved;
    final headingColor = !item.read ? UrbColors.navy : (muted ? UrbColors.muted : const Color(0xFF627082));
    final institutionName = item.isOfficial
        ? (item.actorKind == 'administration' ? 'Prefeitura' : institution)
        : null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 20, 14),
          decoration: BoxDecoration(
            border: Border(
              top: first ? const BorderSide(color: UrbColors.line) : BorderSide.none,
              bottom: const BorderSide(color: UrbColors.line),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, left: 1),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: item.read ? Colors.transparent : UrbColors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: UrbText.titleSmall.copyWith(
                              color: headingColor,
                              fontWeight: item.read ? FontWeight.w600 : FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(formatRelativeTime(item.createdAt), style: UrbText.caption.copyWith(fontWeight: FontWeight.w500)),
                      ],
                    ),
                    if (institutionName != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(color: UrbColors.blue, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: const UrbIcon(UrbIcons.check, size: 8, color: Colors.white, strokeWidth: 3),
                          ),
                          const SizedBox(width: 4),
                          Text(institutionName, style: UrbText.caption.copyWith(color: const Color(0xFF4A5E6E), fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                    // Apoios usam o título da ocorrência como corpo; o link abaixo já o mostra.
                    if (item.body.isNotEmpty && item.body.trim() != occurrenceTitle?.trim()) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: UrbText.bodySmall.copyWith(color: muted ? UrbColors.muted : const Color(0xFF54677C), fontSize: 12.5),
                      ),
                    ],
                    if (occurrenceTitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '$occurrenceTitle ›',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UrbText.caption.copyWith(color: const Color(0xFF4E6070), fontWeight: FontWeight.w700),
                      ),
                    ],
                    if (item.isValidation) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: UrbColors.blueSoft,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: UrbColors.blue.withValues(alpha: 0.18)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Confirmar resolução', style: UrbText.caption.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w800)),
                            const SizedBox(width: 4),
                            const UrbIcon(UrbIcons.arrow, size: 12, color: UrbColors.blue),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
