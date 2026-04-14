import 'dart:convert';

class ApplicationRecord {
  final String serviceId;
  final String serviceName;
  final String category;
  final DateTime savedAt;
  String status; // 'saved' | 'preparing' | 'applied'
  String memo;
  final String phone;
  final String address;
  final String? onlineUrl;
  final List<String> docs;
  List<bool> checkedDocs;

  ApplicationRecord({
    required this.serviceId,
    required this.serviceName,
    required this.category,
    required this.savedAt,
    this.status = 'saved',
    this.memo = '',
    this.phone = '',
    this.address = '',
    this.onlineUrl,
    List<String>? docs,
    List<bool>? checkedDocs,
  })  : docs = docs ?? [],
        checkedDocs = checkedDocs ?? List.filled(docs?.length ?? 0, false);

  String get statusLabel {
    switch (status) {
      case 'preparing': return '준비 중';
      case 'applied': return '신청 완료';
      default: return '저장됨';
    }
  }

  int get checkedCount => checkedDocs.where((c) => c).length;

  Map<String, dynamic> toJson() => {
    'serviceId': serviceId,
    'serviceName': serviceName,
    'category': category,
    'savedAt': savedAt.toIso8601String(),
    'status': status,
    'memo': memo,
    'phone': phone,
    'address': address,
    'onlineUrl': onlineUrl,
    'docs': docs,
    'checkedDocs': checkedDocs,
  };

  factory ApplicationRecord.fromJson(Map<String, dynamic> j) => ApplicationRecord(
    serviceId: j['serviceId'] as String,
    serviceName: j['serviceName'] as String,
    category: j['category'] as String? ?? '',
    savedAt: DateTime.parse(j['savedAt'] as String),
    status: j['status'] as String? ?? 'saved',
    memo: j['memo'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    address: j['address'] as String? ?? '',
    onlineUrl: j['onlineUrl'] as String?,
    docs: (j['docs'] as List?)?.map((e) => e as String).toList() ?? [],
    checkedDocs: (j['checkedDocs'] as List?)?.map((e) => e as bool).toList() ?? [],
  );

  String toJsonString() => jsonEncode(toJson());
  factory ApplicationRecord.fromJsonString(String s) => ApplicationRecord.fromJson(jsonDecode(s));
}
