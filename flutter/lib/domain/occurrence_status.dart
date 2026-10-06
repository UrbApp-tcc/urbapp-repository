import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Estados globais oficiais da ocorrência (spec §31).
///
/// O banco usa códigos estáveis em inglês no enum `report_status`; o
/// mapeamento é 1:1 com os estados da especificação:
/// open → ABERTO, in_analysis → EM_ANALISE, in_progress → EM_ANDAMENTO,
/// awaiting_validation → AGUARDANDO_VALIDACAO, completed → RESOLVIDO,
/// reopened → REABERTO, closed → ENCERRADO.
enum OccurrenceStatus {
  open('open', 'Aberto'),
  inAnalysis('in_analysis', 'Em análise'),
  inProgress('in_progress', 'Em andamento'),
  awaitingValidation('awaiting_validation', 'Aguardando validação'),
  resolved('completed', 'Resolvido'),
  reopened('reopened', 'Reaberto'),
  closed('closed', 'Encerrado');

  const OccurrenceStatus(this.code, this.label);

  final String code;
  final String label;

  static OccurrenceStatus fromCode(String? code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return OccurrenceStatus.open;
  }

  /// Etapas exibidas na trilha "Onde está no ciclo" do detalhe.
  static const lifecycle = [
    open,
    inAnalysis,
    inProgress,
    awaitingValidation,
    resolved,
  ];

  bool get isFinal => this == resolved || this == closed;

  /// Estados a partir dos quais alguém pode informar possível resolução.
  bool get acceptsResolutionReport =>
      this == open ||
      this == inAnalysis ||
      this == inProgress ||
      this == reopened;

  bool get acceptsInteraction => this != closed;

  int get lifecycleIndex => switch (this) {
    open || reopened => 0,
    inAnalysis => 1,
    inProgress => 2,
    awaitingValidation => 3,
    resolved => 4,
    closed => -1,
  };

  /// Selo neutro para todos os estados; só "Resolvido" ganha cor (verde), por
  /// ser a única conclusão boa e confirmada pela comunidade.
  Color get foreground =>
      this == resolved ? UrbColors.success : const Color(0xFF26364D);

  Color get background =>
      this == resolved ? UrbColors.successSoft : const Color(0xFFEEF0F4);
}
