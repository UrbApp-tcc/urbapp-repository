import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../services/occurrence_service.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/occurrence_widgets.dart';
import '../../widgets/urb/urb_icon.dart';

/// Vincula atividades institucionais às ocorrências citadas.
Future<List<InstitutionalActivity>> attachOccurrences(List<InstitutionalActivity> items) async {
  final occurrences = await OccurrenceService().fetchByIds(items.map((item) => item.occurrenceId));
  final byId = {for (final occurrence in occurrences) occurrence.id: occurrence};
  return [for (final item in items) item.withOccurrence(byId[item.occurrenceId])];
}

/// Linhas de "Atuação recente" / "Atualizações oficiais".
class ActivityList extends StatelessWidget {
  const ActivityList({super.key, required this.items, required this.labels, this.emptyMessage = 'Nenhuma ação registrada ainda.'});

  final List<InstitutionalActivity> items;
  final Map<String, String> labels;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Text(emptyMessage, style: UrbText.caption);
    return Column(
      children: [
        for (var index = 0; index < items.length; index++)
          UrbDotRow(
            title: labels[items[index].actionType] ?? 'Ação registrada',
            subtitle: items[index].occurrence?.title ?? items[index].description,
            note: items[index].actionType == 'conclusion' || items[index].actionType == 'possible_resolution'
                ? (items[index].occurrence?.status.name == 'resolved'
                    ? 'Confirmada pela comunidade'
                    : 'Sujeita à validação da comunidade')
                : null,
            noteColor: UrbColors.validationNote,
            trailingText: formatRelativeTime(items[index].createdAt).toLowerCase(),
            dotColor: actionDotColor(items[index].actionType),
            showChevron: false,
            last: index == items.length - 1,
            onTap: () => openOccurrence(context, occurrenceId: items[index].occurrenceId, initial: items[index].occurrence),
          ),
      ],
    );
  }
}

/// Linha de ocorrência relacionada: título, onde, e a situação como selo.
class RelatedOccurrenceRow extends StatelessWidget {
  const RelatedOccurrenceRow({super.key, required this.occurrence, this.note, this.last = false});

  final Occurrence occurrence;
  final String? note;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${occurrence.title}, ${occurrence.status.label}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => openOccurrence(context, occurrenceId: occurrence.id, initial: occurrence),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: UrbColors.divider)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      occurrence.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800, height: 1.25),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      occurrence.locationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.caption.copyWith(fontSize: 12),
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 4),
                      Text(note!, style: UrbText.caption.copyWith(color: UrbColors.textBody, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: StatusPill(occurrence.status, compact: true),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: UrbIcon(UrbIcons.chevron, size: 14, color: UrbColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
