import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../domain/models.dart';

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class ResolvedAddress {
  const ResolvedAddress({this.street, this.neighborhood, this.city, this.stateCode});

  final String? street;
  final String? neighborhood;
  final String? city;
  final String? stateCode;

  String get label {
    final parts = [street ?? neighborhood, city].whereType<String>().where((part) => part.isNotEmpty);
    return parts.isEmpty ? 'Local aproximado' : parts.join(', ');
  }
}

/// Localização do dispositivo e endereço aproximado do ponto escolhido.
class LocationService {
  const LocationService();

  /// Posição atual. Lança exceção legível quando a permissão é negada.
  Future<GeoPoint> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Ative a localização do dispositivo para continuar.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Permita o acesso à localização para usar esta função.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 15));
    return GeoPoint(position.latitude, position.longitude);
  }

  /// Última posição conhecida sem solicitar permissão (para distâncias no feed).
  Future<GeoPoint?> lastKnownPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
        return null;
      }
      final position = kIsWeb
          ? await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 8))
          : await Geolocator.getLastKnownPosition();
      return position == null ? null : GeoPoint(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  double distanceKm(GeoPoint from, double latitude, double longitude) =>
      Geolocator.distanceBetween(from.latitude, from.longitude, latitude, longitude) / 1000;

  Future<ResolvedAddress> reverseGeocode(GeoPoint point) async {
    if (!kIsWeb) {
      try {
        final placemarks = await geo.placemarkFromCoordinates(point.latitude, point.longitude);
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          return ResolvedAddress(
            street: _first([place.thoroughfare, place.street]),
            neighborhood: _first([place.subLocality]),
            city: _first([place.locality, place.subAdministrativeArea]),
            stateCode: stateCodeFromName(place.administrativeArea),
          );
        }
      } catch (_) {
        // Recorre ao Nominatim abaixo.
      }
    }
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '${point.latitude}',
        'lon': '${point.longitude}',
        'zoom': '18',
        'addressdetails': '1',
      });
      final response = await http
          .get(uri, headers: const {'Accept': 'application/json', 'User-Agent': 'UrbApp/1.0'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const ResolvedAddress();
      final address = (jsonDecode(response.body) as Map<String, dynamic>)['address'] as Map<String, dynamic>? ?? {};
      return ResolvedAddress(
        street: _first([address['road'], address['pedestrian'], address['footway']]),
        neighborhood: _first([address['suburb'], address['neighbourhood'], address['quarter']]),
        city: _first([address['city'], address['town'], address['village'], address['municipality']]),
        stateCode: stateCodeFromName(address['state'] as String?),
      );
    } catch (_) {
      return const ResolvedAddress();
    }
  }

  /// Associa o endereço resolvido a uma cidade cadastrada.
  CityOption? matchCity(List<CityOption> cities, ResolvedAddress address) {
    final target = address.city == null ? null : normalize(address.city!);
    if (target == null || target.isEmpty) return null;
    CityOption? partial;
    for (final city in cities) {
      if (address.stateCode != null && city.stateCode != address.stateCode) continue;
      final name = normalize(city.name);
      if (name == target) return city;
      if (name.contains(target) || target.contains(name)) partial ??= city;
    }
    return partial;
  }

  static String normalize(String value) {
    const map = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'é': 'e', 'ê': 'e', 'í': 'i',
      'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ü': 'u', 'ç': 'c',
    };
    var text = value.trim().toLowerCase();
    map.forEach((from, to) => text = text.replaceAll(from, to));
    return text
        .replaceAll(RegExp(r'^(municipio|cidade|estancia turistica) de\s+'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? stateCodeFromName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    const states = {
      'acre': 'ac', 'alagoas': 'al', 'amapa': 'ap', 'amazonas': 'am', 'bahia': 'ba',
      'ceara': 'ce', 'distrito federal': 'df', 'espirito santo': 'es', 'goias': 'go',
      'maranhao': 'ma', 'mato grosso': 'mt', 'mato grosso do sul': 'ms', 'minas gerais': 'mg',
      'para': 'pa', 'paraiba': 'pb', 'parana': 'pr', 'pernambuco': 'pe', 'piaui': 'pi',
      'rio de janeiro': 'rj', 'rio grande do norte': 'rn', 'rio grande do sul': 'rs',
      'rondonia': 'ro', 'roraima': 'rr', 'santa catarina': 'sc', 'sao paulo': 'sp',
      'sergipe': 'se', 'tocantins': 'to',
    };
    final normalized = normalize(name);
    if (normalized.length == 2) return normalized;
    return states[normalized];
  }

  String? _first(List<dynamic> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
