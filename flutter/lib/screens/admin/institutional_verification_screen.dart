import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routes.dart';
import '../../logic/institutional_review_rules.dart';
import '../../services/institutional_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

/// Verificação de perfis institucionais (vereador, órgão, gestão) — spec §19.
/// Pendentes ficam em ordem de chegada; o histórico mostra quem decidiu e por quê.
class InstitutionalVerificationScreen extends StatefulWidget {
  const InstitutionalVerificationScreen({super.key});

  @override
  State<InstitutionalVerificationScreen> createState() => _InstitutionalVerificationScreenState();
}

class _InstitutionalVerificationScreenState extends State<InstitutionalVerificationScreen> {
  final _service = InstitutionalService();
  final Map<int, List<InstitutionalVerificationRequest>> _items = {};
  final Map<int, String> _errors = {};
  int _tab = 0;
  bool _loading = true;

  bool get _reviewed => _tab == 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tab = _tab;
    setState(() {
      _loading = !_items.containsKey(tab);
      _errors.remove(tab);
    });
    try {
      final items = await _service.fetchInstitutionalVerificationQueue(reviewed: tab == 1);
      if (mounted) setState(() => _items[tab] = items);
    } catch (error) {
      if (mounted) setState(() => _errors[tab] = friendlyError(error));
    } finally {
      if (mounted && tab == _tab) setState(() => _loading = false);
    }
  }

  void _selectTab(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _load();
  }

  Future<void> _open(InstitutionalVerificationRequest request) async {
    final decided = await Navigator.of(context).push<bool>(urbRoute(InstitutionalRequestDetailScreen(
      request: request,
      onReview: (approve, notes) => _service.reviewInstitutionalRequest(request: request, approve: approve, notes: notes),
    )));
    if (decided == true && mounted) {
      _items.remove(1);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items[_tab] ?? const <InstitutionalVerificationRequest>[];
    final error = _errors[_tab];
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Verificação institucional'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UrbUnderlineTabs(
            labels: const ['Pendentes', 'Histórico'],
            selected: _tab,
            onChanged: _selectTab,
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          Expanded(
            child: _loading
                ? const UrbLoadingView()
                : error != null
                    ? UrbErrorState(message: error, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                          children: [
                            if (items.isEmpty)
                              _reviewed
                                  ? const UrbEmptyState(
                                      icon: UrbIcons.clock,
                                      title: 'Nenhuma decisão registrada',
                                      message: 'Pedidos aprovados e rejeitados aparecerão aqui.',
                                    )
                                  : const UrbEmptyState(
                                      icon: UrbIcons.check,
                                      title: 'Nenhuma solicitação pendente',
                                      message: 'Novas solicitações aparecerão aqui.',
                                    )
                            else
                              for (var index = 0; index < items.length; index++)
                                UrbDotRow(
                                  title: items[index].name,
                                  subtitle: _subtitle(items[index]),
                                  trailingText: _reviewed ? institutionalRequestStatusLabel(items[index].status) : null,
                                  dotColor: _dotColor(items[index]),
                                  last: index == items.length - 1,
                                  onTap: () => _open(items[index]),
                                ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _subtitle(InstitutionalVerificationRequest request) {
    final date = request.isPending ? request.createdAt : (request.reviewedAt ?? request.createdAt);
    final who = request.requesterUsername == null ? '' : ' · @${request.requesterUsername}';
    return '${institutionalRequestKindLabel(request.kind)} · ${request.cityName}$who · ${formatDate(date)}';
  }

  Color _dotColor(InstitutionalVerificationRequest request) {
    if (!request.isPending) return request.isApproved ? UrbColors.success : UrbColors.danger;
    return request.isCouncilor ? UrbColors.violet : UrbColors.blue;
  }
}

/// Detalhe de um pedido: o que foi pedido, quem pediu, a comprovação e, se
/// pendente, a decisão. Rejeitar exige motivo, enviado ao solicitante.
class InstitutionalRequestDetailScreen extends StatefulWidget {
  const InstitutionalRequestDetailScreen({super.key, required this.request, required this.onReview});

  final InstitutionalVerificationRequest request;
  final Future<void> Function(bool approve, String notes) onReview;

  @override
  State<InstitutionalRequestDetailScreen> createState() => _InstitutionalRequestDetailScreenState();
}

class _InstitutionalRequestDetailScreenState extends State<InstitutionalRequestDetailScreen> {
  bool _saving = false;

  InstitutionalVerificationRequest get _request => widget.request;

  Future<void> _submit(bool approve, String notes) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onReview(approve, notes);
      if (!mounted) return;
      showUrbToast(context, approve ? 'Pedido aprovado. O solicitante foi avisado.' : 'Pedido rejeitado. O solicitante recebeu o motivo.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _approve() async {
    final confirmed = await UrbConfirmSheet.show(
      context,
      title: 'Aprovar pedido?',
      message: '${_request.requesterName ?? 'O solicitante'} passa a atuar como '
          '${institutionalRequestKindLabel(_request.kind).toLowerCase()} "${_request.name}" em ${_request.cityName}.',
      confirmLabel: 'Aprovar',
    );
    if (confirmed) await _submit(true, '');
  }

  Future<void> _reject() async {
    final reason = await showUrbSheet<String>(
      context: context,
      eyebrow: 'Rejeitar pedido',
      title: _request.name,
      intro: 'O motivo é enviado ao solicitante, para que ele possa corrigir e pedir de novo.',
      builder: (_) => const _RejectionForm(),
    );
    if (reason != null) await _submit(false, reason);
  }

  Future<void> _openLink(String link) async {
    final uri = Uri.tryParse(link.startsWith('http') ? link : 'https://$link');
    final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) showUrbToast(context, 'Não foi possível abrir o link.');
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final warnings = institutionalReviewWarnings(
      institutionalEmail: request.institutionalEmail,
      previousRejections: request.previousRejections,
    );
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Pedido institucional'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          UrbEyebrow(institutionalRequestKindLabel(request.kind)),
          const SizedBox(height: 6),
          Text(request.name, style: UrbText.h2),
          const SizedBox(height: 4),
          Text('${request.cityName} · enviado em ${formatDate(request.createdAt)}', style: UrbText.caption),
          if (!request.isPending) ...[
            const SizedBox(height: 14),
            _DecisionBanner(request: request),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final warning in warnings) _Warning(text: warning),
          ],
          _Section(
            title: 'Pedido',
            rows: [
              ('Tipo', institutionalRequestKindLabel(request.kind)),
              if (request.agencyType != null && request.kind == 'agency') ('Tipo de órgão', request.agencyType!),
              if (request.requesterRole != null) ('Cargo informado', request.requesterRole!),
              if (request.isCouncilor && request.party != null) ('Partido', request.party!),
              if (request.isCouncilor && request.mandateStartsOn != null)
                ('Mandato', formatPeriod(request.mandateStartsOn!, request.mandateEndsOn)),
              ('Situação atual', existingProfileLabel(request.kind, request.existingProfileStatus)),
            ],
          ),
          _Section(
            title: 'Quem pediu',
            rows: [
              ('Nome', request.requesterName ?? 'Conta removida'),
              if (request.requesterUsername != null) ('Usuário', '@${request.requesterUsername}'),
              if (request.requesterAccountEmail != null) ('E-mail da conta', request.requesterAccountEmail!),
              if (request.requesterSince != null) ('No UrbApp desde', formatDate(request.requesterSince!)),
              ('Outros pedidos', request.previousRequests == 0
                  ? 'Nenhum'
                  : '${request.previousRequests} (${request.previousRejections} rejeitado${request.previousRejections == 1 ? '' : 's'})'),
            ],
          ),
          _Section(
            title: 'Comprovação',
            rows: [('E-mail institucional', request.institutionalEmail)],
            children: [
              const SizedBox(height: 10),
              Text(request.proofSummary, style: UrbText.bodySmall.copyWith(color: UrbColors.navy)),
              for (final link in request.proofLinkList) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _openLink(link),
                  child: Row(
                    children: [
                      const UrbIcon(UrbIcons.share, size: 14, color: UrbColors.blue),
                      const SizedBox(width: 6),
                      Expanded(child: Text(link, style: UrbText.bodySmall.copyWith(color: UrbColors.blue))),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (request.isPending) ...[
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: UrbButton(
                    label: 'Rejeitar',
                    tone: UrbButtonTone.danger,
                    expand: true,
                    onPressed: _saving ? null : _reject,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: UrbButton(label: 'Aprovar', expand: true, loading: _saving, onPressed: _saving ? null : _approve),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'A decisão fica registrada com seu nome e não pode ser desfeita por aqui.',
              style: UrbText.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows, this.children = const []});

  final String title;
  final List<(String, String)> rows;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: UrbColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: UrbText.title),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 130, child: Text(label, style: UrbText.caption)),
                  Expanded(child: Text(value, style: UrbText.bodySmall.copyWith(color: UrbColors.navy))),
                ],
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: UrbColors.warningSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const UrbIcon(UrbIcons.flag, size: 14, color: UrbColors.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: UrbText.bodySmall.copyWith(color: UrbColors.navy))),
        ],
      ),
    );
  }
}

class _DecisionBanner extends StatelessWidget {
  const _DecisionBanner({required this.request});

  final InstitutionalVerificationRequest request;

  @override
  Widget build(BuildContext context) {
    final approved = request.isApproved;
    final when = request.reviewedAt == null ? '' : ' em ${formatDate(request.reviewedAt!)}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: approved ? UrbColors.successSoft : UrbColors.dangerSoft,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${institutionalRequestStatusLabel(request.status)} por ${request.reviewerName ?? 'administração'}$when',
            style: UrbText.label.copyWith(color: approved ? UrbColors.success : UrbColors.danger),
          ),
          if (request.reviewNotes != null) ...[
            const SizedBox(height: 6),
            Text(request.reviewNotes!, style: UrbText.bodySmall.copyWith(color: UrbColors.navy)),
          ],
        ],
      ),
    );
  }
}

class _RejectionForm extends StatefulWidget {
  const _RejectionForm();

  @override
  State<_RejectionForm> createState() => _RejectionFormState();
}

class _RejectionFormState extends State<_RejectionForm> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = validateRejectionReason(_reason.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UrbTextField(
          label: 'Motivo da rejeição',
          hint: 'Ex.: o e-mail não é institucional e falta documento que comprove o vínculo.',
          controller: _reason,
          maxLines: 4,
          minLines: 3,
          maxLength: 500,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        UrbButton(
          label: 'Rejeitar pedido',
          tone: UrbButtonTone.danger,
          expand: true,
          onPressed: error == null ? () => Navigator.of(context).pop(_reason.text.trim()) : null,
        ),
      ],
    );
  }
}
