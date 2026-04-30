import 'package:supabase_flutter/supabase_flutter.dart';

class AgencyCityOption {
  const AgencyCityOption({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;
}

class AgencyOption {
  const AgencyOption({
    required this.id,
    required this.cityId,
    required this.name,
    required this.type,
    required this.contactEmail,
  });

  final int id;
  final int cityId;
  final String name;
  final String type;
  final String contactEmail;
}

class ManagedAgencyProfile {
  const ManagedAgencyProfile({
    required this.id,
    required this.cityId,
    required this.cityName,
    required this.name,
    required this.type,
    required this.contactEmail,
    required this.role,
    required this.isActive,
  });

  final int id;
  final int cityId;
  final String cityName;
  final String name;
  final String type;
  final String contactEmail;
  final String role;
  final bool isActive;
}

class AgencyProfileRequest {
  const AgencyProfileRequest({
    required this.id,
    required this.cityId,
    required this.cityName,
    required this.agencyName,
    required this.agencyType,
    required this.institutionalEmail,
    this.requesterRole,
    required this.proofSummary,
    this.proofLinks,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final int cityId;
  final String cityName;
  final String agencyName;
  final String agencyType;
  final String institutionalEmail;
  final String? requesterRole;
  final String proofSummary;
  final String? proofLinks;
  final String status;
  final DateTime createdAt;
}

class AgencyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<AgencyCityOption>> fetchCities() async {
    try {
      final response = await _supabase.from('cities').select('id, name').order('name');

      return (response as List<dynamic>)
          .map(
            (item) => AgencyCityOption(
              id: (item['id'] as num).toInt(),
              name: item['name'] as String,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar cidades institucionais: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar cidades institucionais.');
    }
  }

  Future<List<AgencyOption>> fetchAgenciesByCity(int cityId) async {
    try {
      final response = await _supabase
          .from('public_agencies')
          .select('id, city_id, name, type, contact_email')
          .eq('city_id', cityId)
          .order('name');

      return (response as List<dynamic>)
          .map(
            (item) => AgencyOption(
              id: (item['id'] as num).toInt(),
              cityId: (item['city_id'] as num).toInt(),
              name: item['name'] as String,
              type: item['type'] as String,
              contactEmail: item['contact_email'] as String,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar secretarias da cidade: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar secretarias da cidade.');
    }
  }

  Future<List<ManagedAgencyProfile>> fetchManagedAgencies(String userId) async {
    try {
      final response = await _supabase
          .from('agency_users')
          .select('''
            role,
            is_active,
            public_agencies!agency_users_agency_id_fkey(
              id,
              city_id,
              name,
              type,
              contact_email,
              cities(name)
            )
          ''')
          .eq('user_id', userId)
          .order('agency_id');

      return (response as List<dynamic>)
          .map((item) {
            final agency = item['public_agencies'] as Map<String, dynamic>?;
            if (agency == null) return null;
            final city = agency['cities'] as Map<String, dynamic>?;

            return ManagedAgencyProfile(
              id: (agency['id'] as num).toInt(),
              cityId: (agency['city_id'] as num).toInt(),
              cityName: (city?['name'] as String?) ?? 'Cidade',
              name: agency['name'] as String,
              type: agency['type'] as String,
              contactEmail: agency['contact_email'] as String,
              role: (item['role'] as String?) ?? 'agent',
              isActive: item['is_active'] as bool? ?? false,
            );
          })
          .whereType<ManagedAgencyProfile>()
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar seus perfis institucionais: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar seus perfis institucionais.');
    }
  }

  Future<List<AgencyProfileRequest>> fetchOwnAgencyRequests(String userId) async {
    try {
      final response = await _supabase
          .from('agency_profile_requests')
          .select('''
            id,
            city_id,
            agency_name,
            agency_type,
            institutional_email,
            requester_role,
            proof_summary,
            proof_links,
            status,
            created_at,
            cities(name)
          ''')
          .eq('requester_user_id', userId)
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((item) {
            final city = item['cities'] as Map<String, dynamic>?;
            return AgencyProfileRequest(
              id: (item['id'] as num).toInt(),
              cityId: (item['city_id'] as num).toInt(),
              cityName: (city?['name'] as String?) ?? 'Cidade',
              agencyName: item['agency_name'] as String,
              agencyType: item['agency_type'] as String,
              institutionalEmail: item['institutional_email'] as String,
              requesterRole: item['requester_role'] as String?,
              proofSummary: item['proof_summary'] as String,
              proofLinks: item['proof_links'] as String?,
              status: item['status'] as String,
              createdAt: DateTime.parse(item['created_at'] as String),
            );
          })
          .toList();
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar suas solicitações institucionais: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao carregar suas solicitações institucionais.');
    }
  }

  Future<void> createAgencyProfileRequest({
    required int cityId,
    required String name,
    required String type,
    required String contactEmail,
    String? requesterRole,
    required String proofSummary,
    String? proofLinks,
  }) async {
    try {
      await _supabase.rpc(
        'create_agency_profile_request',
        params: {
          'target_city_id': cityId,
          'agency_name': name.trim(),
          'agency_type': type.trim(),
          'institutional_email': contactEmail.trim(),
          'requester_role': requesterRole?.trim(),
          'proof_summary': proofSummary.trim(),
          'proof_links': proofLinks?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw Exception('Erro ao enviar solicitação institucional: ${error.message}');
    } catch (_) {
      throw Exception('Erro inesperado ao enviar solicitação institucional.');
    }
  }
}
