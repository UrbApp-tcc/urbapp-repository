import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/gradient_button.dart';
import '../widgets/wave_header.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({
    super.key,
    this.returnToPreviousOnSuccess = false,
  });

  final bool returnToPreviousOnSuccess;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _postService = PostService();
  final _mapController = MapController();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categorySearchController = TextEditingController();

  List<LookupOption> _cities = const [];
  List<LookupOption> _categories = const [];
  List<PlatformFile> _selectedMedia = const [];

  LookupOption? _selectedCity;
  LookupOption? _selectedCategory;

  LatLng? _selectedPoint;
  String _locationLabel = 'Buscando sua localizacao atual...';
  String _cityLabel = 'Cidade nao identificada';

  bool _isAnonymous = false;
  bool _isSubmitting = false;
  bool _isLoadingLookups = true;
  bool _isLoadingLocation = true;
  bool _isResolvingAddress = false;

  Timer? _reverseGeocodeDebounce;

  static const double _maxContentWidth = 440;
  static const double _fieldSpacing = 16;
  static const LatLng _fallbackPoint = LatLng(-23.55052, -46.63331);

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  @override
  void dispose() {
    _reverseGeocodeDebounce?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _categorySearchController.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    setState(() => _isLoadingLookups = true);

    try {
      final cities = await _postService.fetchCities();
      final categories = await _postService.fetchCategories();

      if (!mounted) return;

      setState(() {
        _cities = cities;
        _categories = categories;
        _isLoadingLookups = false;
      });

      await _initializeLocation();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoadingLookups = false;
        _isLoadingLocation = false;
      });
      _showError(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _initializeLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Ative a localizacao do dispositivo para usar o mapa.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permissao de localizacao negada.');
      }

      final position = await Geolocator.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);

      if (!mounted) return;

      setState(() {
        _selectedPoint = point;
        _isLoadingLocation = false;
      });

      _mapController.move(point, 16);
      await _updateAddressFromPoint(point);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _selectedPoint = _fallbackPoint;
        _isLoadingLocation = false;
        _locationLabel = 'Nao foi possivel usar sua localizacao atual. Ajuste o pin manualmente no mapa.';
        _cityLabel = 'Cidade nao identificada';
      });

      _mapController.move(_fallbackPoint, 13);
      _showError(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  String? _validateRequired(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Informe $label';
    }
    return null;
  }

  String get _currentUserLabel {
    return _authService.currentUser?.email ?? 'Usuario autenticado';
  }

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'avi', 'mkv'],
    );

    if (result == null) return;

    setState(() {
      _selectedMedia = result.files;
    });
  }

  Future<void> _updateAddressFromPoint(LatLng point) async {
    if (!mounted) return;

    setState(() => _isResolvingAddress = true);

    try {
      final locationData = await _fetchAddressFromCoordinates(point);
      final street = locationData.street;
      final neighborhood = locationData.neighborhood;
      final locality = locationData.city;

      final locationParts = <String>[
        if (street.isNotEmpty) street,
        if (neighborhood.isNotEmpty) neighborhood,
      ];

      final matchedCity = _matchCity(locality);

      if (!mounted) return;

      setState(() {
        _selectedPoint = point;
        _selectedCity = matchedCity;
        _cityLabel = matchedCity?.name ?? (locality.isNotEmpty ? locality : 'Cidade nao identificada');
        _locationLabel = locationParts.isEmpty
            ? 'Endereco nao identificado com detalhes. Ajuste o pin no mapa.'
            : locationParts.join(' - ');
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _selectedPoint = point;
        _selectedCity = null;
        _cityLabel = 'Cidade nao identificada';
        _locationLabel = 'Nao foi possivel identificar rua e bairro para este ponto.';
      });
    } finally {
      if (mounted) {
        setState(() => _isResolvingAddress = false);
      }
    }
  }

  LookupOption? _matchCity(String? cityName) {
    if (cityName == null || cityName.trim().isEmpty) return null;

    final normalizedTarget = _normalizeText(cityName);
    for (final city in _cities) {
      if (_normalizeText(city.name) == normalizedTarget) {
        return city;
      }
    }

    return null;
  }

  Future<({String street, String neighborhood, String city})> _fetchAddressFromCoordinates(
    LatLng point,
  ) async {
    final uri = Uri.https(
      'nominatim.openstreetmap.org',
      '/reverse',
      {
        'format': 'jsonv2',
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'zoom': '18',
        'addressdetails': '1',
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Falha ao consultar o endereco no mapa.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final address = (data['address'] as Map<String, dynamic>?) ?? const {};

    final street = (address['road'] ?? address['pedestrian'] ?? address['footway'] ?? '')
        .toString()
        .trim();
    final neighborhood = (address['suburb'] ?? address['neighbourhood'] ?? address['quarter'] ?? '')
        .toString()
        .trim();
    final city = (address['city'] ??
            address['town'] ??
            address['village'] ??
            address['municipality'] ??
            address['county'] ??
            '')
        .toString()
        .trim();

    return (
      street: street,
      neighborhood: neighborhood,
      city: city,
    );
  }

  String _normalizeText(String value) {
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'é': 'e',
      'ê': 'e',
      'í': 'i',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ç': 'c',
    };

    var normalized = value.trim().toLowerCase();
    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(source, target);
    });
    return normalized;
  }

  Future<void> _submitPost() async {
    if (!_formKey.currentState!.validate()) return;

    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      _showError('Sua sessao expirou. Entre novamente para publicar o reporte.');
      return;
    }

    if (_selectedPoint == null) {
      _showError('Aguarde o mapa carregar ou escolha um ponto no mapa.');
      return;
    }

    if (_selectedCity == null) {
      _showError('Nao foi possivel identificar uma cidade valida para o ponto selecionado.');
      return;
    }

    if (_selectedCategory == null) {
      _showError('Selecione uma categoria.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      final postId = await _postService.createPost(
        userId: currentUser.id,
        cityId: _selectedCity!.id,
        categoryId: _selectedCategory!.id,
        title: _titleController.text,
        description: _descriptionController.text,
        latitude: _selectedPoint!.latitude,
        longitude: _selectedPoint!.longitude,
        isAnonymous: _isAnonymous,
      );

      await _postService.createInitialStatusHistory(
        postId: postId,
        userId: currentUser.id,
      );

      await _postService.uploadPostImages(
        userId: currentUser.id,
        postId: postId,
        files: _selectedMedia,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedMedia.isEmpty
                ? 'Post criado com sucesso!'
                : 'Post criado com imagens com sucesso!',
          ),
          backgroundColor: AppColors.resolved,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );

      _formKey.currentState!.reset();
      _titleController.clear();
      _descriptionController.clear();
      _categorySearchController.clear();

      setState(() {
        _isAnonymous = false;
        _selectedCategory = null;
        _selectedMedia = const [];
      });

      if (widget.returnToPreviousOnSuccess && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      _showError(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            children: [
              WaveHeader(
                height: 220,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _buildHeaderContent(),
                  ),
                ),
              ),
              const AppLogo(height: 100),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                    child: _buildFormCard(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderContent() {
    return Stack(
      children: [
        if (Navigator.of(context).canPop())
          Positioned(
            top: 0,
            left: 0,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
          ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            const Text(
              'Criar um Reporte!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Registre um novo reporte para ajudar a comunidade a resolver problemas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
        border: Border.all(color: AppColors.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Detalhes do post',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Preencha os campos abaixo para registrar um novo reporte.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionLabel('Identificação'),
            const SizedBox(height: 24),
            _buildAnonymousCard(),
            const SizedBox(height: 12),
            _buildAuthenticatedUserCard(),
            const SizedBox(height: 24),
            _buildSectionLabel('Categoria'),
            const SizedBox(height: 12),
            _buildLookupField(
              label: 'Categoria',
              controller: _categorySearchController,
              options: _categories,
              selectedOption: _selectedCategory,
              loading: _isLoadingLookups,
              icon: Icons.category_outlined,
              emptyMessage: 'Nenhuma categoria encontrada.',
              onSelected: (option) {
                setState(() {
                  _selectedCategory = option;
                  _categorySearchController.text = option.name;
                });
              },
            ),
            const SizedBox(height: 24),
            _buildSectionLabel('Conteúdo'),
            const SizedBox(height: 12),
            AuthTextField(
              controller: _titleController,
              validator: (value) => _validateRequired(value, 'o ttulo'),
              hintText: 'Título',
              prefixIcon: const Icon(Icons.title_rounded, size: 22),
            ),
            const SizedBox(height: _fieldSpacing),
            TextFormField(
              controller: _descriptionController,
              validator: (value) => _validateRequired(value, 'a descrição'),
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 5,
              maxLines: 7,
              decoration: const InputDecoration(
                hintText: 'Detalhe o seu problema',
                fillColor: AppColors.background,
                filled: true,
                contentPadding: EdgeInsets.fromLTRB(16, 18, 16, 18),
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 74),
                  child: Icon(Icons.description_outlined, size: 22),
                ),
              ),
            ),
            const SizedBox(height: _fieldSpacing),
            _buildMediaPicker(),
            const SizedBox(height: 24),
            _buildSectionLabel('Localização'),
            const SizedBox(height: 12),
            _buildLocationCard(),
            const SizedBox(height: 28),
            GradientButton(
              label: 'Publicar reporte',
              loading: _isSubmitting,
              onPressed: (_isLoadingLookups || _isLoadingLocation) ? null : _submitPost,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnonymousCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.visibility_off_outlined,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reportar em anonimo',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Ocultar o autor do post quando ele for publicado.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isAnonymous,
            activeColor: AppColors.primary,
            onChanged: (value) => setState(() => _isAnonymous = value),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthenticatedUserCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Usuario autenticado',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _currentUserLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPicker() {
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adicionar midia',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Selecione imagens e videos para anexar ao post.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _pickMedia,
                child: const Text('Escolher'),
              ),
            ],
          ),
          if (_selectedMedia.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedMedia
                  .map(
                    (file) => Chip(
                      label: Text(
                        file.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                      deleteIcon: const Icon(Icons.close_rounded, size: 18),
                      onDeleted: () {
                        setState(() {
                          _selectedMedia = _selectedMedia.where((item) => item != file).toList();
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
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
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.place_outlined,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isResolvingAddress ? 'Atualizando endereco...' : _locationLabel,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _cityLabel,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Usar minha localizacao',
                onPressed: _isLoadingLocation ? null : _initializeLocation,
                icon: const Icon(Icons.my_location_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 260,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _selectedPoint ?? _fallbackPoint,
                      initialZoom: 15,
                      onPositionChanged: (camera, hasGesture) {
                        final center = camera.center;
                        if (center == null) return;

                        _selectedPoint = center;
                        _reverseGeocodeDebounce?.cancel();
                        _reverseGeocodeDebounce = Timer(
                          const Duration(milliseconds: 500),
                          () => _updateAddressFromPoint(center),
                        );
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.meu_app',
                      ),
                    ],
                  ),
                  IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_pin,
                          size: 42,
                          color: AppColors.accentPink,
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'O pin fica travado no centro. Arraste o mapa para ajustar o ponto exato do reporte.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLookupField({
    required String label,
    required TextEditingController controller,
    required List<LookupOption> options,
    required LookupOption? selectedOption,
    required bool loading,
    required IconData icon,
    required String emptyMessage,
    required ValueChanged<LookupOption> onSelected,
  }) {
    return Autocomplete<LookupOption>(
      displayStringForOption: (option) => option.name,
      optionsBuilder: (textEditingValue) {
        if (loading) {
          return const Iterable<LookupOption>.empty();
        }

        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) {
          return options.take(8);
        }

        return options.where(
          (option) => option.name.toLowerCase().contains(query) || option.id.toString().contains(query),
        );
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, textController, focusNode, onSubmitted) {
        textController.value = controller.value;

        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          validator: (_) {
            if (selectedOption == null) {
              return 'Selecione ${label.toLowerCase()} na lista';
            }
            return null;
          },
          onChanged: (value) {
            controller.value = textController.value;
            if (selectedOption != null && value.trim() != selectedOption.name) {
              setState(() => _selectedCategory = null);
            }
          },
          decoration: InputDecoration(
            hintText: loading ? 'Carregando $label...' : 'Pesquisar $label',
            fillColor: AppColors.background,
            filled: true,
            prefixIcon: Icon(icon, size: 22),
            suffixIcon: loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : selectedOption != null
                    ? const Icon(Icons.check_circle, color: AppColors.resolved)
                    : const Icon(Icons.search_rounded),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, optionsList) {
        final items = optionsList.toList();

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: MediaQuery.sizeOf(context).width - 48,
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          emptyMessage,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final option = items[index];
                        return ListTile(
                          title: Text(option.name),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.primaryDark,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
  }
}
