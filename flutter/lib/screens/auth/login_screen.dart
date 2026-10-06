import 'package:flutter/material.dart';

import '../../app/institutional_intent.dart';
import '../../app/routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import 'institutional_onboarding_screen.dart';
import 'register_screen.dart';

final _emailPattern = RegExp(r'^[\w.+-]+@[\w.-]+\.\w{2,}$');

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _showPassword = false;
  bool _loading = false;
  bool _googleLoading = false;
  InstitutionalKind? _pendingKind = InstitutionalIntent.pending;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _openInstitutional() async {
    final kind = await Navigator.of(context).push<InstitutionalKind>(urbRoute(const InstitutionalOnboardingScreen()));
    if (mounted) setState(() => _pendingKind = kind ?? InstitutionalIntent.pending);
  }

  void _cancelInstitutional() {
    InstitutionalIntent.pending = null;
    setState(() => _pendingKind = null);
  }

  String? _validateIdentifier(String? value) {
    final identifier = value?.trim() ?? '';
    if (identifier.isEmpty) return 'Informe seu e-mail ou nome de usuário';
    if (identifier.contains('@') && !identifier.startsWith('@')) {
      return _emailPattern.hasMatch(identifier) ? null : 'E-mail inválido';
    }
    final username = identifier.startsWith('@') ? identifier.substring(1) : identifier;
    return username.trim().length < 3 ? 'Nome de usuário muito curto' : null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _authService.signIn(identifier: _identifierController.text, password: _passwordController.text);
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    setState(() => _googleLoading = true);
    try {
      await _authService.signInWithGoogle();
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final initial = _identifierController.text.trim();
    final controller = TextEditingController(text: _emailPattern.hasMatch(initial) ? initial : '');
    final formKey = GlobalKey<FormState>();
    await showUrbSheet<void>(
      context: context,
      eyebrow: 'Acesso',
      title: 'Redefinir senha',
      intro: 'Enviaremos um link para o e-mail cadastrado na sua conta.',
      builder: (sheetContext) {
        var sending = false;
        return StatefulBuilder(
          builder: (context, setSheetState) => Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UrbTextField(
                  label: 'E-mail',
                  controller: controller,
                  hint: 'seuemail@exemplo.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) =>
                      _emailPattern.hasMatch(value?.trim() ?? '') ? null : 'Informe um e-mail válido',
                ),
                const SizedBox(height: 18),
                UrbPrimaryButton(
                  label: 'Enviar link',
                  loading: sending,
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    setSheetState(() => sending = true);
                    try {
                      await _authService.resetPassword(controller.text);
                      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                      if (mounted) showUrbToast(this.context, 'Link enviado. Verifique sua caixa de entrada.');
                    } catch (error) {
                      setSheetState(() => sending = false);
                      if (mounted) showUrbToast(this.context, friendlyError(error));
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      body: Stack(
        children: [
          const Positioned(top: -80, right: -77, child: UrbBrandGeometry()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, topInset > 0 ? 36 : 64, 20, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Align(alignment: Alignment.centerLeft, child: UrbBrand()),
                          const SizedBox(height: 42),
                          const UrbEyebrow('A cidade também é sua'),
                          const SizedBox(height: 12),
                          Semantics(
                            header: true,
                            child: Text('Sua cidade.\nSua voz.', style: UrbText.display),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Participe, acompanhe e ajude a melhorar o lugar onde você vive.',
                            style: UrbText.body.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 30),
                          if (_pendingKind != null) ...[
                            _InstitutionalPendingNotice(kind: _pendingKind!, onCancel: _cancelInstitutional),
                            const SizedBox(height: 18),
                          ],
                          UrbTextField(
                            label: 'E-mail',
                            controller: _identifierController,
                            hint: 'seuemail@exemplo.com',
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email, AutofillHints.username],
                            validator: _validateIdentifier,
                          ),
                          const SizedBox(height: 19),
                          UrbTextField(
                            label: 'Senha',
                            trailingLabel: UrbTextButton('Esqueci minha senha', onPressed: _forgotPassword),
                            controller: _passwordController,
                            hint: 'Digite sua senha',
                            obscure: !_showPassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _submit(),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Informe sua senha';
                              if (value.length < 6) return 'Senha muito curta';
                              return null;
                            },
                            suffix: IconButton(
                              tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                              icon: UrbIcon(
                                _showPassword ? UrbIcons.eye : UrbIcons.eyeOff,
                                size: 19,
                                color: const Color(0xFF758296),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          UrbPrimaryButton(label: 'Entrar', loading: _loading, onPressed: _submit),
                          const SizedBox(height: 23),
                          Row(
                            children: [
                              const Expanded(child: Divider(color: Color(0xFFDCE2E7))),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 13),
                                child: Text('ou', style: UrbText.caption),
                              ),
                              const Expanded(child: Divider(color: Color(0xFFDCE2E7))),
                            ],
                          ),
                          const SizedBox(height: 23),
                          _GoogleButton(loading: _googleLoading, onPressed: _google),
                          const SizedBox(height: 30),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('Ainda não tem uma conta? ', style: UrbText.meta),
                              UrbTextButton(
                                'Criar conta',
                                onPressed: () => Navigator.of(context).push(urbRoute(const RegisterScreen())),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _InstitutionalEntry(onTap: _openInstitutional),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Atalho discreto para vereadores, órgãos e gestão municipal.
class _InstitutionalEntry extends StatelessWidget {
  const _InstitutionalEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Acesso institucional para vereadores, órgãos e gestão municipal',
      excludeSemantics: true,
      child: Material(
        color: Colors.white.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UrbRadius.md),
          side: const BorderSide(color: Color(0xFFD5DCE4)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(UrbRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const UrbIcon(UrbIcons.building, size: 20, color: UrbColors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Representa uma instituição?', style: UrbText.label.copyWith(color: UrbColors.navy, fontWeight: FontWeight.w800)),
                      Text('Acesso para vereadores, órgãos e gestão municipal', style: UrbText.caption),
                    ],
                  ),
                ),
                const UrbIcon(UrbIcons.chevron, size: 16, color: UrbColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InstitutionalPendingNotice extends StatelessWidget {
  const _InstitutionalPendingNotice({required this.kind, required this.onCancel});

  final InstitutionalKind kind;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(color: UrbColors.blueSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const UrbIcon(UrbIcons.building, size: 18, color: UrbColors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Depois de entrar, abriremos a solicitação de perfil: ${kind.label.toLowerCase()}.',
              style: UrbText.caption.copyWith(color: UrbColors.navy),
            ),
          ),
          UrbTextButton('Cancelar', onPressed: onCancel),
        ],
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UrbRadius.md),
        side: const BorderSide(color: Color(0xFFD5DCE4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(UrbRadius.md),
        onTap: loading ? null : onPressed,
        child: SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else
                ShaderMask(
                  shaderCallback: (bounds) => const SweepGradient(
                    colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335), Color(0xFF4285F4)],
                    startAngle: -0.8,
                  ).createShader(bounds),
                  child: Text('G', style: UrbText.h3.copyWith(color: Colors.white, fontSize: 19)),
                ),
              const SizedBox(width: 14),
              Text('Continuar com Google', style: UrbText.label.copyWith(color: const Color(0xFF102039), fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
