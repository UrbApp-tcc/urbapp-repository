import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
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
  final _profileService = ProfileService();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _isCitiesLoading = true;
  List<ProfileCityOption> _cities = const [];
  int? _selectedCityId;

  static const double _maxContentWidth = 400;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) return 'Informe o nome de usuário';
    if (value.trim().length < 3) return 'Use pelo menos 3 caracteres';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value.trim())) {
      return 'Use apenas letras, números e _';
    }
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

  String? _validateMobile(String? value) => null;

  Future<void> _loadCities() async {
    try {
      final cities = await _profileService.fetchCities();
      if (!mounted) return;
      setState(() {
        _cities = cities;
        _selectedCityId = cities.isNotEmpty ? cities.first.id : null;
        _isCitiesLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isCitiesLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Selecione uma cidade para continuar.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final response = await _authService.signUp(
        email: _emailController.text,
        password: _passwordController.text,
        username: _usernameController.text,
        cityId: _selectedCityId!,
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
          content: Text(friendlyError(error)),
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
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final availableHeight = size.height - padding.top - padding.bottom;
    final isCompact = availableHeight < 750;

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: availableHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  _buildDecorativeShapes(isCompact: isCompact),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _buildContent(isCompact: isCompact),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDecorativeShapes({required bool isCompact}) {
    final headerHeight = isCompact ? 80.0 : 110.0;
    return SizedBox(
      height: headerHeight,
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

  Widget _buildContent({required bool isCompact}) {
    final logoHeight = isCompact ? 70.0 : 100.0;
    final spacingLogoTitle = isCompact ? 10.0 : 16.0;
    final spacingTitleForm = isCompact ? 14.0 : 24.0;
    final spacingFields = isCompact ? 10.0 : 16.0;
    final spacingFormButton = isCompact ? 16.0 : 24.0;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppLogo(height: logoHeight),
          SizedBox(height: spacingLogoTitle),
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
          SizedBox(height: spacingTitleForm),
          AuthTextField(
            controller: _usernameController,
            validator: _validateUsername,
            hintText: 'Nome de usuário',
            prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.textSecondary, size: 22),
            textInputAction: TextInputAction.next,
          ),
          SizedBox(height: spacingFields),
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
          SizedBox(height: spacingFields),
          AuthTextField(
            controller: _emailController,
            validator: _validateEmail,
            hintText: 'E-mail',
            keyboardType: TextInputType.emailAddress,
            prefixIcon: const Icon(Icons.email_outlined, color: AppColors.textSecondary, size: 22),
            textInputAction: TextInputAction.next,
          ),
          SizedBox(height: spacingFields),
          AuthTextField(
            controller: _mobileController,
            validator: _validateMobile,
            hintText: 'Celular',
            keyboardType: TextInputType.phone,
            prefixIcon: const Icon(Icons.phone_android_rounded, color: AppColors.textSecondary, size: 22),
            textInputAction: TextInputAction.done,
          ),
          SizedBox(height: spacingFields),
          DropdownButtonFormField<int>(
            initialValue: _selectedCityId,
            items: _cities
                .map(
                  (city) => DropdownMenuItem<int>(
                    value: city.id,
                    child: Text(city.name),
                  ),
                )
                .toList(),
            onChanged: _isCitiesLoading
                ? null
                : (value) => setState(() => _selectedCityId = value),
            validator: (value) => value == null ? 'Selecione a sua cidade' : null,
            decoration: InputDecoration(
              labelText: 'Cidade',
              hintText: _isCitiesLoading ? 'Carregando cidades...' : 'Selecione a sua cidade',
              prefixIcon: const Icon(
                Icons.location_city_outlined,
                color: AppColors.textSecondary,
                size: 22,
              ),
            ),
          ),
          SizedBox(height: spacingFormButton),
          GradientButton(
            label: 'Criar conta',
            loading: _isLoading || _isCitiesLoading,
            onPressed: (_isCitiesLoading || _cities.isEmpty) ? null : _createAccount,
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
}
