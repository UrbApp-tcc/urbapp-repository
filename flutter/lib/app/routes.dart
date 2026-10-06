import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../screens/alerts/alerts_screen.dart';
import '../screens/occurrence/occurrence_detail_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/ranking/ranking_screen.dart';
import '../screens/report/report_flow_screen.dart';
import '../screens/transparency/administration_profile_screen.dart';
import '../screens/transparency/agency_profile_screen.dart';
import '../screens/transparency/councilor_profile_screen.dart';
import '../screens/transparency/transparency_screen.dart';
import '../screens/validation/validation_screen.dart';

Route<T> urbRoute<T>(Widget page, {bool fullscreenDialog = false}) => MaterialPageRoute<T>(
      builder: (_) => page,
      fullscreenDialog: fullscreenDialog,
    );

enum DetailAnchor { top, reports, comments }

Future<void> openOccurrence(
  BuildContext context, {
  required int occurrenceId,
  Occurrence? initial,
  DetailAnchor anchor = DetailAnchor.top,
}) {
  return Navigator.of(context).push(urbRoute(
    OccurrenceDetailScreen(occurrenceId: occurrenceId, initial: initial, anchor: anchor),
  ));
}

Future<void> openValidation(BuildContext context, Occurrence occurrence) {
  return Navigator.of(context).push(urbRoute(ValidationScreen(occurrence: occurrence)));
}

Future<void> openAlerts(BuildContext context) {
  return Navigator.of(context).push(urbRoute(const AlertsScreen(), fullscreenDialog: true));
}

/// Abre o fluxo Relatar; opcionalmente já vinculado a uma ocorrência existente.
Future<ReportSubmission?> openReportFlow(BuildContext context, {Occurrence? existing}) {
  return Navigator.of(context).push<ReportSubmission>(
    urbRoute(ReportFlowScreen(existingOccurrence: existing), fullscreenDialog: true),
  );
}

Future<void> openAgency(BuildContext context, int agencyId) {
  return Navigator.of(context).push(urbRoute(AgencyProfileScreen(agencyId: agencyId)));
}

Future<void> openCouncilor(BuildContext context, int councilorProfileId) {
  return Navigator.of(context).push(urbRoute(CouncilorProfileScreen(councilorProfileId: councilorProfileId)));
}

Future<void> openAdministration(BuildContext context, {int? administrationId, int? cityId}) {
  return Navigator.of(context).push(urbRoute(
    AdministrationProfileScreen(administrationId: administrationId, cityId: cityId),
  ));
}

Future<void> openUserProfile(BuildContext context, String profileId) {
  return Navigator.of(context).push(urbRoute(ProfileScreen(profileId: profileId)));
}

/// Visão pública de uma cidade: a mesma Transparência da aba principal,
/// contextualizada para [cityId] e aberta como página (com voltar).
Future<void> openCityTransparency(BuildContext context, int cityId) {
  return Navigator.of(context).push(urbRoute(TransparencyScreen(cityId: cityId)));
}

/// Rankings: página principal com Cidades e Cidadãos lado a lado.
Future<void> openRankings(BuildContext context) {
  return Navigator.of(context).push(urbRoute(const RankingsScreen()));
}

/// Comparativo completo de cidades.
Future<void> openCityRanking(BuildContext context) {
  return Navigator.of(context).push(urbRoute(const CityRankingScreen()));
}

/// Ranking completo de cidadãos.
Future<void> openCitizenRanking(BuildContext context) {
  return Navigator.of(context).push(urbRoute(const CitizenRankingScreen()));
}
