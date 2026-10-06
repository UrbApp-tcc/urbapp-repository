import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_session.dart';
import '../../app/routes.dart';
import '../../domain/models.dart';
import '../../services/auth_service.dart';
import '../../services/institutional_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/city_picker.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import '../admin/admin_governance_screen.dart';
import '../admin/institutional_verification_screen.dart';
import '../admin/moderation_queue_screen.dart';
import '../institutional/access_request_screen.dart';
import '../institutional/workspace_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.profile, required this.access});

  final UserProfile profile;
  final InstitutionalAccess access;

  void _push(BuildContext context, Widget page) => Navigator.of(context).push(urbRoute(page));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Configurações'),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        children: [
          const UrbGroupLabel('Conta'),
          UrbSettingsRow(label: 'Editar perfil', onTap: () => _push(context, EditProfileScreen(profile: profile))),
          UrbSettingsRow(label: 'Conta e segurança', onTap: () => _push(context, AccountSecurityScreen(profile: profile))),
          const UrbGroupLabel('Privacidade'),
          UrbSettingsRow(label: 'Privacidade', onTap: () => _push(context, PrivacyScreen(profile: profile))),
          const UrbGroupLabel('Notificações'),
          UrbSettingsRow(label: 'Preferências de alertas', onTap: () => _push(context, const NotificationPreferencesScreen())),
          const UrbGroupLabel('Atuação institucional'),
          if (access.hasInstitutionalRole)
            UrbSettingsRow(label: 'Sua atuação', onTap: () => _push(context, const WorkspaceScreen())),
          UrbSettingsRow(
            label: 'Solicitar perfil institucional',
            subtitle: 'Vereador, órgão municipal ou gestão municipal',
            onTap: () => _push(context, const AccessRequestScreen()),
          ),
          if (access.isPlatformAdmin) ...[
            const UrbGroupLabel('Administração do UrbApp'),
            UrbSettingsRow(label: 'Moderação e denúncias', onTap: () => _push(context, const ModerationQueueScreen())),
            UrbSettingsRow(label: 'Verificação institucional', onTap: () => _push(context, const InstitutionalVerificationScreen())),
            UrbSettingsRow(label: 'Governança da plataforma', onTap: () => _push(context, const AdminGovernanceScreen())),
          ],
          const UrbGroupLabel('Aplicativo'),
          UrbSettingsRow(label: 'Sobre o UrbApp', onTap: () => _push(context, const AboutScreen())),
          UrbSettingsRow(label: 'Termos e privacidade', onTap: () => _push(context, const TermsScreen())),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            child: UrbButton(
              label: 'Sair da conta',
              tone: UrbButtonTone.danger,
              height: 50,
              expand: true,
              onPressed: () async {
                final confirmed = await UrbConfirmSheet.show(
                  context,
                  title: 'Sair da conta?',
                  message: 'Você terá que fazer login novamente para acessar seu perfil e participar da comunidade.',
                  confirmLabel: 'Confirmar saída',
                  destructive: true,
                );
                if (!confirmed || !context.mounted) return;
                Navigator.of(context).popUntil((route) => route.isFirst);
                await AuthService().signOut();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ProfileService();
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _username = TextEditingController(text: widget.profile.username);
  late final _bio = TextEditingController(text: widget.profile.biography ?? '');
  CityOption? _city;
  String? _avatarUrl;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.profile.avatarUrl;
    final cities = AppSession.instance.cities;
    _city = cities.where((city) => city.id == widget.profile.cityId).firstOrNull;
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _changePhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final url = await _service.uploadAvatar(file);
      if (mounted) setState(() => _avatarUrl = url);
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _service.updateProfile(
        fullName: _name.text,
        username: _username.text,
        biography: _bio.text,
        cityId: _city?.id,
        avatarUrl: _avatarUrl != widget.profile.avatarUrl ? _avatarUrl : null,
      );
      if (_city != null && _city!.id != AppSession.instance.city.value?.id) {
        AppSession.instance.city.value = _city;
      }
      if (!mounted) return;
      showUrbToast(context, 'Perfil atualizado.');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Editar perfil'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
          children: [
            Center(
              child: Column(
                children: [
                  UrbAvatar(name: _name.text, imageUrl: _avatarUrl, size: 86, rounded: false, gradientSeed: _avatarUrl == null ? 0 : null),
                  const SizedBox(height: 8),
                  _uploading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : UrbTextButton('Alterar foto', onPressed: _changePhoto),
                ],
              ),
            ),
            const SizedBox(height: 20),
            UrbTextField(
              label: 'Nome exibido',
              controller: _name,
              validator: (value) => (value?.trim().length ?? 0) < 2 ? 'Informe seu nome' : null,
            ),
            const SizedBox(height: 18),
            UrbTextField(
              label: 'Nome de usuário',
              controller: _username,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.length < 3) return 'Use pelo menos 3 caracteres';
                if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(text)) return 'Use apenas letras, números, pontos e _';
                return null;
              },
            ),
            const SizedBox(height: 18),
            UrbTextField(label: 'Sobre você', controller: _bio, hint: 'Escreva algo sobre você…', maxLines: 3, minLines: 3, maxLength: 240),
            const SizedBox(height: 10),
            Text('Cidade', style: UrbText.label),
            const SizedBox(height: 8),
            CitySelectorButton(
              city: _city,
              label: 'Cidade do perfil',
              onTap: () async {
                final picked = await showCityPicker(context, cities: AppSession.instance.cities, selected: _city);
                if (picked != null) setState(() => _city = picked);
              },
            ),
            const SizedBox(height: 26),
            UrbPrimaryButton(label: 'Salvar alterações', icon: UrbIcons.check, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class AccountSecurityScreen extends StatelessWidget {
  const AccountSecurityScreen({super.key, required this.profile});

  final UserProfile profile;

  String _maskEmail(String? email) {
    if (email == null || !email.contains('@')) return '—';
    final parts = email.split('@');
    final name = parts.first;
    final visible = name.length <= 3 ? name : name.substring(0, 3);
    return '$visible****@${parts.last}';
  }

  @override
  Widget build(BuildContext context) {
    final email = ProfileService().currentEmail;
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Conta e segurança'),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        children: [
          const UrbGroupLabel('Informações da conta'),
          UrbSettingsRow(label: 'E-mail', value: _maskEmail(email)),
          UrbSettingsRow(label: 'Nome de usuário', value: '@${profile.username}'),
          if (profile.createdAt != null) UrbSettingsRow(label: 'Membro desde', value: formatMonthYear(profile.createdAt!)),
          const UrbGroupLabel('Acesso'),
          UrbSettingsRow(
            label: 'Alterar senha',
            subtitle: 'Enviaremos um link de redefinição para o seu e-mail',
            onTap: email == null
                ? null
                : () async {
                    try {
                      await AuthService().resetPassword(email);
                      if (context.mounted) showUrbToast(context, 'Link de redefinição enviado para o seu e-mail.');
                    } catch (error) {
                      if (context.mounted) showUrbToast(context, friendlyError(error));
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late bool _public = widget.profile.isPublic;

  Future<void> _toggle(bool value) async {
    setState(() => _public = value);
    try {
      await ProfileService().setPublicProfile(value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _public = !value);
      showUrbToast(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Privacidade'),
      body: ListView(
        padding: const EdgeInsets.only(top: 16),
        children: [
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: UrbColors.line))),
            child: UrbSettingsRow(
              label: 'Perfil público',
              subtitle: 'Outros cidadãos podem ver suas contribuições públicas.',
              trailing: UrbSwitch(value: _public, label: 'Perfil público', onChanged: _toggle),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const UrbIcon(UrbIcons.eyeOff, size: 16, color: UrbColors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Relatos publicados anonimamente nunca revelam sua identidade ao público, a vereadores, à Prefeitura ou aos órgãos. '
                    'O UrbApp mantém o vínculo internamente apenas para moderação, segurança e prevenção de fraudes.',
                    style: UrbText.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen> {
  final _service = ProfileService();
  NotificationPreferences? _preferences;

  static const _items = [
    ('occurrence_updates', 'Atualizações das ocorrências que acompanho'),
    ('comments', 'Comentários e respostas'),
    ('official_updates', 'Atualizações oficiais de órgãos e da gestão'),
    ('validations', 'Validações comunitárias disponíveis'),
    ('councilor_activity', 'Atuação de vereadores nas ocorrências'),
  ];

  @override
  void initState() {
    super.initState();
    _service.fetchNotificationPreferences().then((value) {
      if (mounted) setState(() => _preferences = value);
    }).catchError((Object error) {
      if (mounted) setState(() => _preferences = const NotificationPreferences());
    });
  }

  bool _value(String key) {
    final preferences = _preferences!;
    return switch (key) {
      'occurrence_updates' => preferences.occurrenceUpdates,
      'comments' => preferences.comments,
      'official_updates' => preferences.officialUpdates,
      'validations' => preferences.validations,
      _ => preferences.councilorActivity,
    };
  }

  Future<void> _set(String key, bool value) async {
    final previous = _preferences!;
    final next = previous.copyWithKey(key, value);
    setState(() => _preferences = next);
    try {
      await _service.saveNotificationPreferences(next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _preferences = previous);
      showUrbToast(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Preferências de alertas'),
      body: _preferences == null
          ? const UrbLoadingView()
          : ListView(
              padding: const EdgeInsets.only(top: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text('Escolha quais atividades geram alertas para você.', style: UrbText.bodySmall),
                ),
                Container(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: UrbColors.line))),
                  child: Column(
                    children: [
                      for (final item in _items)
                        UrbSettingsRow(
                          label: item.$2,
                          trailing: UrbSwitch(value: _value(item.$1), label: item.$2, onChanged: (value) => _set(item.$1, value)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _TextPage extends StatelessWidget {
  const _TextPage({required this.title, required this.sections, this.showBrand = false});

  final String title;
  final List<(String, List<String>)> sections;
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: UrbSubscreenHeader(title: title),
      body: ListView(
        padding: const EdgeInsets.only(top: 20, bottom: 48),
        children: [
          if (showBrand)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: UrbColors.line))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const UrbBrand(),
                  const SizedBox(height: 6),
                  Text('Versão 1.0.0', style: UrbText.caption),
                ],
              ),
            ),
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UrbEyebrow(section.$1, muted: true),
                  const SizedBox(height: 10),
                  for (final paragraph in section.$2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(paragraph, style: UrbText.bodySmall.copyWith(color: UrbColors.navy, height: 1.6)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TextPage(
      title: 'Sobre o UrbApp',
      showBrand: true,
      sections: [
        (
          'Nossa missão',
          [
            'O UrbApp conecta cidadãos, poder público e vereadores em torno de um objetivo comum: tornar a cidade mais justa, segura e funcional.',
            'O cidadão registra e fiscaliza; a Prefeitura coordena e responde; o órgão executa; o vereador acompanha e fiscaliza; '
                'a comunidade confirma o resultado; e o UrbApp registra tudo e transforma essas ações em transparência e indicadores públicos.',
          ],
        ),
        (
          'Como uma ocorrência é resolvida',
          [
            'Qualquer ator pode informar uma possível resolução, mas ela só é confirmada quando cidadãos próximos validam o que aconteceu no local.',
          ],
        ),
        ('Contato', ['contato@urbapp.com.br']),
      ],
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TextPage(
      title: 'Termos e privacidade',
      sections: [
        (
          'Termos de uso',
          [
            'Ao usar o UrbApp, você concorda em publicar informações verdadeiras sobre problemas urbanos e em respeitar outras pessoas.',
            'Conteúdos falsos, ofensivos ou que exponham dados pessoais podem ser removidos pela moderação, preservando o histórico interno.',
          ],
        ),
        (
          'Política de privacidade',
          [
            'Coletamos apenas os dados necessários para o funcionamento do aplicativo, incluindo a localização aproximada das ocorrências e das validações.',
            'Relatos publicados anonimamente não associam seu nome ou identidade à publicação pública.',
          ],
        ),
      ],
    );
  }
}
