import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../theme/urbapp_design.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/urb_dialog.dart';
import '../../widgets/urb_hero.dart';
import '../../widgets/urb_primary_button.dart';
import '../../widgets/urb_text_field.dart';

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

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty)
      return 'Informe o nome de usuário';
    if (value.trim().length < 3) return 'Use pelo menos 3 caracteres';
    if (value.trim().length > 48) return 'Use no máximo 48 caracteres';
    if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(value.trim())) {
      return 'Use apenas letras, números, pontos e _';
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
      showUrbSnack(context, friendlyError(error), error: true);
    }
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCityId == null) {
      showUrbSnack(
        context,
        'Selecione uma cidade para continuar.',
        error: true,
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
        Navigator.of(
          context,
        ).pop('Conta criada. Confirme seu e-mail para entrar.');
        return;
      }

      Navigator.of(context).pop('Conta criada com sucesso!');
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
      onBack: () => Navigator.of(context).maybePop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FadeSlideIn(
            offsetY: 12,
            child: UrbAuthTitle(
              title: 'Faça parte da sua cidade',
              subtitle: 'Crie sua conta para reportar e acompanhar problemas.',
            ),
          ),
          const SizedBox(height: 32),
          FadeSlideIn(
            delay: const Duration(milliseconds: 120),
            child: UrbCard(child: _buildForm()),
          ),
          const SizedBox(height: 20),
          UrbAuthFooterLink(
            text: 'Já tem uma conta?',
            action: 'Entrar',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UrbTextField(
            label: 'Nome de usuário',
            controller: _usernameController,
            icon: Icons.alternate_email_rounded,
            hintText: 'seu.usuario',
            helperText: 'Use letras, números, pontos e _',
            validator: _validateUsername,
            autofillHints: const [AutofillHints.newUsername],
          ),
          const SizedBox(height: 22),
          UrbTextField(
            label: 'E-mail',
            controller: _emailController,
            icon: Icons.mail_outline_rounded,
            hintText: 'seu@email.com',
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: 22),
          UrbTextField(
            label: 'Celular (opcional)',
            controller: _mobileController,
            icon: Icons.phone_iphone_rounded,
            hintText: '(15) 90000-0000',
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
          ),
          const SizedBox(height: 22),
          _buildCityField(),
          const SizedBox(height: 22),
          UrbTextField(
            label: 'Senha',
            controller: _passwordController,
            icon: Icons.lock_outline_rounded,
            hintText: 'Mínimo de 8 caracteres',
            validator: _validatePassword,
            obscureText: !_isPasswordVisible,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _createAccount(),
            autofillHints: const [AutofillHints.newPassword],
            suffix: PasswordVisibilityToggle(
              visible: _isPasswordVisible,
              onPressed: () =>
                  setState(() => _isPasswordVisible = !_isPasswordVisible),
            ),
          ),
          const SizedBox(height: 30),
          UrbPrimaryButton(
            label: 'Criar conta',
            loading: _isLoading,
            onPressed: (_isCitiesLoading || _cities.isEmpty)
                ? null
                : _createAccount,
          ),
        ],
      ),
    );
  }

  Widget _buildCityField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Cidade',
          style: UrbText.body(
            size: 13,
            weight: FontWeight.w700,
            color: const Color(0xFF374151),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          initialValue: _selectedCityId,
          isExpanded: true,
          alignment: Alignment.center,
          borderRadius: BorderRadius.circular(16),
          icon: const Icon(
            Icons.expand_more_rounded,
            color: UrbColors.textMuted,
          ),
          style: UrbText.body(size: 15, color: UrbColors.ink, height: 1.3),
          items: _cities
              .map(
                (city) => DropdownMenuItem<int>(
                  value: city.id,
                  alignment: Alignment.center,
                  child: Text(city.name),
                ),
              )
              .toList(),
          onChanged: _isCitiesLoading
              ? null
              : (value) => setState(() => _selectedCityId = value),
          validator: (value) => value == null ? 'Selecione a sua cidade' : null,
          decoration: urbInputDecoration(
            hintText: _isCitiesLoading
                ? 'Carregando cidades...'
                : 'Selecione a sua cidade',
            icon: Icons.location_on_outlined,
            suffix: const SizedBox(width: 0),
          ),
        ),
      ],
    );
  }
}
