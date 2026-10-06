import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

/// Ícones de traço do protótipo aprovado (viewBox 24×24, stroke 1.8).
enum UrbIcons {
  arrow,
  bell,
  bookmark,
  camera,
  check,
  checkCircle,
  chevron,
  chevronLeft,
  chevronDown,
  close,
  eye,
  eyeOff,
  filter,
  heart,
  home,
  list,
  location,
  map,
  message,
  profile,
  pencil,
  search,
  share,
  transparency,
  settings,
  logout,
  lock,
  flag,
  plus,
  clock,
  building,
  megaphone,
  more,
}

const Map<UrbIcons, List<String>> _paths = {
  UrbIcons.more: [
    'M5 11a1 1 0 1 0 0 2a1 1 0 1 0 0-2Z',
    'M12 11a1 1 0 1 0 0 2a1 1 0 1 0 0-2Z',
    'M19 11a1 1 0 1 0 0 2a1 1 0 1 0 0-2Z',
  ],
  UrbIcons.arrow: ['m9 5 7 7-7 7M4 12h12'],
  UrbIcons.bell: ['M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4'],
  UrbIcons.bookmark: ['M6 4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v18l-6-4-6 4V4Z'],
  UrbIcons.camera: [
    'M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3L14.5 4Z',
    'M15 13a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z',
  ],
  UrbIcons.check: ['m5 12 4 4L19 6'],
  UrbIcons.checkCircle: [
    'M22 12a10 10 0 1 1-20 0a10 10 0 1 1 20 0Z',
    'm9 12 2 2 4-4',
  ],
  UrbIcons.chevron: ['m9 18 6-6-6-6'],
  UrbIcons.chevronLeft: ['m15 18-6-6 6-6'],
  UrbIcons.chevronDown: ['m6 9 6 6 6-6'],
  UrbIcons.close: ['M18 6 6 18M6 6l12 12'],
  UrbIcons.eye: [
    'M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12',
    'M15 12a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z',
  ],
  UrbIcons.eyeOff: [
    'M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12',
    'm3 3 18 18M9.9 9.9a3 3 0 0 0 4.2 4.2',
  ],
  UrbIcons.filter: [
    'M4 6h16M7 12h10M10 18h4',
    'M9.5 6a1.5 1.5 0 1 1-3 0a1.5 1.5 0 1 1 3 0Z',
    'M16.5 12a1.5 1.5 0 1 1-3 0a1.5 1.5 0 1 1 3 0Z',
    'M13.5 18a1.5 1.5 0 1 1-3 0a1.5 1.5 0 1 1 3 0Z',
  ],
  UrbIcons.heart: [
    'M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8l1.1 1.1L12 21l7.8-7.5 1.1-1.1a5.5 5.5 0 0 0-.1-7.8Z',
  ],
  UrbIcons.home: ['m3 11 9-8 9 8', 'M5 10v10h14V10M9 20v-6h6v6'],
  UrbIcons.list: [
    'M8 6h12M8 12h12M8 18h12',
    'M5 6a1 1 0 1 1-2 0a1 1 0 1 1 2 0Z',
    'M5 12a1 1 0 1 1-2 0a1 1 0 1 1 2 0Z',
    'M5 18a1 1 0 1 1-2 0a1 1 0 1 1 2 0Z',
  ],
  UrbIcons.location: [
    'M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z',
    'M14.5 10a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0Z',
  ],
  UrbIcons.map: ['m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3V6Zm6-3v15m6-12v15'],
  UrbIcons.message: [
    'M21 15a4 4 0 0 1-4 4H8l-5 3V7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4v8Z',
  ],
  UrbIcons.profile: [
    'M16 8a4 4 0 1 1-8 0a4 4 0 1 1 8 0Z',
    'M4 21a8 8 0 0 1 16 0',
  ],
  UrbIcons.pencil: ['M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z'],
  UrbIcons.search: ['M18 11a7 7 0 1 1-14 0a7 7 0 1 1 14 0Z', 'm20 20-4-4'],
  UrbIcons.share: [
    'M20.5 5a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0Z',
    'M8.5 12a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0Z',
    'M20.5 19a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0Z',
    'm8.2 10.8 7.5-4.4M8.2 13.2l7.5 4.4',
  ],
  UrbIcons.transparency: [
    'M2 20h20',
    'M4 20V9l8-6 8 6v11',
    'M9 20v-5h6v5',
    'M9 12h6',
  ],
  UrbIcons.settings: [
    'M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z',
    'M15 12a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z',
  ],
  UrbIcons.logout: [
    'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9',
  ],
  UrbIcons.lock: [
    'M7 11h10a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2Z',
    'M8 11V7a4 4 0 1 1 8 0v4',
  ],
  UrbIcons.flag: [
    'M4 22V4M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1',
  ],
  UrbIcons.plus: ['M12 5v14M5 12h14'],
  UrbIcons.clock: ['M22 12a10 10 0 1 1-20 0a10 10 0 1 1 20 0Z', 'M12 6v6l4 2'],
  UrbIcons.building: [
    'M3 21h18M5 21V7l7-4 7 4v14',
    'M9 21v-4h6v4M9 10h1M14 10h1M9 13.5h1M14 13.5h1',
  ],
  UrbIcons.megaphone: ['m3 11 15-6v14L3 13v-2ZM7 12.5V18a2 2 0 0 0 4 0v-4'],
};

final Map<UrbIcons, Path> _cache = {};

Path _pathFor(UrbIcons icon) => _cache.putIfAbsent(icon, () {
  final combined = Path();
  for (final data in _paths[icon]!) {
    combined.addPath(parseSvgPathData(data), Offset.zero);
  }
  return combined;
});

class UrbIcon extends StatelessWidget {
  const UrbIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth = 1.8,
    this.filled = false,
    this.semanticLabel,
  });

  final UrbIcons icon;
  final double size;
  final Color? color;
  final double strokeWidth;
  final bool filled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? Colors.black;
    final painter = CustomPaint(
      size: Size.square(size),
      painter: _UrbIconPainter(
        path: _pathFor(icon),
        color: resolved,
        strokeWidth: strokeWidth,
        filled: filled,
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: painter);
    return Semantics(label: semanticLabel, child: painter);
  }
}

class _UrbIconPainter extends CustomPainter {
  _UrbIconPainter({
    required this.path,
    required this.color,
    required this.strokeWidth,
    required this.filled,
  });

  final Path path;
  final Color color;
  final double strokeWidth;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale);
    if (filled) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UrbIconPainter old) =>
      old.color != color ||
      old.path != path ||
      old.strokeWidth != strokeWidth ||
      old.filled != filled;
}
