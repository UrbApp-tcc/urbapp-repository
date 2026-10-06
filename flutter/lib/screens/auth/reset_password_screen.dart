import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/urb_components.dart';

/// Aberta pelo link de recuperação de senha enviado por e-mail.
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
  bool _saving = false;
  bool _done = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _authService.updatePassword(_passwordController.text);
      if (mounted) setState(() => _done = true);
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: _done
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const UrbBrandMark(size: 66),
                        const SizedBox(height: 20),
                        Text('Senha atualizada', style: UrbText.h1, textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        Text(
                          'Sua nova senha já está valendo. Continue usando o UrbApp normalmente.',
                          style: UrbText.body,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        UrbPrimaryButton(
                          label: 'Entrar com a nova senha',
                          onPressed: () => _authService.signOut(),
                        ),
                      ],
                    )
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Align(alignment: Alignment.centerLeft, child: UrbBrand(compact: true)),
                          const SizedBox(height: 32),
                          const UrbEyebrow('Conta e segurança'),
                          const SizedBox(height: 10),
                          Text('Crie uma nova senha', style: UrbText.h1),
                          const SizedBox(height: 24),
                          UrbTextField(
                            label: 'Nova senha',
                            controller: _passwordController,
                            obscure: true,
                            hint: 'Mínimo de 8 caracteres',
                            validator: (value) => (value?.length ?? 0) < 8 ? 'Mínimo de 8 caracteres' : null,
                          ),
                          const SizedBox(height: 18),
                          UrbTextField(
                            label: 'Confirmar senha',
                            controller: _confirmController,
                            obscure: true,
                            validator: (value) =>
                                value == _passwordController.text ? null : 'As senhas não conferem',
                          ),
                          const SizedBox(height: 24),
                          UrbPrimaryButton(label: 'Salvar nova senha', loading: _saving, onPressed: _save),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
