import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/parent_profile.dart';
import '../models/welfare_service.dart';

class ProfileProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  List<ParentProfile> _profiles = [];
  ParentProfile? _selectedProfile;
  List<WelfareService> _matchedServices = [];
  List<WelfareService> _notMatchedServices = [];
  List<WelfareService> _allServices = [];
  bool _isLoading = false;
  String? _error;

  List<ParentProfile> get profiles => _profiles;
  ParentProfile? get selectedProfile => _selectedProfile;
  List<WelfareService> get matchedServices => _matchedServices;
  List<WelfareService> get notMatchedServices => _notMatchedServices;
  List<WelfareService> get allServices => _allServices;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void selectProfile(ParentProfile profile) {
    _selectedProfile = profile;
    notifyListeners();
  }

  Future<void> loadProfiles() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await _client
          .from('parent_profiles')
          .select()
          .eq('user_id', userId)
          .order('created_at');

      _profiles = (response as List)
          .map((json) => ParentProfile.fromJson(json as Map<String, dynamic>))
          .toList();

      if (_profiles.isNotEmpty && _selectedProfile == null) {
        _selectedProfile = _profiles.first;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addProfile(ParentProfile profile) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _client
          .from('parent_profiles')
          .insert(profile.toJson())
          .select()
          .single();

      final newProfile = ParentProfile.fromJson(response);
      _profiles.add(newProfile);
      _selectedProfile ??= newProfile;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateProfile(ParentProfile profile) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _client
          .from('parent_profiles')
          .update(profile.toJson())
          .eq('id', profile.id!);

      final index = _profiles.indexWhere((p) => p.id == profile.id);
      if (index != -1) {
        _profiles[index] = profile;
        if (_selectedProfile?.id == profile.id) _selectedProfile = profile;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 복지 서비스 매칭 (프로필 조건 기반 필터링)
  Future<void> matchWelfareServices(ParentProfile profile) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_allServices.isEmpty) {
        await loadAllWelfareServices();
      }

      _matchedServices = [];
      _notMatchedServices = [];

      for (final s in _allServices) {
        final reasons = s.getMismatchReasons(profile);
        if (reasons.isEmpty) {
          _matchedServices.add(s);
        } else {
          // 필터 기준이 실제로 설정된 서비스만 미해당에 표시
          final hasRealCriteria = s.minAge > 0 ||
              s.maxIncomeLevel < 10 ||
              s.requiresLtcGrade ||
              s.requiresAlone ||
              s.requiresBasicRecipient;
          if (hasRealCriteria) _notMatchedServices.add(s);
        }
      }

    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 모든 복지 서비스 로드 (캐시)
  Future<void> loadAllWelfareServices() async {
    try {
      final response = await _client.from('welfare_services').select();

      _allServices = (response as List)
          .map((json) => WelfareService.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = e.toString();
      _allServices = [];
    }
  }

  /// 특정 ID의 복지 서비스 조회
  Future<WelfareService?> getWelfareService(String serviceId) async {
    try {
      // 캐시에서 먼저 찾기
      try {
        return _allServices.firstWhere((s) => s.id == serviceId);
      } on StateError {
        // 캐시에 없으면 DB에서 조회
        final response = await _client
            .from('welfare_services')
            .select()
            .eq('id', serviceId)
            .single();

        return WelfareService.fromJson(response);
      }
    } catch (e) {
      _error = e.toString();
      return null;
    }
  }
}
