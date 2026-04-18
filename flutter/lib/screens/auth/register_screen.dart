import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/auth_text_field.dart';
import '../../widgets/gradient_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _authService = AuthService();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

  static const double _maxContentWidth = 400;
  static const double _spacingLogoTitle = 16;
  static const double _spacingTitleForm = 24;
  static const double _spacingBetweenFields = 16;
  static const double _spacingFormButton = 24;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) return 'Informe o nome de usuário';
    if (value.trim().length < 3) return 'Use pelo menos 3 caracteres';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Informe uma senha';
    if (value.length < 8) return 'Mínimo de 8 caracteres';
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Informe o e-mail';

    final regex = RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$');
    if (!regex.hasMatch(value.trim())) return 'E-mail inválido';

    return null;
  }

  String? _validateMobile(String? value) {
    if (value == null || value.trim().isEmpty) return 'Informe o celular';
    return null;
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final response = await _authService.signUp(
        email: _emailController.text,
        password: _passwordController.text,
        username: _usernameController.text,
        phone: _mobileController.text,
      );

      if (!mounted) return;

      if (response.session == null) {
        Navigator.of(context).pop('Conta criada. Confirme seu e-mail para entrar.');
        return;
      }

      Navigator.of(context).pop('Conta criada com sucesso!');
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
                      _buildDecorativeShapes(),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: _buildContent(),
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

  Widget _buildDecorativeShapes() {
    return SizedBox(
      height: 120,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.gradientViolet.withValues(alpha: 0.5),
                    AppColors.gradientBlue.withValues(alpha: 0.4),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    AppColors.gradientViolet.withValues(alpha: 0.4),
                    AppColors.accentPurple.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppLogo(height: 115),
          const SizedBox(height: _spacingLogoTitle),
          const Text(
            'Criar conta',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: _spacingTitleForm),
          AuthTextField(
            controller: _usernameController,
            validator: _validateUsername,
            hintText: 'Nome de usuário',
            prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.textSecondary, size: 22),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: _spacingBetweenFields),
          AuthTextField(
            controller: _passwordController,
            validator: _validatePassword,
            hintText: 'Senha',
            obscureText: !_isPasswordVisible,
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.textSecondary, size: 22),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
              icon: Icon(
                _isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.textSecondary,
                size: 22,
              ),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: _spacingBetweenFields),
          AuthTextField(
            controller: _emailController,
            validator: _validateEmail,
            hintText: 'E-mail',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.email_outlined, color: AppColors.textSecondary, size: 22),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: _spacingBetweenFields),
          AuthTextField(
            controller: _mobileController,
            validator: _validateMobile,
            hintText: 'Celular',
            keyboardType: TextInputType.phone,
            prefixIcon: const Icon(Icons.phone_android_rounded, color: AppColors.textSecondary, size: 22),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _createAccount(),
          ),
          const SizedBox(height: _spacingFormButton),
          GradientButton(
            label: 'Criar conta',
            loading: _isLoading,
            onPressed: _createAccount,
          ),
          const SizedBox(height: 24),
          const Text(
            'Ou crie uma conta com redes sociais',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textHint, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSocialButton(const Color(0xFF1877F2), Icons.facebook_rounded),
              const SizedBox(width: 20),
              _buildSocialButton(const Color(0xFF1DA1F2), Icons.alternate_email_rounded),
              const SizedBox(width: 20),
              _buildSocialButton(Colors.white, Icons.g_mobiledata_rounded, isGoogle: true),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                children: [
                  const TextSpan(text: 'Já tem uma conta? '),
                  TextSpan(
                    text: 'Entrar',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()..onTap = () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton(Color bgColor, IconData icon, {bool isGoogle = false}) {
    return Material(
      color: bgColor,
      shape: const CircleBorder(),
      elevation: 1,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: () {},
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isGoogle ? Border.all(color: AppColors.border) : null,
          ),
          child: Icon(
            icon,
            color: isGoogle ? AppColors.textPrimary : Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }
}
