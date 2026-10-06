import 'package:flutter/material.dart';

import '../../app/institutional_intent.dart';
import '../../domain/models.dart';
import '../../services/auth_service.dart';
import '../../services/occurrence_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/city_picker.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.institutionalKind});

  /// Quando presente, a conta nasce com a intenção de solicitar esse papel.
  final InstitutionalKind? institutionalKind;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _authService = AuthService();

  List<CityOption> _cities = const [];
  CityOption? _city;
  bool _loadingCities = true;
  bool _submitting = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadCities() async {
    try {
      final cities = await OccurrenceService().fetchCities();
      if (mounted) setState(() => _cities = cities);
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_city == null) {
      showUrbToast(context, 'Selecione a sua cidade para continuar.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      final response = await _authService.signUp(
        email: _emailController.text,
        password: _passwordController.text,
        username: _usernameController.text,
        cityId: _city!.id,
        phone: _phoneController.text,
        institutionalIntent: widget.institutionalKind?.code,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      final institutional = widget.institutionalKind != null;
      messenger.showSnackBar(SnackBar(
        content: Text(
          response.session == null
              ? (institutional
                  ? 'Conta criada. Confirme seu e-mail e entre para enviar a comprovação institucional.'
                  : 'Conta criada. Confirme seu e-mail para entrar.')
              : 'Conta criada com sucesso!',
        ),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      ));
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final institutional = widget.institutionalKind != null;
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: UrbSubscreenHeader(title: institutional ? 'Conta institucional' : 'Criar conta'),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      UrbEyebrow(
                        institutional ? 'Conta institucional · ${widget.institutionalKind!.label}' : 'Participe da sua cidade',
                      ),
                      const SizedBox(height: 10),
                      Text('Crie sua conta', style: UrbText.h1),
                      const SizedBox(height: 8),
                      Text(
                        institutional
                            ? 'Use de preferência seu e-mail institucional. Depois de entrar, você envia a comprovação '
                                'do vínculo para a equipe do UrbApp.'
                            : 'Relate problemas, apoie demandas e ajude a confirmar o que foi resolvido.',
                        style: UrbText.body,
                      ),
                      const SizedBox(height: 26),
                      UrbTextField(
                        label: 'Nome de usuário',
                        controller: _usernameController,
                        hint: 'ex.: maria.silva',
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newUsername],
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.length < 3) return 'Use pelo menos 3 caracteres';
                          if (text.length > 48) return 'Use no máximo 48 caracteres';
                          if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(text)) {
                            return 'Use apenas letras, números, pontos e _';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      UrbTextField(
                        label: institutional ? 'E-mail institucional' : 'E-mail',
                        controller: _emailController,
                        hint: 'seuemail@exemplo.com',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        validator: (value) => RegExp(r'^[\w.+-]+@[\w.-]+\.\w{2,}$').hasMatch(value?.trim() ?? '')
                            ? null
                            : 'Informe um e-mail válido',
                      ),
                      const SizedBox(height: 18),
                      UrbTextField(
                        label: 'Senha',
                        controller: _passwordController,
                        hint: 'Mínimo de 8 caracteres',
                        obscure: !_showPassword,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        validator: (value) => (value?.length ?? 0) < 8 ? 'Mínimo de 8 caracteres' : null,
                        suffix: IconButton(
                          tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                          icon: UrbIcon(_showPassword ? UrbIcons.eye : UrbIcons.eyeOff, size: 19, color: UrbColors.muted),
                        ),
                      ),
                      const SizedBox(height: 18),
                      UrbTextField(
                        label: 'Celular (opcional)',
                        controller: _phoneController,
                        hint: '(00) 00000-0000',
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                      ),
                      const SizedBox(height: 18),
                      Text('Cidade', style: UrbText.label),
                      const SizedBox(height: 8),
                      CitySelectorButton(
                        city: _city,
                        label: _loadingCities
                            ? 'Carregando cidades…'
                            : (institutional ? 'Cidade onde você atua' : 'Onde você mora'),
                        onTap: () async {
                          if (_cities.isEmpty) return;
                          final picked = await showCityPicker(context, cities: _cities, selected: _city);
                          if (picked != null) setState(() => _city = picked);
                        },
                      ),
                      const SizedBox(height: 26),
                      UrbPrimaryButton(label: 'Criar conta', loading: _submitting, onPressed: _submit),
                      const SizedBox(height: 14),
                      Text(
                        'Ao criar sua conta você concorda com os Termos de uso e a Política de privacidade do UrbApp.',
                        textAlign: TextAlign.center,
                        style: UrbText.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
