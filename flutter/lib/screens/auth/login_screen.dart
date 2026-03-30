import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/auth_text_field.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/wave_header.dart';
import 'register_screen.dart';
import '../../services/post_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _senhaController = TextEditingController();

  bool _senhaVisivel = false;
  bool _carregando = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  String? _validarUsername(String? value) {
    if (value == null || value.trim().isEmpty) return 'Informe seu nome de usuário';
    return null;
  }

  String? _validarSenha(String? value) {
    if (value == null || value.isEmpty) return 'Informe sua senha';
    if (value.length < 6) return 'Senha muito curta';
    return null;
  }

  Future<void> _entrar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _carregando = true);
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Login realizado com sucesso!'),
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
        child: Stack(
          children: [
            LayoutBuilder(
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
            _buildWaveInferior(),
          ],
        ),
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
            'Hello',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sign in to your account',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
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
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _entrar(),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textHint,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Forgot your password?', style: TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(height: _spacingFormButton),
          GradientButton(
            label: 'Sign in',
            loading: _carregando,
            onPressed: _entrar,
          ),
          // REMOVER DEPOIS -----------------------------------------
          ElevatedButton(
            onPressed: () async {
              try {
                await PostService().createPost(
                  userId: 1, // pode ser qualquer string por enquanto
                  cityId: 1,
                  categoryId: 1,
                  title: 'Post de teste',
                  description: 'Esse é um post de teste',
                  latitude: -23.5,
                  longitude: -47.4,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Post criado com sucesso!')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erro: $e')),
                );
              }
            },
            child: const Text('Testar criação de post'),
          ),
          // REMOVER DEPOIS -----------------------------------------
          const SizedBox(height: 28),
          Center(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                children: [
                  const TextSpan(text: "Don't have an account? "),
                  TextSpan(
                    text: 'Create',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RegisterScreen()),
                        );
                      },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveInferior() {
    return Positioned(
      left: -40,
      bottom: -20,
      child: CustomPaint(
        size: const Size(180, 120),
        painter: _WaveInferiorPainter(),
      ),
    );
  }
}

class _WaveInferiorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.4)
      ..quadraticBezierTo(size.width * 0.3, 0, size.width * 0.6, size.height * 0.35)
      ..quadraticBezierTo(size.width, size.height * 0.7, size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final paint = Paint()
      ..color = AppColors.accentPurple.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
