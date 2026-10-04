import 'package:flutter/material.dart';

import '../services/city_service.dart';
import '../services/institutional_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';
import 'admin_governance_screen.dart';
import 'agency_profiles_screen.dart';
import 'city_indicators_screen.dart';
import 'institutional_verification_screen.dart';
import 'institutional_indicators_screen.dart';
import 'moderation_queue_screen.dart';

class InstitutionalCenterScreen extends StatefulWidget {
  const InstitutionalCenterScreen({super.key, required this.currentUserId});

  final String currentUserId;

  static Future<void> open(
    BuildContext context, {
    required String currentUserId,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InstitutionalCenterScreen(currentUserId: currentUserId),
      ),
    );
  }

  @override
  State<InstitutionalCenterScreen> createState() =>
      _InstitutionalCenterScreenState();
}

class _InstitutionalCenterScreenState extends State<InstitutionalCenterScreen> {
  final _service = InstitutionalService();
  final _cityService = CityService();

  InstitutionalAccess? _access;
  List<CityOption> _cities = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        _service.fetchMyAccess(),
        _cityService.fetchCities(),
      ]);
      if (!mounted) return;
      setState(() {
        _access = results[0] as InstitutionalAccess;
        _cities = results[1] as List<CityOption>;
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openCouncilorRequest() async {
    final draft = await showModalBottomSheet<_CouncilorRequestDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _CouncilorRequestSheet(cities: _cities),
    );
    if (draft == null) return;

    try {
      await _service.submitCouncilorRequest(
        cityId: draft.cityId,
        publicName: draft.publicName,
        party: draft.party,
        mandateStartsOn: draft.mandateStartsOn,
        mandateEndsOn: draft.mandateEndsOn,
        institutionalEmail: draft.institutionalEmail,
        proofSummary: draft.proofSummary,
        proofLinks: draft.proofLinks,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitação de perfil enviada para verificação.'),
          backgroundColor: AppColors.resolved,
        ),
      );
    } catch (error) {
      _showError(error);
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
    final access = _access;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(title: const Text('Central institucional')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  const _InstitutionalIntro(),
                  const SizedBox(height: 18),
                  if (access != null) _AccessSummary(access: access),
                  const SizedBox(height: 18),
                  _CenterActionTile(
                    icon: Icons.account_balance_outlined,
                    title: 'Órgãos e secretarias',
                    subtitle:
                        'Solicite verificação ou gerencie perfis dos quais você participa.',
                    onTap: () => AgencyProfilesScreen.open(
                      context,
                      currentUserId: widget.currentUserId,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CenterActionTile(
                    icon: Icons.how_to_vote_outlined,
                    title: access?.councilorProfileId == null
                        ? 'Solicitar perfil de vereador'
                        : 'Perfil de vereador verificado',
                    subtitle: access?.councilorProfileId == null
                        ? 'Envie dados do mandato e comprovação institucional.'
                        : 'As ações registradas aparecem publicamente na linha do tempo.',
                    onTap: access?.councilorProfileId == null
                        ? _openCouncilorRequest
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _CenterActionTile(
                    icon: Icons.insights_outlined,
                    title: 'Indicadores públicos',
                    subtitle:
                        'Consulte os dados históricos e objetivos da cidade.',
                    onTap: () => CityIndicatorsScreen.open(context),
                  ),
                  const SizedBox(height: 12),
                  _CenterActionTile(
                    icon: Icons.query_stats_rounded,
                    title: 'Indicadores institucionais',
                    subtitle:
                        'Compare gestão, órgãos e vereadores sem atribuir causalidade política.',
                    onTap: () => InstitutionalIndicatorsScreen.open(context),
                  ),
                  if (access?.isPlatformAdmin == true) ...[
                    const SizedBox(height: 12),
                    _CenterActionTile(
                      icon: Icons.tune_rounded,
                      title: 'Governança e regras',
                      subtitle:
                          'Categorias, órgãos, validação, competência e duplicidades.',
                      onTap: () => AdminGovernanceScreen.open(context),
                    ),
                    const SizedBox(height: 12),
                    _CenterActionTile(
                      icon: Icons.verified_user_outlined,
                      title: 'Verificações institucionais',
                      subtitle:
                          'Aprove ou rejeite solicitações de órgãos e vereadores.',
                      onTap: () =>
                          InstitutionalVerificationScreen.open(context),
                    ),
                    const SizedBox(height: 12),
                    _CenterActionTile(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Moderação e denúncias',
                      subtitle:
                          'Analise conteúdo, preserve o histórico e reverta pontos inválidos.',
                      onTap: () => ModerationQueueScreen.open(context),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Uma ação institucional sempre registra ator, data, descrição e gestão vigente. Nenhum perfil pode marcar uma ocorrência como resolvida sem validação comunitária.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _InstitutionalIntro extends StatelessWidget {
  const _InstitutionalIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17222D), Color(0xFF37536B)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.apartment_rounded, color: Colors.white, size: 30),
          SizedBox(height: 16),
          Text(
            'Transparência por papel',
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Gestão coordena, órgão executa, vereador acompanha e a comunidade confirma o resultado.',
            style: TextStyle(color: Colors.white70, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _AccessSummary extends StatelessWidget {
  const _AccessSummary({required this.access});

  final InstitutionalAccess access;

  @override
  Widget build(BuildContext context) {
    final roles = <String>[
      ...access.administrationMemberships,
      ...access.agencyMemberships,
      if (access.councilorName != null) 'Vereador · ${access.councilorName}',
      ...access.platformRoles.map((role) => 'UrbApp · $role'),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seus acessos',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (roles.isEmpty)
            const Text(
              'Você está usando o UrbApp como cidadão.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else
            ...roles.map(
              (role) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      color: AppColors.resolved,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(role)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CenterActionTile extends StatelessWidget {
  const _CenterActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryDark, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textHint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CouncilorRequestDraft {
  const _CouncilorRequestDraft({
    required this.cityId,
    required this.publicName,
    required this.party,
    required this.mandateStartsOn,
    required this.mandateEndsOn,
    required this.institutionalEmail,
    required this.proofSummary,
    required this.proofLinks,
  });

  final int cityId;
  final String publicName;
  final String party;
  final DateTime mandateStartsOn;
  final DateTime mandateEndsOn;
  final String institutionalEmail;
  final String proofSummary;
  final String proofLinks;
}

class _CouncilorRequestSheet extends StatefulWidget {
  const _CouncilorRequestSheet({required this.cities});

  final List<CityOption> cities;

  @override
  State<_CouncilorRequestSheet> createState() => _CouncilorRequestSheetState();
}

class _CouncilorRequestSheetState extends State<_CouncilorRequestSheet> {
  final _name = TextEditingController();
  final _party = TextEditingController();
  final _email = TextEditingController();
  final _proof = TextEditingController();
  final _links = TextEditingController();
  int? _cityId;
  late DateTime _startsOn;
  late DateTime _endsOn;

  @override
  void initState() {
    super.initState();
    _cityId = widget.cities.firstOrNull?.id;
    final year = DateTime.now().year;
    _startsOn = DateTime(year, 1, 1);
    _endsOn = DateTime(year + 3, 12, 31);
  }

  @override
  void dispose() {
    _name.dispose();
    _party.dispose();
    _email.dispose();
    _proof.dispose();
    _links.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final current = start ? _startsOn : _endsOn;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        _startsOn = selected;
      } else {
        _endsOn = selected;
      }
    });
  }

  void _submit() {
    if (_cityId == null ||
        _name.text.trim().length < 3 ||
        !_email.text.contains('@') ||
        _proof.text.trim().length < 3 ||
        _endsOn.isBefore(_startsOn)) {
      return;
    }
    Navigator.of(context).pop(
      _CouncilorRequestDraft(
        cityId: _cityId!,
        publicName: _name.text.trim(),
        party: _party.text.trim(),
        mandateStartsOn: _startsOn,
        mandateEndsOn: _endsOn,
        institutionalEmail: _email.text.trim(),
        proofSummary: _proof.text.trim(),
        proofLinks: _links.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Solicitar perfil de vereador',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<int>(
              initialValue: _cityId,
              items: widget.cities
                  .map(
                    (city) => DropdownMenuItem<int>(
                      value: city.id,
                      child: Text(city.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _cityId = value),
              decoration: const InputDecoration(labelText: 'Cidade'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome público'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _party,
              decoration: const InputDecoration(labelText: 'Partido'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(true),
                    child: Text('Início ${_formatDate(_startsOn)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(false),
                    child: Text('Fim ${_formatDate(_endsOn)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail institucional',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _proof,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Comprovação e contexto',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _links,
              decoration: const InputDecoration(
                labelText: 'Links públicos de comprovação',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('Enviar para verificação'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
