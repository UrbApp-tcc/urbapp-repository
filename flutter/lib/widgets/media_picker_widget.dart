import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';

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

  Future<void> _pickImages() async {
    if (_isPicking) return;

    if (widget.images.length >= widget.maxImages) {
      _showSnackBar('Voce pode adicionar no maximo ${widget.maxImages} imagens.');
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
        _showSnackBar(
          'Limite de ${widget.maxImages} imagens por reporte. Apenas as primeiras foram adicionadas.',
        );
      }
    } catch (_) {
      _showSnackBar('Nao foi possivel selecionar as imagens.');
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  void _removeImage(int index) {
    final updatedImages = List<XFile>.from(widget.images)..removeAt(index);
    widget.onChanged(updatedImages);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildPreviewImage(XFile image) {
    if (kIsWeb) {
      return Image.network(
        image.path,
        fit: BoxFit.cover,
        errorBuilder: _buildImageError,
      );
    }

    return Image.file(
      File(image.path),
      fit: BoxFit.cover,
      errorBuilder: _buildImageError,
    );
  }

  Widget _buildImageError(BuildContext context, Object error, StackTrace? stackTrace) {
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image_outlined,
        color: AppColors.textHint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImages = widget.images.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.perm_media_outlined,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Adicionar midia',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.images.length}/${widget.maxImages} imagens',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Selecione ate 5 imagens da galeria para anexar ao post.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _isPicking ? null : _pickImages,
                icon: _isPicking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(_isPicking ? 'Carregando' : 'Adicionar'),
              ),
            ],
          ),
          if (hasImages) ...[
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth >= 360 ? 3 : 2;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.images.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, index) {
                    final image = widget.images[index];

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: _buildPreviewImage(image),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _removeImage(index),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
