import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LookupOption {
  const LookupOption({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;
}

class UserLookupResult {
  const UserLookupResult({
    required this.id,
  });

  final int id;
}

class PostService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _postImagesBucket = 'post-images';

  Future<List<LookupOption>> fetchCities() async {
    try {
      final response = await _supabase
          .from('cities')
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
    } on PostgrestException catch (e) {
      throw Exception('Erro ao buscar cidades: ${e.message}');
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
    } on PostgrestException catch (e) {
      throw Exception('Erro ao buscar categorias: ${e.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao buscar categorias.');
    }
  }

  Future<UserLookupResult> getUserByUsername(String username) async {
    try {
      final normalized = username.trim();
      if (normalized.isEmpty) {
        throw Exception('Informe um username.');
      }

      final response = await _supabase
          .from('users')
          .select('id')
          .eq('username', normalized)
          .maybeSingle();

      if (response == null) {
        throw Exception('Usuario nao encontrado para o username informado.');
      }

      return UserLookupResult(
        id: response['id'] as int,
      );
    } on PostgrestException catch (e) {
      throw Exception('Erro ao buscar usuario: ${e.message}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Erro inesperado ao buscar usuario.');
    }
  }

  Future<int> createPost({
    required int userId,
    required int cityId,
    required int categoryId,
    required String title,
    required String description,
    required double latitude,
    required double longitude,
    bool isAnonymous = false,
  }) async {
    try {
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
    } on PostgrestException catch (e) {
      throw Exception('Erro ao criar post: ${e.message}');
    } catch (e) {
      throw Exception('Erro inesperado ao criar post: $e');
    }
  }

  Future<void> createInitialStatusHistory({
    required int postId,
    required int userId,
  }) async {
    try {
      await _supabase.from('post_status_history').insert({
        'post_id': postId,
        'changed_by': userId,
        'from_status': null,
        'to_status': 'open',
        'note': 'Post criado pelo usuario.',
      });
    } on PostgrestException catch (e) {
      throw Exception('Erro ao criar historico do post: ${e.message}');
    } catch (e) {
      throw Exception('Erro inesperado ao criar historico do post: $e');
    }
  }

  Future<void> uploadPostImages({
    required int postId,
    required List<PlatformFile> files,
  }) async {
    try {
      final imageFiles = files.where(_isImageFile).toList();
      if (imageFiles.isEmpty) return;

      for (var index = 0; index < imageFiles.length; index++) {
        final file = imageFiles[index];
        final bytes = _extractBytes(file);
        final extension = _fileExtension(file.name);
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_$index.$extension';
        final storagePath = 'posts/$postId/$fileName';

        await _supabase.storage
            .from(_postImagesBucket)
            .uploadBinary(storagePath, bytes, fileOptions: const FileOptions(upsert: false));

        final publicUrl = _supabase.storage.from(_postImagesBucket).getPublicUrl(storagePath);

        await _supabase.from('post_images').insert({
          'post_id': postId,
          'storage_path': publicUrl,
          'position': index + 1,
        });
      }
    } on StorageException catch (e) {
      throw Exception('Erro ao enviar imagem para o storage: ${e.message}');
    } on PostgrestException catch (e) {
      throw Exception('Erro ao salvar imagem do post: ${e.message}');
    } catch (e) {
      throw Exception('Erro inesperado ao salvar imagens do post: $e');
    }
  }

  bool _isImageFile(PlatformFile file) {
    final extension = _fileExtension(file.name);
    return {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(extension);
  }

  String _fileExtension(String name) {
    final parts = name.split('.');
    if (parts.length < 2) return 'bin';
    return parts.last.toLowerCase();
  }

  Uint8List _extractBytes(PlatformFile file) {
    final bytes = file.bytes;
    if (bytes == null) {
      throw Exception('Nao foi possivel ler os bytes do arquivo ${file.name}.');
    }
    return bytes;
  }
}
