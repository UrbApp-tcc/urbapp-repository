import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Ações oficiais da Gestão Municipal e dos órgãos (spec §3.2, §3.3).
const institutionalActionLabels = <String, String>{
  'received': 'Recebimento confirmado',
  'priority': 'Prioridade reconhecida pela gestão municipal',
  'priority_removed': 'Prioridade retirada pela gestão municipal',
  'forwarding': 'Encaminhada ao órgão competente',
  'request': 'Providência solicitada ao órgão',
  'official_position': 'Posicionamento oficial publicado',
  'forecast': 'Previsão de atendimento informada',
  'analysis': 'Análise técnica iniciada',
  'scheduled': 'Serviço programado',
  'in_progress': 'Serviço em execução',
  'progress_update': 'Andamento atualizado',
  'executed': 'Serviço executado',
  'observation': 'Observação oficial',
  'conclusion': 'Conclusão informada',
};

/// Ações de acompanhamento de vereador (spec §3.4, §35).
const councilorActionLabels = <String, String>{
  'forwarding': 'Encaminhamento',
  'request': 'Solicitação de providência',
  'charge': 'Cobrança registrada',
  'official_letter': 'Ofício encaminhado',
  'agency_contact': 'Contato com órgão',
  'response_received': 'Retorno recebido',
  'visit': 'Visita ao local',
  'verification': 'Verificação',
  'public_update': 'Atualização pública',
  'possible_resolution': 'Possível resolução informada',
};

const councilorFollowingStatusLabels = <String, String>{
  'started': 'Acompanhamento iniciado',
  'action_registered': 'Ação registrada',
  'awaiting_response': 'Aguardando retorno',
  'resolved': 'Resolvida durante o acompanhamento',
  'ended': 'Acompanhamento encerrado',
};

Color actionDotColor(String actionType) => switch (actionType) {
      'charge' => UrbColors.orange,
      'official_letter' || 'forwarding' || 'request' || 'priority' => UrbColors.blue,
      'priority_removed' => UrbColors.muted,
      'response_received' || 'agency_contact' || 'conclusion' || 'executed' => UrbColors.green,
      'visit' || 'verification' => UrbColors.violet,
      'public_update' || 'forecast' || 'scheduled' => UrbColors.gold,
      'received' || 'analysis' || 'official_position' || 'observation' => UrbColors.blue,
      'in_progress' || 'progress_update' => UrbColors.teal,
      _ => UrbColors.blue,
    };

/// Cor do ponto de categoria, como nos chips do fluxo Relatar.
Color categoryColor(String? slug, String name) {
  final key = '${slug ?? ''} ${name.toLowerCase()}';
  if (key.contains('dren') || key.contains('alag') || key.contains('agua') || key.contains('esgot') || key.contains('sanea') || key.contains('sanitation')) {
    return UrbColors.blue;
  }
  if (key.contains('via') || key.contains('buraco') || key.contains('paviment') || key.contains('asfalt') || key.contains('obra') || key.contains('maintenance')) {
    return UrbColors.orange;
  }
  if (key.contains('ilumin') || key.contains('luz') || key.contains('poste') || key.contains('lighting')) {
    return UrbColors.gold;
  }
  if (key.contains('resid') || key.contains('lixo') || key.contains('entulho')) {
    return UrbColors.teal;
  }
  if (key.contains('limpeza') || key.contains('cleaning')) return const Color(0xFF1A8A7A);
  if (key.contains('arvor') || key.contains('arbor') || key.contains('veget') || key.contains('verde') || key.contains('poda') || key.contains('trees')) {
    return const Color(0xFF3A7D44);
  }
  if (key.contains('calcad') || key.contains('acessib') || key.contains('accessib')) return const Color(0xFF7B5EA7);
  if (key.contains('transit') || key.contains('trânsito') || key.contains('traffic') || key.contains('sinal') || key.contains('transport')) {
    return UrbColors.violet;
  }
  return UrbColors.slate;
}

String jurisdictionLabel(String code) => switch (code) {
      'state' => 'Competência estadual',
      'federal' => 'Competência federal',
      'concessionaire' => 'Concessionária',
      'private' => 'Propriedade privada',
      'unknown' => 'Competência em análise',
      _ => 'Competência municipal',
    };

/// "1 relato", "3 relatos" — contagem com concordância de número.
String plural(int count, String singular, String pluralForm) => '$count ${count == 1 ? singular : pluralForm}';

/// Só a palavra, concordando com [count] ("aberta" / "abertas").
String pluralWord(int count, String singular, String pluralForm) => count == 1 ? singular : pluralForm;

String formatCount(int value) {
  if (value < 1000) return '$value';
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 == 0) buffer.write('.');
    buffer.write(text[index]);
  }
  return buffer.toString();
}

String formatDecimal(double value, {int digits = 1}) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');

String formatDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${formatDecimal(km, digits: km < 10 ? 1 : 0)} km';
}

/// Duração legível em dias para indicadores ("8,4 dias").
String formatDays(double? seconds) {
  if (seconds == null || seconds < 0) return '—';
  if (seconds < 86400) return '< 1';
  return formatDecimal(seconds / 86400);
}
