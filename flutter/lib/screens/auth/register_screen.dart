import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/auth_text_field.dart';
import '../../widgets/gradient_button.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _senhaController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();

  bool _senhaVisivel = false;
  bool _carregando = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _senhaController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  String? _validarUsername(String? value) {
    if (value == null || value.trim().isEmpty) return 'Informe o nome de usuário';
    return null;
  }

  String? _validarSenha(String? value) {
    if (value == null || value.isEmpty) return 'Informe uma senha';
    if (value.length < 8) return 'Mínimo 8 caracteres';
    return null;
  }

  String? _validarEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Informe o e-mail';
    final regex = RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$');
    if (!regex.hasMatch(value.trim())) return 'E-mail inválido';
    return null;
  }

  String? _validarMobile(String? value) {
    if (value == null || value.trim().isEmpty) return 'Informe o celular';
    return null;
  }

  Future<void> _criarConta() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _carregando = true);
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Conta criada com sucesso! Bem-vindo ao UrbApp 🎉'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  static const double _maxContentWidth = 400;
  static const double _spacingLogoTitle = 16;
  static const double _spacingTitleForm = 24;
  static const double _spacingBetweenFields = 16;
  static const double _spacingFormButton = 24;

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
                              child: _buildConteudo(),
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

  Widget _buildConteudo() {
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
            'Create account',
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
            validator: _validarUsername,
            hintText: 'Username',
            prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.textSecondary, size: 22),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: _spacingBetweenFields),
          AuthTextField(
            controller: _senhaController,
            validator: _validarSenha,
            hintText: 'Password',
            obscureText: !_senhaVisivel,
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.textSecondary, size: 22),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
              icon: Icon(
                _senhaVisivel ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.textSecondary,
                size: 22,
              ),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: _spacingBetweenFields),
          AuthTextField(
            controller: _emailController,
            validator: _validarEmail,
            hintText: 'E-mail',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.email_outlined, color: AppColors.textSecondary, size: 22),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: _spacingBetweenFields),
          AuthTextField(
            controller: _mobileController,
            validator: _validarMobile,
            hintText: 'Mobile',
            keyboardType: TextInputType.phone,
            prefixIcon: const Icon(Icons.phone_android_rounded, color: AppColors.textSecondary, size: 22),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: _spacingFormButton),
          GradientButton(
            label: 'Create',
            loading: _carregando,
            onPressed: _criarConta,
          ),
          const SizedBox(height: 24),
          const Text(
            'Or create account using social media',
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
                  const TextSpan(text: 'Already have an account? '),
                  TextSpan(
                    text: 'Sign in',
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
