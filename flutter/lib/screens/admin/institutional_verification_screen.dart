import 'package:flutter/material.dart';

import '../../services/institutional_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

/// Verificação de perfis institucionais (vereador, órgão, gestão) — spec §19.
class InstitutionalVerificationScreen extends StatefulWidget {
  const InstitutionalVerificationScreen({super.key});

  @override
  State<InstitutionalVerificationScreen> createState() => _InstitutionalVerificationScreenState();
}

class _InstitutionalVerificationScreenState extends State<InstitutionalVerificationScreen> {
  final _service = InstitutionalService();
  List<InstitutionalVerificationRequest> _items = const [];
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
      final items = await _service.fetchInstitutionalVerificationQueue();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(InstitutionalVerificationRequest request) async {
    final decision = await showUrbSheet<({bool approve, String notes})>(
      context: context,
      eyebrow: 'Verificação institucional',
      title: request.name,
      intro: 'Confira o vínculo informado antes de liberar funções institucionais.',
      builder: (sheetContext) {
        final notes = TextEditingController();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Comprovação apresentada', style: UrbText.label),
            const SizedBox(height: 6),
            Text(request.proofSummary, style: UrbText.bodySmall),
            const SizedBox(height: 6),
            Text(request.institutionalEmail, style: UrbText.caption),
            const SizedBox(height: 14),
            UrbTextField(label: 'Observações (opcional)', controller: notes, maxLines: 3, minLines: 2),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: UrbButton(
                    label: 'Rejeitar',
                    tone: UrbButtonTone.danger,
                    expand: true,
                    onPressed: () => Navigator.of(sheetContext).pop((approve: false, notes: notes.text)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: UrbButton(
                    label: 'Aprovar',
                    expand: true,
                    onPressed: () => Navigator.of(sheetContext).pop((approve: true, notes: notes.text)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (decision == null) return;
    try {
      await _service.reviewInstitutionalRequest(request: request, approve: decision.approve, notes: decision.notes);
      if (mounted) showUrbToast(context, decision.approve ? 'Perfil verificado.' : 'Solicitação rejeitada.');
      await _load();
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Verificação institucional'),
      body: _loading
          ? const UrbLoadingView()
          : _error != null
              ? UrbErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      if (_items.isEmpty)
                        const UrbEmptyState(icon: UrbIcons.check, title: 'Nenhuma solicitação pendente', message: 'Novas solicitações aparecerão aqui.')
                      else
                        for (var index = 0; index < _items.length; index++)
                          UrbDotRow(
                            title: _items[index].name,
                            subtitle: '${switch (_items[index].kind) {
                              'councilor' => 'Vereador',
                              'administration' => 'Gestão municipal',
                              _ => 'Órgão municipal',
                            }} · ${_items[index].cityName} · ${formatDate(_items[index].createdAt)}',
                            dotColor: _items[index].kind == 'councilor' ? UrbColors.violet : UrbColors.blue,
                            last: index == _items.length - 1,
                            onTap: () => _review(_items[index]),
                          ),
                    ],
                  ),
                ),
    );
  }
}
