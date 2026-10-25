import '../services/institutional_service.dart';
import '../services/occurrence_service.dart';
import 'administration_workspace_rules.dart';

Future<List<AdministrationDemandItem>> loadAdministrationDemandItems(
  int administrationId, {
  int limit = 100,
}) async {
  final occurrences = await OccurrenceService().fetchByAdministration(
    administrationId,
    limit: limit,
  );
  final contexts = await InstitutionalService()
      .fetchAdministrationOccurrenceContexts(
        administrationId,
        occurrences.map((item) => item.id),
      );
  return [
    for (final occurrence in occurrences)
      AdministrationDemandItem(
        occurrence: occurrence,
        context:
            contexts[occurrence.id] ?? const AdministrationOccurrenceContext(),
      ),
  ];
}
