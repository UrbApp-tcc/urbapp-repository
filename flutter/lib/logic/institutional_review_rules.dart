// Regras da verificação institucional (spec §19, §40). O backend repete cada
// uma em `review_*_profile_request`; aqui servem para orientar a decisão antes
// do envio.

/// Mínimo de caracteres do motivo de rejeição. Deve coincidir com
/// `assert_institutional_review_allowed()` no SQL.
const int minRejectionReasonLength = 10;

/// Mensagem de erro para o motivo de rejeição, ou nulo quando é válido.
String? validateRejectionReason(String reason) {
  if (reason.trim().length < minRejectionReasonLength) {
    return 'Informe o motivo da rejeição (pelo menos $minRejectionReasonLength caracteres).';
  }
  return null;
}

/// Rótulo do tipo de pedido (`agency`, `administration` ou `councilor`).
String institutionalRequestKindLabel(String kind) => switch (kind) {
      'councilor' => 'Vereador',
      'administration' => 'Gestão municipal',
      _ => 'Órgão municipal',
    };

/// Rótulo da decisão registrada no pedido.
String institutionalRequestStatusLabel(String status) => switch (status) {
      'approved' => 'Aprovada',
      'rejected' => 'Rejeitada',
      _ => 'Em análise',
    };

/// Situação atual do perfil pedido, para o admin saber se a aprovação cria,
/// reivindica ou amplia um perfil existente.
String existingProfileLabel(String kind, String? status) {
  if (kind == 'councilor') {
    return switch (status) {
      'verified' || 'participant' => 'Já possui perfil de vereador verificado',
      'unclaimed' => 'Possui perfil de vereador não verificado',
      _ => 'Ainda não possui perfil de vereador',
    };
  }
  if (kind == 'administration') {
    return switch (status) {
      'participant' => 'A gestão já tem integrantes com acesso',
      'unclaimed' => 'Primeiro acesso à gestão vigente',
      _ => 'A cidade não tem gestão vigente cadastrada',
    };
  }
  return switch (status) {
    'verified' || 'participant' => 'Órgão já reivindicado na cidade',
    'unclaimed' => 'Perfil do órgão existe e ainda não foi reivindicado',
    _ => 'Órgão novo: será criado na aprovação',
  };
}

/// Pontos de atenção para a decisão, sem bloquear a aprovação.
List<String> institutionalReviewWarnings({
  required String institutionalEmail,
  required int previousRejections,
}) {
  final domain = institutionalEmail.split('@').last.trim().toLowerCase();
  const personalDomains = {
    'gmail.com', 'hotmail.com', 'outlook.com', 'yahoo.com', 'yahoo.com.br',
    'icloud.com', 'live.com', 'bol.com.br', 'uol.com.br', 'terra.com.br',
  };
  return [
    if (personalDomains.contains(domain)) 'O e-mail informado é de provedor pessoal, não institucional.',
    if (previousRejections > 0)
      previousRejections == 1
          ? 'Este solicitante já teve 1 pedido rejeitado.'
          : 'Este solicitante já teve $previousRejections pedidos rejeitados.',
  ];
}
