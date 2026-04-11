import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/parent_profile.dart';
import '../models/welfare_service.dart';

class ProfileProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  List<ParentProfile> _profiles = [];
  ParentProfile? _selectedProfile;
  List<WelfareService> _allServices = [];
  bool _isLoading = false;
  String? _error;

  // 3단계 티어 매칭 결과
  List<WelfareService> _tier1Services = []; // 🔴 지금 바로 신청
  List<WelfareService> _tier2Services = []; // 🟡 등급 신청 후 가능
  List<WelfareService> _tier3Services = []; // 🔵 알아두면 좋아요

  List<ParentProfile> get profiles => _profiles;
  ParentProfile? get selectedProfile => _selectedProfile;
  List<WelfareService> get allServices => _allServices;
  List<WelfareService> get tier1Services => _tier1Services;
  List<WelfareService> get tier2Services => _tier2Services;
  List<WelfareService> get tier3Services => _tier3Services;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // 구 API 호환
  List<WelfareService> get matchedServices => _tier1Services;
  List<WelfareService> get notMatchedServices => _tier3Services;

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

  // 시도명 정규화 (서울특별시 → 서울, 경기도 → 경기)
  static String normalizeRegion(String r) {
    if (r.contains('서울')) return '서울';
    if (r.contains('부산')) return '부산';
    if (r.contains('대구')) return '대구';
    if (r.contains('인천')) return '인천';
    if (r.contains('광주')) return '광주';
    if (r.contains('대전')) return '대전';
    if (r.contains('울산')) return '울산';
    if (r.contains('세종')) return '세종';
    if (r.contains('경기')) return '경기';
    if (r.contains('강원')) return '강원';
    if (r.contains('충북') || r.contains('충청북')) return '충북';
    if (r.contains('충남') || r.contains('충청남')) return '충남';
    if (r.contains('전북') || r.contains('전라북')) return '전북';
    if (r.contains('전남') || r.contains('전라남')) return '전남';
    if (r.contains('경북') || r.contains('경상북')) return '경북';
    if (r.contains('경남') || r.contains('경상남')) return '경남';
    if (r.contains('제주')) return '제주';
    return r;
  }

  /// 3단계 티어 매칭
  Future<void> matchWelfareServices(ParentProfile profile) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_allServices.isEmpty) {
        await loadAllWelfareServices(regionFilter: normalizeRegion(profile.region));
      }

      _tier1Services = [];
      _tier2Services = [];
      _tier3Services = [];

      for (final s in _allServices) {
        final tier = s.getMatchTier(profile);
        if (tier == 1) {
          _tier1Services.add(s);
        } else if (tier == 2) {
          _tier2Services.add(s);
        } else if (tier == 3) {
          _tier3Services.add(s);
        }
        // tier == 0 → 표시 안함
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAllWelfareServices({String? regionFilter}) async {
    try {
      dynamic query = _client.from('welfare_services').select();

      if (regionFilter != null && regionFilter.isNotEmpty) {
        query = query.or('region.eq.,region.eq.전국,region.eq.$regionFilter');
      }

      final response = await query;

      _allServices = (response as List)
          .map((json) => WelfareService.fromJson(json as Map<String, dynamic>))
          .toList();

      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _allServices = [];
    }
  }

  Future<WelfareService?> getWelfareService(String serviceId) async {
    try {
      try {
        return _allServices.firstWhere((s) => s.id == serviceId);
      } on StateError {
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
