import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LookupOption {
  const LookupOption({required this.id, required this.name, this.stateCode});

  final int id;
  final String name;
  final String? stateCode;
}

class PostService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _postImagesBucket = 'post-images';

  Future<List<LookupOption>> fetchCities() async {
    try {
      final response = await _supabase
          .from('cities')
          .select('id, name, state')
          .order('name');

      return (response as List<dynamic>)
          .map(
            (item) => LookupOption(
              id: item['id'] as int,
              name: item['name'] as String,
              stateCode: item['state'] as String?,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao buscar cidades: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao buscar cidades.');
    }
  }

  Future<List<LookupOption>> fetchCategories() async {
    try {
      final response = await _supabase
          .from('problem_categories')
          .select('id, name')
          .order('name');

      return (response as List<dynamic>)
          .map(
            (item) => LookupOption(
              id: item['id'] as int,
              name: item['name'] as String,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao buscar categorias: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao buscar categorias.');
    }
  }

  Future<int> createPost({
    required String userId,
    int? cityId,
    required int categoryId,
    required String title,
    required String description,
    required double latitude,
    required double longitude,
    bool isAnonymous = false,
  }) async {
    try {
      await _supabase.rpc('ensure_my_profile');

      final response = await _supabase
          .from('posts')
          .insert({
            'user_id': userId,
            'city_id': cityId,
            'category_id': categoryId,
            'title': title.trim(),
            'description': description.trim(),
            'latitude': latitude,
            'longitude': longitude,
            'anonymity': isAnonymous,
            'status': 'open',
          })
          .select('id')
          .single();

      return response['id'] as int;
    } on PostgrestException catch (error) {
      throw Exception('Erro ao criar post: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao criar post: $error');
    }
  }

  Future<void> createInitialStatusHistory({
    required int postId,
    required String userId,
  }) async {
    try {
      await _supabase.from('post_status_history').insert({
        'post_id': postId,
        'changed_by': userId,
        'from_status': null,
        'to_status': 'open',
        'note': 'Post criado pelo usuario.',
      });
    } on PostgrestException catch (error) {
      throw Exception('Erro ao criar historico do post: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao criar historico do post: $error');
    }
  }

  Future<void> uploadPostImages({
    required String userId,
    required int postId,
    required List<XFile> files,
  }) async {
    try {
      final imageFiles = files.where(_isImageFile).toList();
      if (imageFiles.isEmpty) return;

      for (var index = 0; index < imageFiles.length; index++) {
        final image = imageFiles[index];
        final bytes = await image.readAsBytes();
        final extension = _fileExtension(image.name);
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_$index.$extension';
        final storagePath = '$userId/posts/$postId/$fileName';

        await _supabase.storage
            .from(_postImagesBucket)
            .uploadBinary(
              storagePath,
              bytes,
              fileOptions: const FileOptions(upsert: false),
            );

        await _supabase.from('post_images').insert({
          'post_id': postId,
          'storage_path': storagePath,
          'position': index + 1,
        });
      }
    } on StorageException catch (error) {
      throw Exception('Erro ao enviar imagem para o storage: ${error.message}');
    } on PostgrestException catch (error) {
      throw Exception('Erro ao salvar imagem do post: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao salvar imagens do post: $error');
    }
  }

  Future<LookupOption?> findCityByName({
    required String cityName,
    String? stateCode,
  }) async {
    final normalizedName = _normalizeText(cityName);
    if (normalizedName.isEmpty) return null;

    try {
      var query = _supabase.from('cities').select('id, name, state');
      if (stateCode != null && stateCode.isNotEmpty) {
        query = query.eq('state', stateCode);
      }

      final response = await query.limit(200);
      final cities = (response as List<dynamic>)
          .map(
            (item) => LookupOption(
              id: item['id'] as int,
              name: item['name'] as String,
              stateCode: item['state'] as String?,
            ),
          )
          .toList();

      LookupOption? partialMatch;
      for (final city in cities) {
        final normalizedCityName = _normalizeText(city.name);
        if (normalizedCityName == normalizedName) {
          return city;
        }

        if (normalizedCityName.contains(normalizedName) ||
            normalizedName.contains(normalizedCityName)) {
          partialMatch ??= city;
        }
      }

      return partialMatch;
    } on PostgrestException catch (error) {
      throw Exception('Erro ao localizar cidade: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao localizar cidade: $error');
    }
  }

  bool _isImageFile(XFile file) {
    final extension = _fileExtension(file.name);
    return {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(extension);
  }

  String _fileExtension(String name) {
    final parts = name.split('.');
    if (parts.length < 2) return 'bin';
    return parts.last.toLowerCase();
  }

  String _normalizeText(String value) {
    var normalized = value.trim().toLowerCase();
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
      'Ã¡': 'a',
      'Ã ': 'a',
      'Ã£': 'a',
      'Ã¢': 'a',
      'Ã©': 'e',
      'Ãª': 'e',
      'Ã­': 'i',
      'Ã³': 'o',
      'Ã´': 'o',
      'Ãµ': 'o',
      'Ãº': 'u',
      'Ã§': 'c',
    };

    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(source, target);
    });

    return normalized
        .replaceAll(RegExp(r'^municipio de\s+'), '')
        .replaceAll(RegExp(r'^cidade de\s+'), '')
        .replaceAll(RegExp(r'^estancia turistica de\s+'), '')
        .replaceAll(RegExp(r'\s*[-/]\s*[a-z]{2}$'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
