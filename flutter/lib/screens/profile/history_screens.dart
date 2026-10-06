import 'package:flutter/material.dart';

import '../../domain/labels.dart';
import '../../app/routes.dart';
import '../../domain/models.dart';
import '../../services/occurrence_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/occurrence_widgets.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

class _HistoryScaffold extends StatelessWidget {
  const _HistoryScaffold({required this.title, required this.intro, required this.children, this.loading = false, this.error, this.onRetry});

  final String title;
  final String intro;
  final List<Widget> children;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: UrbSubscreenHeader(title: title),
      body: loading
          ? const UrbLoadingView()
          : error != null
              ? UrbErrorState(message: error!, onRetry: onRetry)
              : ListView(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: UrbColors.line))),
                      child: Text(intro, style: UrbText.meta),
                    ),
                    ...children,
                  ],
                ),
    );
  }
}

class SupportedHistoryScreen extends StatefulWidget {
  const SupportedHistoryScreen({super.key});

  @override
  State<SupportedHistoryScreen> createState() => _SupportedHistoryScreenState();
}

class _SupportedHistoryScreenState extends State<SupportedHistoryScreen> {
  List<Occurrence>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await OccurrenceService().fetchSupported();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? const <Occurrence>[];
    return _HistoryScaffold(
      title: 'Ocorrências apoiadas',
      intro: '${plural(items.length, 'ocorrência apoiada', 'ocorrências apoiadas')} por você',
      loading: _items == null && _error == null,
      error: _error,
      onRetry: _load,
      children: [
        if (items.isEmpty)
          const UrbEmptyState(icon: UrbIcons.heart, title: 'Nenhum apoio ainda', message: 'Apoie ocorrências de outros cidadãos para dar visibilidade a elas.')
        else
          for (final occurrence in items)
            CompactOccurrenceRow(
              occurrence: occurrence,
              role: 'Você apoiou esta ocorrência',
              onTap: () => openOccurrence(context, occurrenceId: occurrence.id, initial: occurrence),
            ),
      ],
    );
  }
}

class ValidationHistoryScreen extends StatefulWidget {
  const ValidationHistoryScreen({super.key});

  @override
  State<ValidationHistoryScreen> createState() => _ValidationHistoryScreenState();
}

class _ValidationHistoryScreenState extends State<ValidationHistoryScreen> {
  List<ValidationHistoryItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await ProfileService().fetchMyValidations(OccurrenceService().fetchByIds);
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? const <ValidationHistoryItem>[];
    return _HistoryScaffold(
      title: 'Minhas validações',
      intro: plural(items.length, 'validação comunitária realizada', 'validações comunitárias realizadas'),
      loading: _items == null && _error == null,
      error: _error,
      onRetry: _load,
      children: [
        if (items.isEmpty)
          const UrbEmptyState(
            icon: UrbIcons.check,
            title: 'Nenhuma validação ainda',
            message: 'Quando alguém informar uma possível resolução perto de você, ajude a confirmar o que aconteceu.',
          )
        else
          for (final item in items)
            CompactOccurrenceRow(
              occurrence: item.occurrence,
              role: 'Você confirmou: "${item.confirmed ? 'Foi resolvido' : 'O problema continua'}" · '
                  '${formatRelativeTime(item.votedAt).toLowerCase()}',
              pill: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: item.confirmed ? UrbColors.successSoft : UrbColors.dangerSoft,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  item.confirmed ? 'Resolvido' : 'Continua',
                  style: UrbText.caption.copyWith(
                    color: item.confirmed ? UrbColors.success : UrbColors.danger,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
              ),
              onTap: () => openOccurrence(context, occurrenceId: item.occurrence.id, initial: item.occurrence),
            ),
      ],
    );
  }
}
