import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../services/institutional_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

/// Fila de denúncias: PENDENTE → EM_ANALISE → PROCEDENTE/IMPROCEDENTE (spec §38).
class ModerationQueueScreen extends StatefulWidget {
  const ModerationQueueScreen({super.key});

  @override
  State<ModerationQueueScreen> createState() => _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends State<ModerationQueueScreen> {
  final _service = InstitutionalService();
  List<ModerationQueueItem> _items = const [];
  bool _loading = true;
  String? _error;
  int? _processing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await _service.fetchModerationQueue();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(ModerationQueueItem item) async {
    setState(() => _processing = item.id);
    try {
      if (item.status == 'pending') await _service.startModerationReview(item.id);
      if (!mounted) return;
      final decision = await showUrbSheet<({bool uphold, String notes, bool invalidate})>(
        context: context,
        eyebrow: 'Análise de denúncia',
        title: item.targetType == 'comment' ? 'Comentário denunciado' : 'Relato denunciado',
        intro: 'Conteúdo removido sai da exibição pública sem apagar o histórico interno. '
            'A moderação não pode ser usada para alterar indicadores políticos ou institucionais.',
        builder: (_) => _DecisionForm(item: item),
      );
      if (decision != null) {
        await _service.reviewModerationReport(
          reportId: item.id,
          uphold: decision.uphold,
          notes: decision.notes,
          invalidateWholeOccurrence: decision.invalidate,
        );
        if (mounted) showUrbToast(context, 'Decisão registrada no histórico de moderação.');
      }
      await _load();
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _processing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Moderação'),
      body: _loading
          ? const UrbLoadingView()
          : _error != null
              ? UrbErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(children: const [
                          UrbEmptyState(icon: UrbIcons.check, title: 'Fila vazia', message: 'Nenhuma denúncia aguardando análise.'),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: UrbColors.line),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      UrbVerificationPill(
                                        label: item.status == 'pending' ? 'Pendente' : 'Em análise',
                                        verified: item.status != 'pending',
                                      ),
                                      const SizedBox(width: 8),
                                      Text(item.targetType == 'comment' ? 'Comentário' : 'Relato', style: UrbText.caption),
                                      const Spacer(),
                                      Text(formatRelativeTime(item.createdAt), style: UrbText.caption),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    item.targetPreview ?? 'Conteúdo #${item.targetId}',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: UrbText.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Motivo: ${item.reason}', style: UrbText.bodySmall),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      if (item.occurrenceId != null)
                                        UrbTextButton('Ver ocorrência', onPressed: () => openOccurrence(context, occurrenceId: item.occurrenceId!)),
                                      const Spacer(),
                                      UrbButton(
                                        label: 'Analisar',
                                        height: 40,
                                        loading: _processing == item.id,
                                        onPressed: _processing == null ? () => _review(item) : null,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

class _DecisionForm extends StatefulWidget {
  const _DecisionForm({required this.item});

  final ModerationQueueItem item;

  @override
  State<_DecisionForm> createState() => _DecisionFormState();
}

class _DecisionFormState extends State<_DecisionForm> {
  final _notes = TextEditingController();
  bool _invalidate = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _decide(bool uphold) {
    if (_notes.text.trim().length < 3) {
      showUrbToast(context, 'Registre a justificativa da decisão.');
      return;
    }
    Navigator.of(context).pop((uphold: uphold, notes: _notes.text.trim(), invalidate: uphold && _invalidate));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: UrbColors.line)),
          child: Text(widget.item.targetPreview ?? '', style: UrbText.bodySmall.copyWith(color: UrbColors.navy)),
        ),
        const SizedBox(height: 14),
        UrbTextField(label: 'Justificativa', controller: _notes, maxLines: 3, minLines: 3),
        if (widget.item.targetType == 'post') ...[
          const SizedBox(height: 10),
          UrbSettingsRow(
            label: 'Invalidar toda a ocorrência',
            subtitle: 'Use apenas se a ocorrência inteira for inválida. Ela sai dos indicadores e não conta como resolvida.',
            trailing: UrbSwitch(value: _invalidate, onChanged: (value) => setState(() => _invalidate = value)),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: UrbButton(label: 'Improcedente', tone: UrbButtonTone.outline, expand: true, onPressed: () => _decide(false))),
            const SizedBox(width: 8),
            Expanded(child: UrbButton(label: 'Procedente', tone: UrbButtonTone.danger, expand: true, onPressed: () => _decide(true))),
          ],
        ),
      ],
    );
  }
}
