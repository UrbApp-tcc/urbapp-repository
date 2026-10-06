import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/app_session.dart';
import '../../app/institutional_intent.dart';
import '../../domain/models.dart';
import '../../services/agency_service.dart';
import '../../services/institutional_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/city_picker.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

class _RequestSummary {
  const _RequestSummary({required this.kind, required this.name, required this.cityName, required this.status, required this.createdAt});

  final String kind;
  final String name;
  final String cityName;
  final String status;
  final DateTime createdAt;
}

/// Solicitação de perfil institucional (vereador, órgão ou gestão municipal).
/// A verificação é feita pela administração do UrbApp (spec §3.5, §19).
class AccessRequestScreen extends StatefulWidget {
  const AccessRequestScreen({super.key, this.initialKind});

  /// Abre o formulário desse papel assim que a tela aparece.
  final InstitutionalKind? initialKind;

  @override
  State<AccessRequestScreen> createState() => _AccessRequestScreenState();
}

class _AccessRequestScreenState extends State<AccessRequestScreen> {
  List<_RequestSummary> _requests = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    final kind = widget.initialKind;
    if (kind != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(kind));
  }

  Future<void> _load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _error = null);
    try {
      final responses = await Future.wait<dynamic>([
        AgencyService().fetchOwnAgencyRequests(userId),
        Supabase.instance.client
            .from('councilor_profile_requests')
            .select('public_name, status, created_at, cities(name)')
            .eq('requester_user_id', userId)
            .order('created_at', ascending: false),
      ]);
      final agencyRequests = responses[0] as List<AgencyProfileRequest>;
      final councilorRequests = responses[1] as List;
      if (!mounted) return;
      setState(() {
        _requests = [
          for (final request in agencyRequests)
            _RequestSummary(
              kind: request.requestKind == 'administration' ? 'Gestão municipal' : 'Órgão municipal',
              name: request.agencyName,
              cityName: request.cityName,
              status: request.status,
              createdAt: request.createdAt,
            ),
          for (final request in councilorRequests)
            _RequestSummary(
              kind: 'Vereador',
              name: request['public_name'] as String,
              cityName: asJsonMap(request['cities'])?['name'] as String? ?? '',
              status: request['status'] as String? ?? 'pending',
              createdAt: DateTime.parse(request['created_at'] as String),
            ),
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(InstitutionalKind kind) async {
    final sent = await showUrbSheet<bool>(
      context: context,
      eyebrow: 'Solicitação institucional',
      title: switch (kind) {
        InstitutionalKind.councilor => 'Perfil de vereador',
        InstitutionalKind.administration => 'Acesso à gestão municipal',
        InstitutionalKind.agency => 'Perfil de órgão municipal',
      },
      intro: 'A equipe do UrbApp confere o vínculo antes de liberar as funções institucionais. '
          'Use um e-mail institucional e descreva como comprovar o vínculo.',
      builder: (_) => _RequestForm(kind: kind.code),
    );
    if (sent == true && mounted) {
      showUrbToast(context, 'Solicitação enviada para análise.');
      _load();
    }
  }

  String _statusLabel(String status) => switch (status) {
        'approved' => 'Aprovada',
        'rejected' => 'Não aprovada',
        _ => 'Em análise',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Perfil institucional'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          const UrbEyebrow('Atuação institucional'),
          const SizedBox(height: 8),
          Text('Atue pela sua instituição', style: UrbText.h1),
          const SizedBox(height: 8),
          Text(
            'O UrbApp é um único aplicativo: perfis verificados recebem funções adicionais nas ocorrências, '
            'sem perder a experiência cidadã.',
            style: UrbText.body,
          ),
          const SizedBox(height: 20),
          for (final option in InstitutionalKind.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13), side: const BorderSide(color: UrbColors.line)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => _open(option),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(option.choice, style: UrbText.title.copyWith(fontSize: 15)),
                              const SizedBox(height: 3),
                              Text(option.description, style: UrbText.caption.copyWith(fontSize: 12)),
                            ],
                          ),
                        ),
                        const UrbIcon(UrbIcons.chevron, size: 16, color: UrbColors.muted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 18),
          const UrbEyebrow('Suas solicitações', muted: true),
          const SizedBox(height: 6),
          if (_loading)
            const UrbLoadingView()
          else if (_error != null)
            UrbErrorState(message: _error!, onRetry: _load)
          else if (_requests.isEmpty)
            Text('Você ainda não enviou solicitações.', style: UrbText.caption)
          else
            for (var index = 0; index < _requests.length; index++)
              UrbDotRow(
                title: _requests[index].name,
                subtitle: '${_requests[index].kind} · ${_requests[index].cityName} · ${formatDate(_requests[index].createdAt)}',
                trailingText: _statusLabel(_requests[index].status),
                dotColor: switch (_requests[index].status) {
                  'approved' => UrbColors.success,
                  'rejected' => UrbColors.danger,
                  _ => UrbColors.gold,
                },
                last: index == _requests.length - 1,
              ),
        ],
      ),
    );
  }
}

class _RequestForm extends StatefulWidget {
  const _RequestForm({required this.kind});

  final String kind;

  @override
  State<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<_RequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _type = TextEditingController();
  final _party = TextEditingController();
  final _email = TextEditingController();
  final _role = TextEditingController();
  final _proof = TextEditingController();
  final _links = TextEditingController();
  CityOption? _city = AppSession.instance.city.value;
  DateTime? _mandateStart;
  DateTime? _mandateEnd;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _email.text = Supabase.instance.client.auth.currentUser?.email ?? '';
  }

  @override
  void dispose() {
    for (final controller in [_name, _type, _party, _email, _role, _proof, _links]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 8),
      lastDate: DateTime(now.year + 8),
      initialDate: start ? DateTime(now.year, 1, 1) : DateTime(now.year + 3, 12, 31),
    );
    if (picked != null) setState(() => start ? _mandateStart = picked : _mandateEnd = picked);
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate() || _city == null) return;
    if (widget.kind == 'councilor' && (_mandateStart == null || _mandateEnd == null)) {
      showUrbToast(context, 'Informe o início e o fim do mandato.');
      return;
    }
    setState(() => _sending = true);
    try {
      if (widget.kind == 'councilor') {
        await InstitutionalService().submitCouncilorRequest(
          cityId: _city!.id,
          publicName: _name.text,
          party: _party.text,
          mandateStartsOn: _mandateStart!,
          mandateEndsOn: _mandateEnd!,
          institutionalEmail: _email.text,
          proofSummary: _proof.text,
          proofLinks: _links.text,
        );
      } else {
        await AgencyService().createAgencyProfileRequest(
          cityId: _city!.id,
          name: widget.kind == 'administration' ? 'Prefeitura de ${_city!.name}' : _name.text,
          type: widget.kind == 'administration' ? 'Prefeitura Municipal' : _type.text,
          requestKind: widget.kind,
          contactEmail: _email.text,
          requesterRole: _role.text,
          proofSummary: _proof.text,
          proofLinks: _links.text,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        showUrbToast(context, friendlyError(error));
      }
    }
  }

  String? _required(String? value) => (value?.trim().length ?? 0) < 3 ? 'Campo obrigatório' : null;

  @override
  Widget build(BuildContext context) {
    final councilor = widget.kind == 'councilor';
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CitySelectorButton(
            city: _city,
            label: 'Cidade',
            onTap: () async {
              final picked = await showCityPicker(context, cities: AppSession.instance.cities, selected: _city);
              if (picked != null) setState(() => _city = picked);
            },
          ),
          const SizedBox(height: 14),
          if (widget.kind != 'administration') ...[
            UrbTextField(label: councilor ? 'Nome público' : 'Nome do órgão', controller: _name, validator: _required),
            const SizedBox(height: 14),
          ],
          if (widget.kind == 'agency') ...[
            UrbTextField(label: 'Tipo de órgão', hint: 'Ex.: Secretaria, autarquia', controller: _type, validator: _required),
            const SizedBox(height: 14),
          ],
          if (councilor) ...[
            UrbTextField(label: 'Partido (opcional)', controller: _party),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: UrbButton(
                    label: _mandateStart == null ? 'Início do mandato' : formatDate(_mandateStart!),
                    tone: UrbButtonTone.outline,
                    onPressed: () => _pickDate(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: UrbButton(
                    label: _mandateEnd == null ? 'Fim do mandato' : formatDate(_mandateEnd!),
                    tone: UrbButtonTone.outline,
                    onPressed: () => _pickDate(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ] else ...[
            UrbTextField(label: 'Seu cargo', controller: _role, validator: _required),
            const SizedBox(height: 14),
          ],
          UrbTextField(
            label: 'E-mail institucional',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            validator: (value) => RegExp(r'^[\w.+-]+@[\w.-]+\.\w{2,}$').hasMatch(value?.trim() ?? '') ? null : 'E-mail inválido',
          ),
          const SizedBox(height: 14),
          UrbTextField(label: 'Como comprovar o vínculo', controller: _proof, maxLines: 3, minLines: 3, validator: _required),
          const SizedBox(height: 14),
          UrbTextField(label: 'Links de comprovação (opcional)', controller: _links),
          const SizedBox(height: 18),
          UrbButton(label: 'Enviar solicitação', expand: true, height: 50, loading: _sending, onPressed: _send),
        ],
      ),
    );
  }
}
