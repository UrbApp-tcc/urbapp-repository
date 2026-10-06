import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import 'urb_components.dart';
import 'urb_icon.dart';

/// Lista pesquisável de cidades em sheet (substitui o dropdown do protótipo
/// quando há muitas cidades cadastradas).
Future<CityOption?> showCityPicker(
  BuildContext context, {
  required List<CityOption> cities,
  CityOption? selected,
}) {
  return showUrbSheet<CityOption>(
    context: context,
    eyebrow: 'Sua cidade',
    title: 'Escolha a cidade',
    builder: (sheetContext) => _CityPickerBody(cities: cities, selected: selected),
  );
}

class _CityPickerBody extends StatefulWidget {
  const _CityPickerBody({required this.cities, this.selected});

  final List<CityOption> cities;
  final CityOption? selected;

  @override
  State<_CityPickerBody> createState() => _CityPickerBodyState();
}

class _CityPickerBodyState extends State<_CityPickerBody> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final normalized = LocationService.normalize(_query);
    final filtered = widget.cities
        .where((city) => normalized.isEmpty || LocationService.normalize(city.name).contains(normalized))
        .take(60)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UrbTextField(
          hint: 'Buscar cidade',
          prefix: const Padding(
            padding: EdgeInsets.all(14),
            child: UrbIcon(UrbIcons.search, size: 17, color: UrbColors.muted),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
          child: filtered.isEmpty
              ? const UrbEmptyState(
                  compact: true,
                  title: 'Nenhuma cidade encontrada',
                  message: 'Confira a grafia ou procure outra cidade.',
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final city = filtered[index];
                    final selected = city.id == widget.selected?.id;
                    return Material(
                      color: selected ? UrbColors.blueSoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () => Navigator.of(context).pop(city),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  city.label,
                                  style: UrbText.bodySmall.copyWith(
                                    color: selected ? UrbColors.blue : const Color(0xFF536174),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (selected) const UrbIcon(UrbIcons.check, size: 16, color: UrbColors.blue),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Seletor "Sua cidade" do cabeçalho da Home.
class CitySelectorButton extends StatelessWidget {
  const CitySelectorButton({super.key, required this.city, required this.onTap, this.label = 'Sua cidade'});

  final CityOption? city;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: ${city?.name ?? 'não selecionada'}',
      excludeSemantics: true,
      child: Material(
        color: Colors.white.withValues(alpha: 0.86),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UrbRadius.md),
          side: const BorderSide(color: Color(0xFFD7DDE4)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(UrbRadius.md),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const UrbIcon(UrbIcons.location, size: 19, color: UrbColors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label.toUpperCase(), style: UrbText.eyebrow.copyWith(color: const Color(0xFF8B96A5), fontSize: 9.5, letterSpacing: 0.8)),
                        const SizedBox(height: 1),
                        Text(
                          city?.name ?? 'Selecionar cidade',
                          style: UrbText.titleSmall.copyWith(color: const Color(0xFF13233B), fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const UrbIcon(UrbIcons.chevronDown, size: 16, color: Color(0xFF8B96A5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
