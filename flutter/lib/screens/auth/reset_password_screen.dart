import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/urb_dialog.dart';
import '../../widgets/urb_hero.dart';
import '../../widgets/urb_primary_button.dart';
import '../../widgets/urb_text_field.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authService = AuthService();

  bool _isPasswordVisible = false;
  bool _isConfirmVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Informe a nova senha';
    if (value.length < 6) return 'Mínimo de 6 caracteres';
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) return 'Confirme a nova senha';
    if (value != _passwordController.text) return 'As senhas não coincidem';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      await _authService.updatePassword(_passwordController.text);
      if (!mounted) return;
      showUrbSnack(context, 'Senha atualizada com sucesso!');
    } catch (error) {
      if (!mounted) return;
      showUrbSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return UrbAuthScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeSlideIn(
            offsetY: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 24),
                const UrbAuthTitle(
                  title: 'Nova senha',
                  subtitle: 'Escolha uma senha forte para a sua conta',
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          FadeSlideIn(
            delay: const Duration(milliseconds: 120),
            child: UrbCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UrbTextField(
                      label: 'Nova senha',
                      controller: _passwordController,
                      icon: Icons.lock_outline_rounded,
                      hintText: 'Mínimo de 6 caracteres',
                      validator: _validatePassword,
                      obscureText: !_isPasswordVisible,
                      autofillHints: const [AutofillHints.newPassword],
                      suffix: PasswordVisibilityToggle(
                        visible: _isPasswordVisible,
                        onPressed: () => setState(
                          () => _isPasswordVisible = !_isPasswordVisible,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    UrbTextField(
                      label: 'Confirmar nova senha',
                      controller: _confirmController,
                      icon: Icons.lock_outline_rounded,
                      hintText: 'Repita a nova senha',
                      validator: _validateConfirm,
                      obscureText: !_isConfirmVisible,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      suffix: PasswordVisibilityToggle(
                        visible: _isConfirmVisible,
                        onPressed: () => setState(
                          () => _isConfirmVisible = !_isConfirmVisible,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    UrbPrimaryButton(
                      label: 'Salvar nova senha',
                      loading: _isLoading,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
