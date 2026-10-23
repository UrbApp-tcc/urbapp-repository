import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import '../services/location_service.dart';
import '../services/occurrence_service.dart';
import '../utils/error_formatter.dart';
import '../widgets/urb/urb_components.dart';

/// Estado compartilhado da sessão: cidade selecionada, posição aproximada e
/// propagação de mudanças em ocorrências entre telas.
class AppSession {
  AppSession._();

  static final AppSession instance = AppSession._();

  final ValueNotifier<CityOption?> city = ValueNotifier<CityOption?>(null);
  final ValueNotifier<GeoPoint?> position = ValueNotifier<GeoPoint?>(null);

  /// Incrementado quando uma nova ocorrência é criada; listas recarregam.
  final ValueNotifier<int> contentRevision = ValueNotifier<int>(0);
  List<CityOption> cities = const [];

  /// Perfil ainda sem cidade (ex.: primeiro acesso pelo Google): a cidade
  /// exibida é provisória até o usuário escolher a dele.
  bool needsProfileCity = false;

  final _occurrenceChanges = StreamController<Occurrence>.broadcast();
  Stream<Occurrence> get occurrenceChanges => _occurrenceChanges.stream;

  final _service = OccurrenceService();
  final _location = const LocationService();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      cities = await _service.fetchCities();
      final userId = Supabase.instance.client.auth.currentUser?.id;
      int? profileCityId;
      if (userId != null) {
        final row = await Supabase.instance.client.from('profiles').select('city_id').eq('id', userId).maybeSingle();
        profileCityId = (row?['city_id'] as num?)?.toInt();
      }
      needsProfileCity = userId != null && profileCityId == null;
      city.value = cities.where((item) => item.id == profileCityId).firstOrNull ?? cities.firstOrNull;
    } catch (_) {
      _initialized = false;
    }
    unawaited(_location.lastKnownPosition().then((value) {
      if (value != null) position.value = value;
    }));
  }

  void reset() {
    _initialized = false;
    needsProfileCity = false;
    city.value = null;
    position.value = null;
    cities = const [];
  }

  /// Grava a cidade escolhida no perfil e passa a usá-la na sessão.
  Future<void> saveProfileCity(CityOption option) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    await client.from('profiles').update({'city_id': option.id}).eq('id', userId);
    needsProfileCity = false;
    city.value = option;
  }

  Future<GeoPoint?> requestPosition() async {
    try {
      final value = await _location.currentPosition();
      position.value = value;
      return value;
    } catch (_) {
      return null;
    }
  }

  double? distanceTo(Occurrence occurrence) {
    final from = position.value;
    if (from == null) return null;
    return _location.distanceKm(from, occurrence.latitude, occurrence.longitude);
  }

  void publish(Occurrence occurrence) => _occurrenceChanges.add(occurrence);

  /// Apoio otimista; o backend valida elegibilidade (não apoia o próprio relato).
  Future<Occurrence> toggleSupport(BuildContext context, Occurrence occurrence) async {
    if (occurrence.contributedByMe && !occurrence.supportedByMe) {
      showUrbToast(context, 'Você já contribuiu com esta ocorrência por meio de um relato.');
      return occurrence;
    }
    if (occurrence.status.isFinal && !occurrence.supportedByMe) {
      showUrbToast(context, 'Ocorrências finalizadas não recebem novos apoios.');
      return occurrence;
    }
    final next = occurrence.copyWith(
      supportedByMe: !occurrence.supportedByMe,
      supportsCount: occurrence.supportsCount + (occurrence.supportedByMe ? -1 : 1),
    );
    publish(next);
    try {
      await _service.setSupport(occurrence.id, next.supportedByMe);
      return next;
    } catch (error) {
      publish(occurrence);
      if (context.mounted) showUrbToast(context, friendlyError(error));
      return occurrence;
    }
  }

  Future<Occurrence> toggleFollow(BuildContext context, Occurrence occurrence) async {
    final next = occurrence.copyWith(followedByMe: !occurrence.followedByMe);
    publish(next);
    try {
      await _service.setFollowing(occurrence.id, next.followedByMe);
      if (context.mounted) {
        showUrbToast(context, next.followedByMe ? 'Você receberá alertas desta ocorrência' : 'Você deixou de seguir');
      }
      return next;
    } catch (error) {
      publish(occurrence);
      if (context.mounted) showUrbToast(context, friendlyError(error));
      return occurrence;
    }
  }

  Future<void> share(BuildContext context, Occurrence occurrence) async {
    await Clipboard.setData(ClipboardData(
      text: 'Acompanhe esta ocorrência no UrbApp: ${occurrence.title} urbapp://occurrences/${occurrence.id}',
    ));
    if (context.mounted) showUrbToast(context, 'Link da ocorrência copiado');
  }
}

/// Mantém uma lista local sincronizada com mudanças publicadas por outras telas.
mixin OccurrenceListSync<T extends StatefulWidget> on State<T> {
  StreamSubscription<Occurrence>? _occurrenceSubscription;

  void onOccurrenceChanged(Occurrence occurrence);

  @override
  void initState() {
    super.initState();
    _occurrenceSubscription = AppSession.instance.occurrenceChanges.listen((occurrence) {
      if (mounted) onOccurrenceChanged(occurrence);
    });
  }

  @override
  void dispose() {
    _occurrenceSubscription?.cancel();
    super.dispose();
  }

  List<Occurrence> replaceIn(List<Occurrence> items, Occurrence updated) =>
      [for (final item in items) item.id == updated.id ? updated : item];
}
