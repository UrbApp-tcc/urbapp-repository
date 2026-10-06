String friendlyError(Object error) =>
    error.toString().replaceFirst('Exception: ', '').trim();

const _accents = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
const _plain = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';

/// Remove acentos para comparar mensagens independentemente da grafia.
String _fold(String value) {
  final buffer = StringBuffer();
  for (final char in value.split('')) {
    final index = _accents.indexOf(char);
    buffer.write(index < 0 ? char : _plain[index]);
  }
  return buffer.toString();
}

/// Mensagens de regra de negócio vindas do backend ganham um texto voltado ao
/// cidadão (a comparação ignora acentos); mensagens técnicas viram o texto padrão.
String friendlyBackendMessage(String message, String fallback) {
  const known = <String, String>{
    'Usuario fora do raio permitido para validacao.':
        'Você precisa estar próximo ao local para validar esta ocorrência.',
    'Quem iniciou o ciclo nao pode votar nele.':
        'Quem informou a possível resolução não participa da contagem deste ciclo.',
    'Ciclo de validacao nao esta aberto.': 'Esta validação já foi encerrada.',
    'Aguarde o periodo de espera antes de tentar novamente.':
        'Você poderá informar uma nova possível resolução após o período de espera.',
    'A ocorrencia nao permite iniciar validacao no estado atual.':
        'Esta ocorrência não aceita uma nova validação no estado atual.',
    'Descreva a possivel resolucao.': 'Descreva o que você encontrou no local.',
    'Somente ocorrencias resolvidas podem ser reabertas.':
        'Somente ocorrências resolvidas podem ser reabertas.',
    'Reabertura exige descricao e nova evidencia.':
        'A reabertura exige uma descrição e uma nova foto.',
    'Nao e possivel adicionar relato a uma ocorrencia encerrada.':
        'Esta ocorrência não aceita novos relatos.',
    'Usuario nao representa a gestao ou o orgao responsavel.':
        'Seu perfil não representa a gestão ou o órgão responsável por esta ocorrência.',
    'Esta acao e exclusiva da gestao municipal.': 'Esta ação é exclusiva da gestão municipal.',
    'Perfil de vereador verificado e obrigatorio.':
        'É necessário um perfil de vereador verificado nesta cidade.',
    'Esta categoria exige uma foto recente para informar a resolucao.':
        'Esta categoria exige uma foto recente para informar a resolução.',
    'A evidencia informada nao foi enviada.': 'Não foi possível confirmar o envio da foto.',
    'Nao e possivel denunciar o proprio relato.': 'Não é possível denunciar o próprio relato.',
    'Nao e possivel denunciar o proprio comentario.': 'Não é possível denunciar o próprio comentário.',
    'Nao foi possivel determinar a gestao e o orgao responsavel.':
        'Não foi possível identificar o órgão responsável para esta cidade e categoria.',
    'Somente insignias conquistadas podem ficar em destaque.':
        'Somente insígnias conquistadas podem ficar em destaque.',
  };
  final trimmed = message.trim();
  final folded = _fold(trimmed);
  for (final entry in known.entries) {
    if (_fold(entry.key) == folded) return entry.value;
  }
  final lower = trimmed.toLowerCase();
  if (lower.contains('row-level security') || lower.contains('permission denied')) {
    return 'Você não tem permissão para esta ação.';
  }
  if (lower.contains('duplicate key')) return 'Esta ação já foi registrada.';
  if (lower.contains('failed host lookup') || lower.contains('socketexception')) {
    return 'Sem conexão. Verifique sua internet e tente novamente.';
  }
  const technical = ['violates', 'syntax', 'relation', 'column', 'function', 'pgrst', 'constraint', 'null value'];
  if (trimmed.isNotEmpty && trimmed.length < 160 && !technical.any(lower.contains)) {
    return trimmed;
  }
  return fallback;
}
