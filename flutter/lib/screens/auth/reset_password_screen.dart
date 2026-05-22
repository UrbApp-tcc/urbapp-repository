import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/auth_text_field.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/wave_header.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Senha atualizada com sucesso!'),
          backgroundColor: AppColors.resolved,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minHeight = MediaQuery.of(context).size.height -
                MediaQuery.paddingOf(context).top -
                MediaQuery.paddingOf(context).bottom;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const WaveHeader(height: 180),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const AppLogo(height: 115),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Nova senha',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Escolha uma senha forte para a sua conta',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 32),
                                    AuthTextField(
                                      controller: _passwordController,
                                      validator: _validatePassword,
                                      hintText: 'Nova senha',
                                      obscureText: !_isPasswordVisible,
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                        color: AppColors.textSecondary,
                                        size: 22,
                                      ),
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(
                                          () => _isPasswordVisible = !_isPasswordVisible,
                                        ),
                                        icon: Icon(
                                          _isPasswordVisible
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: AppColors.textSecondary,
                                          size: 22,
                                        ),
                                      ),
                                      textInputAction: TextInputAction.next,
                                    ),
                                    const SizedBox(height: 16),
                                    AuthTextField(
                                      controller: _confirmController,
                                      validator: _validateConfirm,
                                      hintText: 'Confirmar nova senha',
                                      obscureText: !_isConfirmVisible,
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                        color: AppColors.textSecondary,
                                        size: 22,
                                      ),
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(
                                          () => _isConfirmVisible = !_isConfirmVisible,
                                        ),
                                        icon: Icon(
                                          _isConfirmVisible
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: AppColors.textSecondary,
                                          size: 22,
                                        ),
                                      ),
                                      textInputAction: TextInputAction.done,
                                      onFieldSubmitted: (_) => _submit(),
                                    ),
                                    const SizedBox(height: 24),
                                    GradientButton(
                                      label: 'Salvar nova senha',
                                      loading: _isLoading,
                                      onPressed: _submit,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
