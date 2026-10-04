import 'package:flutter/material.dart';

import '../services/agency_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';

class AgencyProfilesScreen extends StatefulWidget {
  const AgencyProfilesScreen({super.key, required this.currentUserId});

  final String currentUserId;

  static Future<void> open(
    BuildContext context, {
    required String currentUserId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AgencyProfilesScreen(currentUserId: currentUserId),
      ),
    );
  }

  @override
  State<AgencyProfilesScreen> createState() => _AgencyProfilesScreenState();
}

class _AgencyProfilesScreenState extends State<AgencyProfilesScreen> {
  final _agencyService = AgencyService();

  List<ManagedAgencyProfile> _approvedAgencies = const [];
  List<AgencyProfileRequest> _requests = const [];
  List<AgencyCityOption> _cities = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _agencyService.fetchCities(),
        _agencyService.fetchManagedAgencies(widget.currentUserId),
        _agencyService.fetchOwnAgencyRequests(widget.currentUserId),
      ]);

      if (!mounted) return;
      setState(() {
        _cities = results[0] as List<AgencyCityOption>;
        _approvedAgencies = results[1] as List<ManagedAgencyProfile>;
        _requests = results[2] as List<AgencyProfileRequest>;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openRequestSheet() async {
    if (_cities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cadastre cidades antes de enviar uma solicitação institucional.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) =>
          _RequestAgencySheet(cities: _cities, agencyService: _agencyService),
    );

    if (created == true) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      const Text(
                        'Perfis institucionais',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _openRequestSheet,
                        icon: const Icon(Icons.fact_check_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Solicitação institucional',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'O cidadão envia uma solicitação com provas de vínculo institucional. Depois disso, um administrador revisa e aprova manualmente o perfil da secretaria ou órgão.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _openRequestSheet,
                    icon: const Icon(Icons.account_balance_outlined),
                    label: const Text(
                      'Solicitar perfil de prefeitura/secretaria',
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Solicitações enviadas',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_requests.isEmpty)
                    _emptyCard(
                      'Você ainda não enviou nenhuma solicitação institucional.',
                    )
                  else
                    ..._requests.map(
                      (request) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AgencyRequestCard(request: request),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    'Perfis aprovados',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_approvedAgencies.isEmpty)
                    _emptyCard(
                      'Você ainda não está vinculado a nenhum perfil institucional aprovado.',
                    )
                  else
                    ..._approvedAgencies.map(
                      (agency) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ApprovedAgencyCard(agency: agency),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      ),
    );
  }
}

class _AgencyRequestCard extends StatelessWidget {
  const _AgencyRequestCard({required this.request});

  final AgencyProfileRequest request;

  @override
  Widget build(BuildContext context) {
    final statusPalette = switch (request.status) {
      'approved' => (
        bg: const Color(0xFFE8F8F0),
        fg: AppColors.resolved,
        label: 'Aprovado',
      ),
      'rejected' => (
        bg: const Color(0xFFFDECEC),
        fg: AppColors.error,
        label: 'Rejeitado',
      ),
      _ => (
        bg: const Color(0xFFFFF4E5),
        fg: AppColors.pending,
        label: 'Em análise',
      ),
    };

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
          Row(
            children: [
              Expanded(
                child: Text(
                  request.agencyName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusPalette.bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusPalette.label,
                  style: TextStyle(
                    color: statusPalette.fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${request.requestKind == 'administration' ? 'Gestão municipal' : request.agencyType} · ${request.cityName}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          if ((request.requesterRole ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Cargo informado: ${request.requesterRole}',
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            request.proofSummary,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if ((request.proofLinks ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Links/provas: ${request.proofLinks}',
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApprovedAgencyCard extends StatelessWidget {
  const _ApprovedAgencyCard({required this.agency});

  final ManagedAgencyProfile agency;

  @override
  Widget build(BuildContext context) {
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
          Text(
            agency.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${agency.type} · ${agency.cityName}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            agency.contactEmail,
            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Text(
            'Seu papel: ${agency.role}',
            style: const TextStyle(
              color: AppColors.primaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestAgencySheet extends StatefulWidget {
  const _RequestAgencySheet({
    required this.cities,
    required this.agencyService,
  });

  final List<AgencyCityOption> cities;
  final AgencyService agencyService;

  @override
  State<_RequestAgencySheet> createState() => _RequestAgencySheetState();
}

class _RequestAgencySheetState extends State<_RequestAgencySheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _emailController = TextEditingController();
  final _roleController = TextEditingController();
  final _proofSummaryController = TextEditingController();
  final _proofLinksController = TextEditingController();
  bool _isSaving = false;
  int? _selectedCityId;
  String _requestKind = 'agency';

  @override
  void initState() {
    super.initState();
    if (widget.cities.isNotEmpty) _selectedCityId = widget.cities.first.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _emailController.dispose();
    _roleController.dispose();
    _proofSummaryController.dispose();
    _proofLinksController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _selectedCityId == null) return;

    setState(() => _isSaving = true);

    try {
      await widget.agencyService.createAgencyProfileRequest(
        cityId: _selectedCityId!,
        name: _nameController.text,
        type: _typeController.text,
        requestKind: _requestKind,
        contactEmail: _emailController.text,
        requesterRole: _roleController.text,
        proofSummary: _proofSummaryController.text,
        proofLinks: _proofLinksController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitação institucional enviada para análise.'),
          backgroundColor: AppColors.resolved,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Solicitar perfil institucional',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Explique seu vínculo com a secretaria/órgão e anexe links ou evidências para a revisão do administrador.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _requestKind,
                items: const [
                  DropdownMenuItem(
                    value: 'agency',
                    child: Text('Secretaria ou órgão municipal'),
                  ),
                  DropdownMenuItem(
                    value: 'administration',
                    child: Text('Prefeitura / gestão municipal'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _requestKind = value);
                },
                decoration: const InputDecoration(
                  labelText: 'Perfil solicitado',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _selectedCityId,
                items: widget.cities
                    .map(
                      (city) => DropdownMenuItem<int>(
                        value: city.id,
                        child: Text(city.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedCityId = value),
                decoration: const InputDecoration(labelText: 'Cidade'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: _requestKind == 'administration'
                      ? 'Nome da gestão/prefeitura'
                      : 'Nome da secretaria/órgão',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o nome institucional.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _typeController,
                decoration: InputDecoration(
                  labelText: 'Tipo',
                  hintText: _requestKind == 'administration'
                      ? 'Ex.: Prefeitura Municipal'
                      : 'Secretaria, autarquia, empresa pública...',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o tipo do órgão.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail institucional',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe o e-mail institucional.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _roleController,
                decoration: const InputDecoration(
                  labelText: 'Seu cargo/função',
                  hintText: 'Ex.: assessor, diretor, servidor, terceirizado...',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _proofSummaryController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Provas e contexto',
                  hintText:
                      'Descreva como você comprova o vínculo institucional.',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Descreva as provas para análise.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _proofLinksController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Links de apoio',
                  hintText:
                      'Links de portal oficial, LinkedIn, nomeação, site da prefeitura...',
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: Text(_isSaving ? 'Enviando...' : 'Enviar solicitação'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
