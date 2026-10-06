import 'package:supabase_flutter/supabase_flutter.dart';

/// Papéis institucionais que podem ser solicitados (spec §3.3–3.5).
enum InstitutionalKind {
  councilor(
    'councilor',
    'Vereador(a)',
    'Sou vereador(a)',
    'Acompanhar demandas, registrar encaminhamentos, cobranças e retornos.',
  ),
  agency(
    'agency',
    'Órgão municipal',
    'Represento um órgão municipal',
    'Confirmar recebimento, publicar andamento e informar conclusão.',
  ),
  administration(
    'administration',
    'Gestão municipal',
    'Represento a gestão municipal',
    'Priorizar, encaminhar ao órgão competente e publicar manifestações.',
  );

  const InstitutionalKind(this.code, this.label, this.choice, this.description);

  final String code;
  final String label;
  final String choice;
  final String description;

  static InstitutionalKind? fromCode(String? code) =>
      InstitutionalKind.values.where((kind) => kind.code == code).firstOrNull;
}

/// Intenção de solicitar um perfil institucional escolhida antes do login.
///
/// No cadastro ela vai para os metadados da conta (`institutional_intent`), o
/// que funciona mesmo quando a confirmação de e-mail adia o primeiro acesso.
/// Para quem já tem conta, fica em memória até o login.
class InstitutionalIntent {
  InstitutionalIntent._();

  static const metadataKey = 'institutional_intent';

  static InstitutionalKind? pending;

  /// Lê e limpa a intenção pendente da sessão atual.
  static Future<InstitutionalKind?> consume() async {
    final auth = Supabase.instance.client.auth;
    final stored = auth.currentUser?.userMetadata?[metadataKey] as String?;
    final kind = pending ?? InstitutionalKind.fromCode(stored);
    pending = null;
    if (stored != null) {
      try {
        await auth.updateUser(UserAttributes(data: {metadataKey: null}));
      } catch (_) {
        // Se a limpeza falhar, a solicitação continua disponível no Perfil.
      }
    }
    return kind;
  }
}
