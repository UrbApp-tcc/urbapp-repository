import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/models.dart';
import '../../theme/app_theme.dart';
import 'urb_icon.dart';

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'br.com.urbapp.app';

/// Camada base do mapa com o tratamento visual do protótipo (tons dessaturados).
class UrbMapTiles extends StatelessWidget {
  const UrbMapTiles({super.key});

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.86, 0.10, 0.04, 0, 6,
        0.06, 0.90, 0.04, 0, 6,
        0.06, 0.10, 0.84, 0, 6,
        0, 0, 0, 1, 0,
      ]),
      child: TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _userAgent),
    );
  }
}

/// Pino em gota azul com miolo lime (marcador de ocorrência do Figma).
class OccurrencePin extends StatelessWidget {
  const OccurrencePin({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.785,
      child: Container(
        width: 31,
        height: 31,
        decoration: BoxDecoration(
          color: selected ? UrbColors.navy : UrbColors.blue,
          border: Border.all(color: Colors.white, width: 3),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(5),
          ),
          boxShadow: [
            const BoxShadow(color: Color(0x3311233D), blurRadius: 14, offset: Offset(0, 6)),
            if (selected) BoxShadow(color: UrbColors.blue.withValues(alpha: 0.17), spreadRadius: 5),
          ],
        ),
        alignment: Alignment.center,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: UrbColors.lime, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class OccurrenceMap extends StatefulWidget {
  const OccurrenceMap({
    super.key,
    required this.occurrences,
    required this.center,
    this.selectedId,
    required this.onSelect,
    this.label,
  });

  final List<Occurrence> occurrences;
  final LatLng center;
  final int? selectedId;
  final ValueChanged<Occurrence?> onSelect;
  final String? label;

  @override
  State<OccurrenceMap> createState() => _OccurrenceMapState();
}

class _OccurrenceMapState extends State<OccurrenceMap> {
  final _controller = MapController();

  void _zoom(double delta) {
    final camera = _controller.camera;
    _controller.move(camera.center, (camera.zoom + delta).clamp(4, 18));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDBE1DF)),
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFFE4E8E4),
        ),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: widget.center,
                initialZoom: 13,
                onTap: (_, _) => widget.onSelect(null),
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                const UrbMapTiles(),
                MarkerLayer(
                  markers: [
                    for (final occurrence in widget.occurrences)
                      Marker(
                        point: LatLng(occurrence.latitude, occurrence.longitude),
                        width: 44,
                        height: 44,
                        // A ponta da gota (base da caixa) fica sobre a coordenada.
                        alignment: Alignment.topCenter,
                        child: Semantics(
                          button: true,
                          label: 'Abrir ${occurrence.title}',
                          child: GestureDetector(
                            onTap: () => widget.onSelect(occurrence),
                            child: Center(child: OccurrencePin(selected: occurrence.id == widget.selectedId)),
                          ),
                        ),
                      ),
                  ],
                ),
                const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
              ],
            ),
            if (widget.label != null)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: const [BoxShadow(color: Color(0x1711233D), blurRadius: 16, offset: Offset(0, 5))],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const UrbIcon(UrbIcons.location, size: 13, color: UrbColors.navy),
                      const SizedBox(width: 5),
                      Text(widget.label!, style: UrbText.caption.copyWith(color: UrbColors.navy, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: const [BoxShadow(color: Color(0x1711233D), blurRadius: 16, offset: Offset(0, 5))],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _ZoomButton(label: '+', tooltip: 'Aproximar mapa', onTap: () => _zoom(1)),
                    const SizedBox(height: 1),
                    _ZoomButton(label: '−', tooltip: 'Afastar mapa', onTap: () => _zoom(-1)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.label, required this.tooltip, required this.onTap});

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.95),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(child: Text(label, style: UrbText.title.copyWith(fontWeight: FontWeight.w500))),
          ),
        ),
      ),
    );
  }
}
