import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/urb/occurrence_map.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

class PickedLocation {
  const PickedLocation(this.point, this.address);

  final GeoPoint point;
  final ResolvedAddress address;
}

/// "Ajustar local": o mapa se move sob um pino fixo no centro.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, required this.initial, this.initialAddress});

  final GeoPoint initial;
  final ResolvedAddress? initialAddress;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _location = const LocationService();
  late GeoPoint _point = widget.initial;
  late ResolvedAddress? _address = widget.initialAddress;
  bool _resolving = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onMoved(MapCamera camera) {
    _point = GeoPoint(camera.center.latitude, camera.center.longitude);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _resolve);
    if (!_resolving) setState(() => _resolving = true);
  }

  Future<void> _resolve() async {
    final address = await _location.reverseGeocode(_point);
    if (!mounted) return;
    setState(() {
      _address = address;
      _resolving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Ajustar local'),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(widget.initial.latitude, widget.initial.longitude),
                    initialZoom: 16,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onPositionChanged: (camera, hasGesture) {
                      if (hasGesture) _onMoved(camera);
                    },
                  ),
                  children: const [
                    UrbMapTiles(),
                    SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
                  ],
                ),
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -18),
                      child: const UrbIcon(UrbIcons.location, size: 40, color: UrbColors.blue, strokeWidth: 2.2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.paddingOf(context).bottom + 18),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: UrbColors.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const UrbIcon(UrbIcons.location, size: 15, color: UrbColors.blue),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _resolving ? 'Identificando endereço…' : (_address?.label ?? 'Local aproximado'),
                        style: UrbText.title.copyWith(fontSize: 15),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Arraste o mapa para posicionar o pino', style: UrbText.meta),
                const SizedBox(height: 16),
                UrbPrimaryButton(
                  label: 'Confirmar local',
                  icon: UrbIcons.check,
                  onPressed: _resolving
                      ? null
                      : () => Navigator.of(context).pop(PickedLocation(_point, _address ?? const ResolvedAddress())),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
