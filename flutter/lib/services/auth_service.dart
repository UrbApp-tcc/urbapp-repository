import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService({SupabaseClient? supabase}) {
    _supabase = supabase ?? Supabase.instance.client;
    _auth = _supabase.auth;
  }

  late final SupabaseClient _supabase;
  late final GoTrueClient _auth;

  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;
  Session? get currentSession => _auth.currentSession;
  User? get currentUser => _auth.currentUser;

  Future<AuthResponse> signIn({
    required String identifier,
    required String password,
  }) async {
    final normalizedIdentifier = identifier.trim();

    try {
      if (!_isEmail(normalizedIdentifier)) {
        return await _signInWithUsername(
          username: normalizedIdentifier,
          password: password,
        );
      }

      return await _auth.signInWithPassword(
        email: normalizedIdentifier,
        password: password,
      );
    } on FunctionException catch (error) {
      throw Exception(_mapUsernameLoginError(error));
    } on AuthException catch (error) {
      throw Exception(_mapAuthError(error));
    } catch (_) {
      throw Exception('Erro inesperado ao entrar na conta.');
    }
  }

  Future<AuthResponse> _signInWithUsername({
    required String username,
    required String password,
  }) async {
    final response = await _supabase.functions.invoke(
      'username-login',
      body: {'username': username, 'password': password},
    );

    final data = response.data;
    if (data is! Map) {
      throw Exception('Resposta inválida do serviço de autenticação.');
    }

    final refreshToken = data['refresh_token'];
    if (refreshToken is! String || refreshToken.isEmpty) {
      throw Exception('Resposta inválida do serviço de autenticação.');
    }

    return _auth.setSession(refreshToken);
  }

  bool _isEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(value);
  }

  String _mapUsernameLoginError(FunctionException error) {
    if (error.status == 429) {
      return 'Muitas tentativas. Aguarde um pouco e tente novamente.';
    }

    if (error.status == 401 || error.status == 400) {
      return 'Nome de usuário ou senha inválidos.';
    }

    return 'Não foi possível entrar com o nome de usuário agora.';
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    required int cityId,
    String? phone,
  }) async {
    try {
      return await _auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: 'urbapp://login-callback',
        data: {
          'username': username.trim(),
          'full_name': username.trim(),
          'city_id': cityId,
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
      );
    } on AuthException catch (error) {
      throw Exception(_mapAuthError(error));
    } catch (_) {
      throw Exception('Erro inesperado ao criar a conta.');
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (error) {
      throw Exception(_mapAuthError(error));
    } catch (_) {
      throw Exception('Erro inesperado ao atualizar a senha.');
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: 'urbapp://login-callback',
      );
    } on AuthException catch (error) {
      throw Exception(_mapAuthError(error));
    } catch (_) {
      throw Exception('Erro inesperado ao solicitar redefinição de senha.');
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on AuthException catch (error) {
      throw Exception(_mapAuthError(error));
    } catch (_) {
      throw Exception('Erro inesperado ao sair da conta.');
    }
  }

  String _mapAuthError(AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('invalid login credentials')) {
      return 'E-mail, nome de usuário ou senha inválidos.';
    }

    if (message.contains('unregistered api key')) {
      return 'A Publishable key configurada no app não é mais válida para este projeto Supabase.';
    }

    if (message.contains('email not confirmed')) {
      return 'Confirme seu e-mail antes de entrar.';
    }

    if (message.contains('user already registered')) {
      return 'Já existe uma conta cadastrada com este e-mail.';
    }

    if (message.contains('password should be at least')) {
      return 'A senha precisa ter pelo menos 6 caracteres.';
    }

    if (message.contains('signup is disabled')) {
      return 'O cadastro de novos usuários está desabilitado no momento.';
    }

    return 'Erro de autenticação: ${error.message}';
  }
}
