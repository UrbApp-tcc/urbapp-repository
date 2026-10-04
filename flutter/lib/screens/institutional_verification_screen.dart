import 'package:flutter/material.dart';

import '../services/institutional_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';

class InstitutionalVerificationScreen extends StatefulWidget {
  const InstitutionalVerificationScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const InstitutionalVerificationScreen(),
      ),
    );
  }

  @override
  State<InstitutionalVerificationScreen> createState() =>
      _InstitutionalVerificationScreenState();
}

class _InstitutionalVerificationScreenState
    extends State<InstitutionalVerificationScreen> {
  final _service = InstitutionalService();
  List<InstitutionalVerificationRequest> _requests = const [];
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
      final requests = await _service.fetchInstitutionalVerificationQueue();
      if (!mounted) return;
      setState(() => _requests = requests);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _review(InstitutionalVerificationRequest request) async {
    final decision = await showDialog<_VerificationDecision>(
      context: context,
      builder: (_) => const _VerificationDialog(),
    );
    if (decision == null) return;

    setState(() => _processingId = request.id);
    try {
      await _service.reviewInstitutionalRequest(
        request: request,
        approve: decision.approve,
        notes: decision.notes,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verificação institucional concluída.'),
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
      appBar: AppBar(title: const Text('Verificações institucionais')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                itemCount: _requests.isEmpty ? 1 : _requests.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (_requests.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 70),
                      child: Column(
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 50,
                            color: AppColors.resolved,
                          ),
                          SizedBox(height: 12),
                          Text('Nenhuma verificação pendente.'),
                        ],
                      ),
                    );
                  }
                  final request = _requests[index];
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
                          switch (request.kind) {
                            'administration' => 'Prefeitura / gestão municipal',
                            'agency' => 'Órgão / secretaria',
                            _ => 'Vereador',
                          },
                          style: const TextStyle(
                            color: AppColors.primaryDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          request.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${request.cityName} · ${request.institutionalEmail}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          request.proofSummary,
                          style: const TextStyle(height: 1.4),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _processingId == request.id
                                ? null
                                : () => _review(request),
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Revisar identidade'),
                          ),
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

class _VerificationDecision {
  const _VerificationDecision({required this.approve, required this.notes});

  final bool approve;
  final String notes;
}

class _VerificationDialog extends StatefulWidget {
  const _VerificationDialog();

  @override
  State<_VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<_VerificationDialog> {
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Revisar solicitação'),
      content: TextField(
        controller: _notesController,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Notas da revisão',
          alignLabelWithHint: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            _VerificationDecision(
              approve: false,
              notes: _notesController.text.trim(),
            ),
          ),
          child: const Text('Rejeitar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _VerificationDecision(
              approve: true,
              notes: _notesController.text.trim(),
            ),
          ),
          child: const Text('Aprovar'),
        ),
      ],
    );
  }
}
