import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../services/institutional_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

class AdministrationContactScreen extends StatefulWidget {
  const AdministrationContactScreen({super.key, required this.membership});

  final InstitutionalMembership membership;

  @override
  State<AdministrationContactScreen> createState() =>
      _AdministrationContactScreenState();
}

class _AdministrationContactScreenState
    extends State<AdministrationContactScreen> {
  static const _kinds = [
    ('content_contestation', 'Contestação de publicação'),
    ('credentialing', 'Credenciamento institucional'),
    ('profile_creation', 'Criação de perfil institucional'),
    ('profile_update', 'Atualização de perfil institucional'),
    ('support_partnership', 'Suporte ou parceria'),
  ];

  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final List<PlatformFile> _attachments = [];
  String _kind = _kinds.first.$1;
  bool _sending = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  String? _validateSubject(String? value) {
    final length = value?.trim().length ?? 0;
    if (length < 5) return 'Informe um título com pelo menos 5 caracteres.';
    return null;
  }

  String? _validateMessage(String? value) {
    final length = value?.trim().length ?? 0;
    if (length < 20) {
      return 'Descreva o pedido em pelo menos 20 caracteres.';
    }
    return null;
  }

  Future<void> _send() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await InstitutionalService().createAdministrationContactRequest(
        administrationId: widget.membership.id,
        kind: _kind,
        subject: _subject.text,
        message: _message.text,
        attachments: _attachments,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        showUrbToast(context, friendlyError(error));
      }
    }
  }

  Future<void> _pickAttachments() async {
    final remaining = 5 - _attachments.length;
    if (remaining <= 0) {
      showUrbToast(context, 'Você pode adicionar até 5 mídias.');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'mp4',
        'mov',
        'webm',
      ],
      withData: true,
    );
    if (result == null || !mounted) return;
    final accepted = result.files
        .where((file) => file.size > 0 && file.size <= 52428800)
        .take(remaining)
        .toList();
    final rejected = result.files.length - accepted.length;
    setState(() => _attachments.addAll(accepted));
    if (rejected > 0) {
      showUrbToast(
        context,
        'Algumas mídias foram ignoradas. Use até 5 arquivos de no máximo 50 MB cada.',
      );
    }
  }

  String _fileSizeLabel(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: UrbColors.canvas,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              children: [
                UrbSquareButton(
                  icon: UrbIcons.chevronLeft,
                  tooltip: 'Voltar',
                  size: 36,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Contatar administradores',
                    style: UrbText.screenTitle.copyWith(fontSize: 20),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: UrbColors.blueSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: UrbColors.blue.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          const UrbIcon(
                            UrbIcons.building,
                            size: 22,
                            color: UrbColors.blue,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.membership.name,
                                  style: UrbText.titleSmall,
                                ),
                                Text(
                                  widget.membership.cityName ??
                                      'Gestão municipal',
                                  style: UrbText.caption,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('Tipo de contato', style: UrbText.label),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _kind,
                      decoration: const InputDecoration(),
                      items: [
                        for (final kind in _kinds)
                          DropdownMenuItem(
                            value: kind.$1,
                            child: Text(kind.$2),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _kind = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    UrbTextField(
                      label: 'Título do pedido',
                      hint: 'Resuma o que precisa ser analisado',
                      controller: _subject,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.sentences,
                      validator: _validateSubject,
                    ),
                    const SizedBox(height: 16),
                    UrbTextField(
                      label: 'Descrição',
                      hint:
                          'Explique o contexto, o resultado esperado e as informações que podem ajudar na análise.',
                      controller: _message,
                      minLines: 5,
                      maxLines: 8,
                      maxLength: 1500,
                      textCapitalization: TextCapitalization.sentences,
                      validator: _validateMessage,
                    ),
                    const SizedBox(height: 16),
                    UrbButton(
                      label: _attachments.isEmpty
                          ? 'Adicionar prints ou vídeos'
                          : 'Adicionar mais mídias',
                      icon: UrbIcons.camera,
                      tone: UrbButtonTone.outline,
                      expand: true,
                      onPressed: _pickAttachments,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Opcional · até 5 imagens ou vídeos de 50 MB cada',
                      style: UrbText.caption,
                    ),
                    if (_attachments.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (var index = 0; index < _attachments.length; index++)
                        Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.fromLTRB(11, 8, 5, 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: UrbColors.line),
                          ),
                          child: Row(
                            children: [
                              const UrbIcon(
                                UrbIcons.camera,
                                size: 17,
                                color: UrbColors.blue,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _attachments[index].name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: UrbText.bodySmall.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      _fileSizeLabel(_attachments[index].size),
                                      style: UrbText.caption,
                                    ),
                                  ],
                                ),
                              ),
                              UrbSquareButton(
                                icon: UrbIcons.close,
                                tooltip: 'Remover mídia',
                                size: 30,
                                iconSize: 15,
                                onPressed: () => setState(
                                  () => _attachments.removeAt(index),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'O pedido será enviado aos administradores do UrbApp com a identificação desta gestão.',
                      style: UrbText.caption,
                    ),
                    const SizedBox(height: 20),
                    UrbButton(
                      label: 'Enviar pedido',
                      icon: UrbIcons.message,
                      expand: true,
                      height: 50,
                      loading: _sending,
                      onPressed: _send,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
