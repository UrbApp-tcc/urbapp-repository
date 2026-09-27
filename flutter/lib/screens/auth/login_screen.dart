import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/urbapp_design.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/urb_dialog.dart';
import '../../widgets/urb_hero.dart';
import '../../widgets/urb_primary_button.dart';
import '../../widgets/urb_text_field.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

  /// "Tremidinha" do cartão quando o login falha.
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _shake.dispose();
    super.dispose();
  }

  String? _validateIdentifier(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Informe seu e-mail ou nome de usuário';
    }

    final identifier = value.trim();
    if (identifier.startsWith('@')) {
      if (identifier.substring(1).trim().length < 3) {
        return 'Nome de usuário muito curto';
      }
    } else if (identifier.contains('@')) {
      final emailRegex = RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$');
      if (!emailRegex.hasMatch(identifier)) return 'E-mail inválido';
    } else if (identifier.length < 3) {
      return 'Nome de usuário muito curto';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Informe sua senha';
    if (value.length < 6) return 'Senha muito curta';
    return null;
  }

  void _playShake() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _shake.forward(from: 0);
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) {
      _playShake();
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      await _authService.signIn(
        identifier: _emailController.text,
        password: _passwordController.text,
      );
    } catch (error) {
      if (!mounted) return;
      _playShake();
      showUrbSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final currentIdentifier = _emailController.text.trim();
    final initialEmail =
        currentIdentifier.contains('@') && !currentIdentifier.startsWith('@')
        ? currentIdentifier
        : '';

    final sent = await showUrbDialog<bool>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(
        authService: _authService,
        initialEmail: initialEmail,
      ),
    );

    if (!mounted || sent == null) return;
    if (sent) {
      showUrbSnack(
        context,
        'E-mail de redefinição enviado. Verifique sua caixa de entrada.',
      );
    }
  }

  Future<void> _openRegister() async {
    final message = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const RegisterScreen()));

    if (!mounted || message == null) return;
    showUrbSnack(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 700;

    return UrbAuthScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeSlideIn(
            offsetY: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UrbLogoTile(size: compact ? 96 : 120),
                SizedBox(height: compact ? 20 : 28),
                const UrbAuthTitle(
                  title: 'Seja bem-vindo!',
                  subtitle: 'Faça login na sua conta',
                ),
              ],
            ),
          ),
          SizedBox(height: compact ? 28 : 36),
          FadeSlideIn(
            delay: const Duration(milliseconds: 120),
            child: AnimatedBuilder(
              animation: _shake,
              builder: (context, child) {
                final dx =
                    math.sin(_shake.value * math.pi * 5) *
                    10 *
                    (1 - _shake.value);
                return Transform.translate(offset: Offset(dx, 0), child: child);
              },
              child: UrbCard(child: _buildForm()),
            ),
          ),
          const SizedBox(height: 20),
          FadeSlideIn(
            delay: const Duration(milliseconds: 220),
            child: UrbAuthFooterLink(
              text: 'Não tem uma conta?',
              action: 'Criar conta',
              onPressed: _openRegister,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UrbTextField(
              label: 'E-mail ou nome de usuário',
              controller: _emailController,
              icon: Icons.person_outline_rounded,
              hintText: 'seu@email.com ou @usuario',
              validator: _validateIdentifier,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
            ),
            const SizedBox(height: 22),
            UrbTextField(
              label: 'Senha',
              controller: _passwordController,
              icon: Icons.lock_outline_rounded,
              hintText: 'Sua senha',
              validator: _validatePassword,
              obscureText: !_isPasswordVisible,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _signIn(),
              autofillHints: const [AutofillHints.password],
              suffix: PasswordVisibilityToggle(
                visible: _isPasswordVisible,
                onPressed: () =>
                    setState(() => _isPasswordVisible = !_isPasswordVisible),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _showForgotPasswordDialog,
                child: Text(
                  'Esqueceu sua senha?',
                  style: UrbText.body(
                    size: 14,
                    weight: FontWeight.w700,
                    color: UrbColors.violetDeep,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            UrbPrimaryButton(
              label: 'Entrar',
              loading: _isLoading,
              onPressed: _signIn,
            ),
          ],
        ),
      ),
    );
  }
}

/// Janela flutuante "Redefinir senha".
class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({
    required this.authService,
    required this.initialEmail,
  });

  final AuthService authService;
  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  bool _isSending = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      await widget.authService.resetPassword(_emailController.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _errorMessage = friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UrbDialogHeader(
              icon: Icons.lock_outline_rounded,
              title: 'Redefinir senha',
              subtitle: 'Enviaremos um link para o seu e-mail.',
              onClose: _isSending ? null : () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            UrbTextField(
              label: 'E-mail',
              controller: _emailController,
              icon: Icons.mail_outline_rounded,
              hintText: 'seu@email.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _send(),
              validator: (value) {
                if (value == null || value.trim().isEmpty)
                  return 'Informe seu e-mail';
                final regex = RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$');
                if (!regex.hasMatch(value.trim())) return 'E-mail inválido';
                return null;
              },
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
            Row(
              children: [
                Expanded(
                  child: UrbSecondaryButton(
                    label: 'Cancelar',
                    onPressed: _isSending
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: UrbPrimaryButton(
                    label: 'Enviar',
                    loading: _isSending,
                    onPressed: _send,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
