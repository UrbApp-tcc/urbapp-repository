import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/urbapp_design.dart';
import 'urb_dialog.dart';

/// Escolha das fotos do reporte: botão tracejado "Adicionar" e
/// miniaturas com o "x" para remover.
class MediaPickerWidget extends StatefulWidget {
  const MediaPickerWidget({
    super.key,
    required this.images,
    required this.onChanged,
    this.maxImages = 5,
  });

  final List<XFile> images;
  final ValueChanged<List<XFile>> onChanged;
  final int maxImages;

  @override
  State<MediaPickerWidget> createState() => _MediaPickerWidgetState();
}

class _MediaPickerWidgetState extends State<MediaPickerWidget> {
  final ImagePicker _picker = ImagePicker();
  bool _isPicking = false;

  static const double _tileSize = 92;

  Future<void> _pickImages() async {
    if (_isPicking) return;

    if (widget.images.length >= widget.maxImages) {
      showUrbSnack(
        context,
        'Você pode adicionar no máximo ${widget.maxImages} fotos.',
        error: true,
      );
      return;
    }

    setState(() => _isPicking = true);

    try {
      final selectedImages = await _picker.pickMultiImage();
      if (!mounted || selectedImages.isEmpty) return;

      final availableSlots = widget.maxImages - widget.images.length;
      final imagesToAdd = selectedImages.take(availableSlots).toList();

      widget.onChanged([...widget.images, ...imagesToAdd]);

      if (selectedImages.length > availableSlots) {
        showUrbSnack(
          context,
          'Limite de ${widget.maxImages} fotos por reporte. Só as primeiras foram adicionadas.',
          error: true,
        );
      }
    } catch (_) {
      if (mounted)
        showUrbSnack(
          context,
          'Não foi possível selecionar as fotos.',
          error: true,
        );
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _removeImage(int index) {
    final updatedImages = List<XFile>.from(widget.images)..removeAt(index);
    widget.onChanged(updatedImages);
  }

  Widget _preview(XFile image) {
    Widget error(BuildContext context, Object error, StackTrace? stackTrace) =>
        const DecoratedBox(
          decoration: BoxDecoration(gradient: UrbGradients.photo),
          child: Center(
            child: Icon(Icons.broken_image_outlined, color: Color(0xFF9FB0C6)),
          ),
        );

    if (kIsWeb) {
      return Image.network(image.path, fit: BoxFit.cover, errorBuilder: error);
    }
    return Image.file(File(image.path), fit: BoxFit.cover, errorBuilder: error);
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = widget.images.length < widget.maxImages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _tileSize,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              if (canAdd) ...[
                _AddTile(
                  size: _tileSize,
                  isLoading: _isPicking,
                  onTap: _pickImages,
                ),
                const SizedBox(width: 10),
              ],
              for (var i = 0; i < widget.images.length; i++) ...[
                // Cada foto nova "cresce" ao entrar.
                TweenAnimationBuilder<double>(
                  key: ValueKey(widget.images[i].path),
                  tween: Tween(begin: 0.7, end: 1),
                  duration: UrbMotion.of(
                    context,
                    const Duration(milliseconds: 320),
                  ),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: SizedBox(
                    width: _tileSize,
                    height: _tileSize,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: _preview(widget.images[i]),
                        ),
                        if (i == 0)
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xB30D1520),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Capa',
                                style: UrbText.body(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _removeImage(i),
                              child: const Tooltip(
                                message: 'Remover foto',
                                child: SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 15,
                                    color: UrbColors.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.images.isEmpty
              ? 'Adicione até ${widget.maxImages} fotos. A primeira vira a capa do reporte.'
              : '${widget.images.length} de ${widget.maxImages} fotos',
          textAlign: TextAlign.center,
          style: UrbText.body(
            size: 12,
            color: UrbColors.textMuted,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.size,
    required this.isLoading,
    required this.onTap,
  });

  final double size;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Adicionar fotos',
      child: GestureDetector(
        onTap: isLoading ? null : onTap,
        child: CustomPaint(
          painter: _DashedBorderPainter(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F5FD),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.add_a_photo_outlined,
                        color: UrbColors.violetDeep,
                        size: 24,
                      ),
                const SizedBox(height: 6),
                Text(
                  'Adicionar',
                  style: UrbText.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: UrbColors.violetDeep,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Borda tracejada arredondada do botão "Adicionar".
class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(18),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = const Color(0xFFB9ADE6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
        distance += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}
