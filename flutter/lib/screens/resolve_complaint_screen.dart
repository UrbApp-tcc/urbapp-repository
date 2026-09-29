import 'package:flutter/material.dart';

import '../services/feed_service.dart';
import '../services/resolution_service.dart';
import '../theme/urbapp_design.dart';
import '../utils/error_formatter.dart';
import '../widgets/urb_dialog.dart';
import '../widgets/urb_post_image.dart';
import '../widgets/urb_primary_button.dart';
import '../widgets/urb_status_chip.dart';
import '../widgets/urb_text_field.dart';

/// Janela em que o autor informa a solução e pede a validação da comunidade.
class ResolveComplaintScreen extends StatefulWidget {
  const ResolveComplaintScreen({super.key, required this.post});

  final FeedPost post;

  static Future<bool?> open(BuildContext context, FeedPost post) {
    return showUrbDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ResolveComplaintScreen(post: post),
    );
  }

  @override
  State<ResolveComplaintScreen> createState() => _ResolveComplaintScreenState();
}

class _ResolveComplaintScreenState extends State<ResolveComplaintScreen> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  final _service = ResolutionService();

  bool _confirmed = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_confirmed) {
      setState(
        () => _errorMessage =
            'Confirme que o problema foi resolvido para continuar.',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await _service.requestResolution(
        postId: widget.post.id,
        note: _noteController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UrbDialogHeader(
              icon: Icons.task_alt_rounded,
              title: 'Resolver reclamação',
              subtitle: 'Conte o que foi feito. Os vizinhos confirmam.',
              onClose: _isSubmitting
                  ? null
                  : () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: UrbColors.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  UrbPostImage(
                    url: post.primaryImageUrl,
                    height: 56,
                    width: 56,
                    radius: 14,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: UrbText.display(
                            size: 16,
                            weight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${post.categoryName} · ${post.cityName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: UrbText.body(size: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  UrbStatusChip(status: post.status),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Resumo da resolução',
              style: UrbText.body(
                size: 13,
                weight: FontWeight.w700,
                color: const Color(0xFF374151),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _noteController,
              minLines: 4,
              maxLines: 6,
              maxLength: 1000,
              style: UrbText.body(size: 15, color: UrbColors.ink, height: 1.4),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.length < 5)
                  return 'Descreva em poucas palavras o que foi feito.';
                return null;
              },
              decoration: urbInputDecoration(
                hintText: 'Ex.: A prefeitura tapou o buraco na terça-feira.',
              ).copyWith(contentPadding: const EdgeInsets.all(16)),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: _isSubmitting
                  ? null
                  : () => setState(() => _confirmed = !_confirmed),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Checkbox(
                      value: _confirmed,
                      activeColor: UrbColors.violet,
                      onChanged: _isSubmitting
                          ? null
                          : (value) =>
                                setState(() => _confirmed = value ?? false),
                    ),
                    Expanded(
                      child: Text(
                        'Confirmo que o problema foi resolvido.',
                        style: UrbText.body(
                          size: 14,
                          color: const Color(0xFF374151),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: UrbColors.lavender,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.groups_2_outlined,
                    color: UrbColors.violetDeep,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Vizinhos a até 500 m do local vão confirmar. Com 3 confirmações o reporte vira Concluído e você ganha +50 XP.',
                      style: UrbText.body(
                        size: 13,
                        color: const Color(0xFF3F2A8A),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: UrbMotion.of(context, UrbMotion.fast),
              child: _errorMessage == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: UrbText.body(
                          size: 13,
                          color: const Color(0xFFDC2626),
                          height: 1.4,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            UrbPrimaryButton(
              label: 'Pedir validação',
              icon: Icons.task_alt_rounded,
              loading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
