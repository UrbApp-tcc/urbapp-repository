import 'package:flutter/material.dart';

import '../services/institutional_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';

class ModerationQueueScreen extends StatefulWidget {
  const ModerationQueueScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ModerationQueueScreen()),
    );
  }

  @override
  State<ModerationQueueScreen> createState() => _ModerationQueueScreenState();
}

class _ModerationQueueScreenState extends State<ModerationQueueScreen> {
  final _service = InstitutionalService();
  List<ModerationQueueItem> _items = const [];
  bool _isLoading = true;
  int? _processingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final items = await _service.fetchModerationQueue();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _review(ModerationQueueItem item) async {
    setState(() => _processingId = item.id);
    try {
      if (item.status == 'pending') {
        await _service.startModerationReview(item.id);
      }
      if (!mounted) return;
      final decision = await showModalBottomSheet<_ModerationDecision>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (_) => _ModerationDecisionSheet(item: item),
      );
      if (decision == null) {
        await _load();
        return;
      }

      await _service.reviewModerationReport(
        reportId: item.id,
        uphold: decision.uphold,
        notes: decision.notes,
        invalidateWholeOccurrence: decision.invalidateWholeOccurrence,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Decisão registrada no histórico de moderação.'),
          backgroundColor: AppColors.resolved,
        ),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(friendlyError(error)),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(title: const Text('Fila de moderação')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 80,
                ),
                children: const [
                  Icon(
                    Icons.verified_outlined,
                    size: 52,
                    color: AppColors.resolved,
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Nenhuma denúncia aguardando análise.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _StatusBadge(status: item.status),
                              const Spacer(),
                              Text(
                                '#${item.id}',
                                style: const TextStyle(
                                  color: AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            item.postTitle ?? 'Reporte #${item.targetId}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.reason,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _processingId == item.id
                                  ? null
                                  : () => _review(item),
                              icon: _processingId == item.id
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.gavel_rounded),
                              label: const Text('Analisar denúncia'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status == 'in_analysis'
            ? const Color(0xFFFFF0D9)
            : const Color(0xFFFFE8E8),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status == 'in_analysis' ? 'Em análise' : 'Pendente',
        style: TextStyle(
          color: status == 'in_analysis'
              ? const Color(0xFF8C5700)
              : const Color(0xFF9A2A2A),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ModerationDecision {
  const _ModerationDecision({
    required this.uphold,
    required this.notes,
    required this.invalidateWholeOccurrence,
  });

  final bool uphold;
  final String notes;
  final bool invalidateWholeOccurrence;
}

class _ModerationDecisionSheet extends StatefulWidget {
  const _ModerationDecisionSheet({required this.item});

  final ModerationQueueItem item;

  @override
  State<_ModerationDecisionSheet> createState() =>
      _ModerationDecisionSheetState();
}

class _ModerationDecisionSheetState extends State<_ModerationDecisionSheet> {
  final _notesController = TextEditingController();
  bool _invalidateWholeOccurrence = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _submit(bool uphold) {
    final notes = _notesController.text.trim();
    if (notes.length < 3) return;
    Navigator.of(context).pop(
      _ModerationDecision(
        uphold: uphold,
        notes: notes,
        invalidateWholeOccurrence: uphold && _invalidateWholeOccurrence,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _notesController.text.trim().length >= 3;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Decisão de moderação',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              widget.item.reason,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _notesController,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Justificativa auditável',
                alignLabelWithHint: true,
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _invalidateWholeOccurrence,
              onChanged: (value) =>
                  setState(() => _invalidateWholeOccurrence = value ?? false),
              title: const Text('Invalidar toda a ocorrência'),
              subtitle: const Text(
                'Use apenas se o problema inteiro for fraudulento ou inválido.',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: canSubmit ? () => _submit(false) : null,
                    child: const Text('Improcedente'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: canSubmit ? () => _submit(true) : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    child: const Text('Procedente'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
