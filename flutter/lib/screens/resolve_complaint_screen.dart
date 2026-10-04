import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/feed_service.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';

class ResolveComplaintScreen extends StatefulWidget {
  const ResolveComplaintScreen({super.key, required this.post});

  final FeedPost post;

  static Future<bool?> open(BuildContext context, FeedPost post) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ResolveComplaintScreen(post: post),
      ),
    );
  }

  @override
  State<ResolveComplaintScreen> createState() => _ResolveComplaintScreenState();
}

class _ResolveComplaintScreenState extends State<ResolveComplaintScreen> {
  final _postService = PostService();
  final _noteController = TextEditingController();

  bool _isSubmitting = false;
  bool _confirmResolution = false;
  XFile? _evidence;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitResolution() async {
    if (!_confirmResolution) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Confirme que o problema aparenta estar resolvido para continuar.',
          ),
          backgroundColor: AppColors.pending,
        ),
      );
      return;
    }

    if (_noteController.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Descreva a possível resolução.'),
          backgroundColor: AppColors.pending,
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      await _postService.openResolutionCycle(
        postId: widget.post.id,
        note: _noteController.text,
        evidence: _evidence,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Validação comunitária aberta com sucesso.'),
          backgroundColor: AppColors.resolved,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _pickEvidence() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file != null && mounted) setState(() => _evidence = file);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
        ),
        title: const Text('Informar possível resolução'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _ResolutionHero(post: widget.post),
            const SizedBox(height: 20),
            const Text(
              'Evidência da possível resolução',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              minLines: 5,
              maxLines: 8,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText:
                    'Descreva o que mudou e por que o problema aparenta estar resolvido.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _pickEvidence,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _evidence == null
                    ? 'Adicionar foto recente (recomendado)'
                    : _evidence!.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_evidence != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(() => _evidence = null),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Remover foto'),
                ),
              ),
            const SizedBox(height: 14),
            _ConfirmationTile(
              value: _confirmResolution,
              onChanged: _isSubmitting
                  ? null
                  : (value) =>
                        setState(() => _confirmResolution = value ?? false),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitResolution,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: Text(
                _isSubmitting
                    ? 'Abrindo validação...'
                    : 'Enviar para validação',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'A ocorrência ficará aguardando validação. O quórum, o raio e o prazo vigentes serão registrados neste ciclo; esta ação não a resolve sozinha.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.95),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolutionHero extends StatelessWidget {
  const _ResolutionHero({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.resolved.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.task_alt_rounded,
              color: AppColors.resolved,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    height: 1.22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.label_outline_rounded,
                      label: post.categoryName,
                    ),
                    _InfoChip(
                      icon: Icons.location_city_outlined,
                      label: post.cityName,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmationTile extends StatelessWidget {
  const _ConfirmationTile({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value ? AppColors.resolved : AppColors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Confirmo que o problema aparenta estar resolvido e pode ser enviado à validação comunitária.',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
