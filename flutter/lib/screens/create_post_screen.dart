import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

import '../services/post_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/gradient_button.dart';
import '../widgets/wave_header.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _postService = PostService();

  final _userIdController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _streetController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _citySearchController = TextEditingController();
  final _categorySearchController = TextEditingController();

  List<LookupOption> _cities = const [];
  List<LookupOption> _categories = const [];
  List<PlatformFile> _selectedMedia = const [];

  LookupOption? _selectedCity;
  LookupOption? _selectedCategory;

  bool _isAnonymous = false;
  bool _isSubmitting = false;
  bool _isLoadingLookups = true;

  static const double _maxContentWidth = 440;
  static const double _fieldSpacing = 16;

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _streetController.dispose();
    _neighborhoodController.dispose();
    _citySearchController.dispose();
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
    } catch (error) {
      if (!mounted) return;

      setState(() => _isLoadingLookups = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  String? _validateRequired(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Informe $label';
    }
    return null;
  }

  String? _validateInteger(String? value, String label) {
    final requiredValidation = _validateRequired(value, label);
    if (requiredValidation != null) return requiredValidation;

    if (int.tryParse(value!.trim()) == null) {
      return '$label deve ser um numero inteiro';
    }
    return null;
  }

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'avi', 'mkv'],
    );

    if (result == null) return;

    setState(() {
      _selectedMedia = result.files;
    });
  }

  Future<({double latitude, double longitude})> _resolveCoordinates() async {
    final city = _selectedCity;
    if (city == null) {
      throw Exception('Selecione uma cidade antes de publicar.');
    }

    final address = [
      _streetController.text.trim(),
      _neighborhoodController.text.trim(),
      city.name,
    ].where((part) => part.isNotEmpty).join(', ');

    final locations = await locationFromAddress(address);
    if (locations.isEmpty) {
      throw Exception('Nao foi possivel localizar esse endereco no mapa.');
    }

    final match = locations.first;
    return (latitude: match.latitude, longitude: match.longitude);
  }

  Future<void> _submitPost() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCity == null) {
      _showError('Selecione uma cidade.');
      return;
    }

    if (_selectedCategory == null) {
      _showError('Selecione uma categoria.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      final coordinates = await _resolveCoordinates();

      await _postService.createPost(
        userId: int.parse(_userIdController.text.trim()),
        cityId: _selectedCity!.id,
        categoryId: _selectedCategory!.id,
        title: _titleController.text,
        description: _descriptionController.text,
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        isAnonymous: _isAnonymous,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedMedia.isEmpty
                ? 'Post criado com sucesso!'
                : 'Post criado com sucesso! A selecao de midia ja esta pronta na tela, mas o upload ainda precisa ser ligado ao storage.',
          ),
          backgroundColor: AppColors.resolved,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );

      _formKey.currentState!.reset();
      _userIdController.clear();
      _titleController.clear();
      _descriptionController.clear();
      _streetController.clear();
      _neighborhoodController.clear();
      _citySearchController.clear();
      _categorySearchController.clear();

      setState(() {
        _isAnonymous = false;
        _selectedCity = null;
        _selectedCategory = null;
        _selectedMedia = const [];
      });
    } on NoResultFoundException {
      _showError('Nao foi possivel encontrar esse endereco. Confira rua, bairro e cidade.');
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
    return Column(
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
          'Compartilhe um problema urbano com endereco, categoria e descricao.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 14,
            height: 1.4,
          ),
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
            _buildSectionLabel('Identificacao'),
            const SizedBox(height: 24),
            _buildAnonymousCard(),
            const SizedBox(height: 12),
            AuthTextField(
              controller: _userIdController,
              validator: (value) => _validateInteger(value, 'user_id'),
              hintText: 'Usuario',
              keyboardType: TextInputType.number,
              prefixIcon: const Icon(Icons.badge_outlined, size: 22),
            ),
            const SizedBox(height: 24),
            _buildSectionLabel('Cidade e categoria'),
            const SizedBox(height: 12),
            _buildLookupField(
              label: 'Cidade',
              controller: _citySearchController,
              options: _cities,
              selectedOption: _selectedCity,
              loading: _isLoadingLookups,
              icon: Icons.location_city_outlined,
              emptyMessage: 'Nenhuma cidade encontrada.',
              onSelected: (option) {
                setState(() {
                  _selectedCity = option;
                  _citySearchController.text = option.name;
                });
              },
            ),
            const SizedBox(height: _fieldSpacing),
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
            _buildSectionLabel('Conteudo'),
            const SizedBox(height: 12),
            AuthTextField(
              controller: _titleController,
              validator: (value) => _validateRequired(value, 'o titulo'),
              hintText: 'Titulo',
              prefixIcon: const Icon(Icons.title_rounded, size: 22),
            ),
            const SizedBox(height: _fieldSpacing),
            TextFormField(
              controller: _descriptionController,
              validator: (value) => _validateRequired(value, 'a descricao'),
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
            _buildSectionLabel('Endereco'),
            const SizedBox(height: 12),
            AuthTextField(
              controller: _streetController,
              validator: (value) => _validateRequired(value, 'a rua'),
              hintText: 'Rua',
              prefixIcon: const Icon(Icons.signpost_outlined, size: 22),
            ),
            const SizedBox(height: _fieldSpacing),
            AuthTextField(
              controller: _neighborhoodController,
              validator: (value) => _validateRequired(value, 'o bairro'),
              hintText: 'Bairro',
              prefixIcon: const Icon(Icons.location_on_outlined, size: 22),
            ),
            const SizedBox(height: 28),
            GradientButton(
              label: 'Publicar reporte',
              loading: _isSubmitting,
              onPressed: _isLoadingLookups ? null : _submitPost,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Autocomplete<LookupOption>(
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
              (option) =>
                  option.name.toLowerCase().contains(query) ||
                  option.id.toString().contains(query),
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
                  setState(() {
                    if (label == 'Cidade') {
                      _selectedCity = null;
                    } else {
                      _selectedCategory = null;
                    }
                  });
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
        ),
      ],
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
