import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/application_record.dart';

const _kPrefKey = 'application_records';

class ApplicationProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  List<ApplicationRecord> _records = [];
  String? _currentUserId;

  List<ApplicationRecord> get records => List.unmodifiable(_records);

  bool contains(String serviceId) => _records.any((r) => r.serviceId == serviceId);

  ApplicationRecord? get(String serviceId) =>
      _records.where((r) => r.serviceId == serviceId).firstOrNull;

  void setCurrentUser(String? userId) {
    if (_currentUserId == userId) return;
    _currentUserId = userId;
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kPrefKey) ?? [];
    final localRecords = raw.map((s) => ApplicationRecord.fromJsonString(s)).toList();
    final remoteRecords = await _loadRemoteRecords();
    _records = _mergeRecords(localRecords, remoteRecords);
    _records.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    await _saveLocalOnly();
    await _syncRemote();
    notifyListeners();
  }

  Future<void> add(ApplicationRecord record) async {
    if (contains(record.serviceId)) return;
    _records.insert(0, record);
    await _save();
    notifyListeners();
  }

  Future<void> remove(String serviceId) async {
    _records.removeWhere((r) => r.serviceId == serviceId);
    await _save();
    notifyListeners();
  }

  Future<void> update(ApplicationRecord record) async {
    final idx = _records.indexWhere((r) => r.serviceId == record.serviceId);
    if (idx == -1) return;
    _records[idx] = record;
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    await _saveLocalOnly();
    await _syncRemote();
  }

  Future<void> _saveLocalOnly() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrefKey, _records.map((r) => r.toJsonString()).toList());
  }

  Future<List<ApplicationRecord>> _loadRemoteRecords() async {
    if (_currentUserId == null) return const [];
    try {
      final rows = await _client
          .from('application_records')
          .select('record')
          .eq('user_id', _currentUserId!);
      return rows
          .map((row) {
            final record = row['record'];
            if (record is Map<String, dynamic>) {
              return ApplicationRecord.fromJson(record);
            }
            if (record is Map) {
              return ApplicationRecord.fromJson(Map<String, dynamic>.from(record));
            }
            return null;
          })
          .whereType<ApplicationRecord>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<ApplicationRecord> _mergeRecords(
    List<ApplicationRecord> localRecords,
    List<ApplicationRecord> remoteRecords,
  ) {
    final merged = <String, ApplicationRecord>{};
    for (final record in [...localRecords, ...remoteRecords]) {
      final existing = merged[record.serviceId];
      if (existing == null || record.savedAt.isAfter(existing.savedAt)) {
        merged[record.serviceId] = record;
      }
    }
    return merged.values.toList();
  }

  Future<void> _syncRemote() async {
    if (_currentUserId == null) return;
    try {
      final payload = _records
          .map((r) => {
                'user_id': _currentUserId,
                'service_id': r.serviceId,
                'record': r.toJson(),
                'updated_at': DateTime.now().toIso8601String(),
              })
          .toList();
      await _client.from('application_records').delete().eq('user_id', _currentUserId!);
      if (payload.isNotEmpty) {
        await _client.from('application_records').insert(payload);
      }
    } catch (_) {
      // 원격 동기화 실패 시 로컬 데이터는 유지한다.
    }
  }
}
