import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/welfare_service.dart';
import '../../providers/profile_provider.dart';
import '../../config/app_theme.dart';
import '../../config/secrets.dart';

class WelfareDetailScreen extends StatefulWidget {
  final String serviceId;
  const WelfareDetailScreen({super.key, required this.serviceId});

  @override
  State<WelfareDetailScreen> createState() => _WelfareDetailScreenState();
}

class _WelfareDetailScreenState extends State<WelfareDetailScreen> {
  WelfareService? _service;
  bool _isLoading = true;
  String? _error;
  bool _detailExpanded = false;
  List<Map<String, String>> _providers = [];

  @override
  void initState() {
    super.initState();
    _loadService();
  }

  Future<void> _loadService() async {
    setState(() { _isLoading = true; _error = null; });
    final service = await context.read<ProfileProvider>().getWelfareService(widget.serviceId);
    if (!mounted) return;
    setState(() {
      _service = service;
      _isLoading = false;
      if (service == null) _error = '서비스를 찾을 수 없습니다.';
    });
    if (service != null) _loadProviders(service);
  }

  Future<void> _loadProviders(WelfareService service) async {
    if (kSocialServiceApiKey.isEmpty) return;
    try {
      final regionParam = Uri.encodeComponent(service.region.isNotEmpty ? service.region : '');
      final uri = Uri.parse(
        'https://api.socialservice.or.kr:444/api/service/provider/providerList'
        '?sigunguNm=$regionParam&searchIdx=0&pageSize=10'
        '&serviceKey=${Uri.encodeComponent(kSocialServiceApiKey)}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['data'] as List?)
            ?.map((p) => {
                  'name': (p['provNm'] as String?) ?? '',
                  'addr': (p['addr'] as String?) ?? '',
                  'phone': (p['telNo'] as String?) ?? '',
                })
            .where((p) => p['name']!.isNotEmpty)
            .cast<Map<String, String>>()
            .toList();
        if (mounted && list != null) setState(() => _providers = list);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null || _service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('서비스 상세')),
        body: Center(child: Text(_error ?? '서비스를 찾을 수 없습니다.',
            style: const TextStyle(color: AppTheme.textSecondary))),
      );
    }
    final profile = context.read<ProfileProvider>().selectedProfile;
    return _buildDetail(context, _service!, profile);
  }

  Widget _buildDetail(BuildContext context, WelfareService service, profile) {
    final categoryColor = AppTheme.categoryColors[service.category] ?? AppTheme.primary;
    final matchReasons = profile != null ? service.getMatchReasons(profile) : <String>[];
    final tier = profile != null ? service.getMatchTier(profile) : -1;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () => _showAdminSheet(service),
          child: Text(service.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          // ── 헤더 배지 ──────────────────────────────────
          Wrap(spacing: 8, runSpacing: 6, children: [
            _badge(service.categoryLabel, categoryColor),
            if (tier == 1) _badge('✓ 우선 확인', Colors.green),
            if (tier == 2) _badge('★ 등급 후 신청 가능', const Color(0xFFF57C00)),
            if (service.isDeadlineSoon)
              _badge('D-${service.deadline!.difference(DateTime.now()).inDays} 마감 임박', AppTheme.warning),
          ]),
          const SizedBox(height: 16),

          // ── 개요 ───────────────────────────────────────
          if (service.description.isNotEmpty)
            Text(service.description,
                style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary, height: 1.6)),

          // ── AI 요약 ──────────────────────────────────
          if (service.aiSummary.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.auto_awesome, size: 15, color: Color(0xFF388E3C)),
                  const SizedBox(width: 6),
                  const Text('AI 요약',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF388E3C), fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Text(service.aiSummary,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF1B5E20), height: 1.65)),
              ]),
            ),
          ],

          // ── 해당 사유 ──────────────────────────────────
          if (matchReasons.isNotEmpty) ...[
            const SizedBox(height: 20),
            _section(
              title: '해당 사유',
              icon: Icons.check_circle_outline,
              iconColor: Colors.green,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: matchReasons.map((r) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
                  ),
                  child: Text(r, style: const TextStyle(
                      fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                )).toList(),
              ),
            ),
          ],

          // ── 지원 대상 ──────────────────────────────────
          const SizedBox(height: 16),
          _section(
            title: '지원 대상',
            icon: Icons.group_outlined,
            child: _textOrPending(service.targetInfo),
          ),

          // ── 지원 내용 ──────────────────────────────────
          const SizedBox(height: 12),
          _section(
            title: '지원 내용',
            icon: Icons.card_giftcard_outlined,
            child: _textOrPending(
              (service.benefitInfo.contains('복지로') || service.benefitInfo.length < 10)
                  ? '' : service.benefitInfo,
            ),
          ),

          // ── 신청 방법 ──────────────────────────────────
          const SizedBox(height: 12),
          _section(
            title: '신청 방법',
            icon: Icons.how_to_reg_outlined,
            child: service.applmetList.isNotEmpty
                ? _applyMethods(service.applmetList)
                : service.applyPlace.isNotEmpty
                    ? Text(service.applyPlace,
                        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.5))
                    : _pendingText(),
          ),

          // ── 신청 서류 ──────────────────────────────────
          Builder(builder: (_) {
            final docs = _extractSection(service.rawContent, ['신청 서류', 'rqutPdFrmCn']);
            if (docs.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _section(
                title: '신청 서류',
                icon: Icons.folder_outlined,
                iconColor: const Color(0xFF4527A0),
                child: Text(docs, style: const TextStyle(
                    fontSize: 14, color: AppTheme.textPrimary, height: 1.6)),
              ),
            );
          }),

          // ── 원문 안내 ──────────────────────────────────
          const SizedBox(height: 12),
          _buildRawContentCard(service),

          // ── 문의처 ─────────────────────────────────────
          const SizedBox(height: 12),
          _section(
            title: '문의처',
            icon: Icons.phone_outlined,
            child: service.inqPlace.isNotEmpty
                ? _buildPhoneContent(service.inqPlace, const Color(0xFF37474F))
                : _pendingText(),
          ),

          // ── 우리 지역 제공기관 ──────────────────────────
          if (_providers.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildProvidersSection(),
          ],

          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('신청 현황에 추가'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              foregroundColor: AppTheme.primary,
              side: const BorderSide(color: AppTheme.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── 우리 지역 제공기관 ────────────────────────────────────────

  Widget _buildProvidersSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          const Text('우리 지역 제공기관',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        ..._providers.map(_buildProviderCard),
      ]),
    );
  }

  Widget _buildProviderCard(Map<String, String> p) {
    final name = p['name'] ?? '';
    final addr = p['addr'] ?? '';
    final phone = p['phone'] ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          const Icon(Icons.business_outlined, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              if (addr.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(addr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ]),
          ),
          if (phone.isNotEmpty)
            GestureDetector(
              onTap: () => _confirmCall(phone),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.phone, size: 14, color: AppTheme.primary),
                  const SizedBox(width: 4),
                  Text('연결',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  // ─── 원문 안내 카드 ─────────────────────────────────────────

  static const _sectionIcons = <String, IconData>{
    '서비스 개요': Icons.info_outline,
    '지원 대상': Icons.group_outlined,
    '선정 기준': Icons.rule_outlined,
    '지원 혜택': Icons.card_giftcard_outlined,
    '신청 방법': Icons.how_to_reg_outlined,
    '신청 서류': Icons.folder_outlined,
    '문의처': Icons.phone_outlined,
    '담당 부서': Icons.business_outlined,
    '소재지': Icons.location_on_outlined,
  };

  static const _sectionColors = <String, Color>{
    '서비스 개요': Color(0xFF1565C0),
    '지원 대상': Color(0xFF2E7D32),
    '선정 기준': Color(0xFF6A1B9A),
    '지원 혜택': Color(0xFFE65100),
    '신청 방법': Color(0xFF00695C),
    '신청 서류': Color(0xFF4527A0),
    '문의처': Color(0xFF37474F),
    '담당 부서': Color(0xFF455A64),
    '소재지': Color(0xFF00695C),
  };

  // 표시할 섹션만 정의 (raw 필드명 → 표시 이름, null이면 숨김)
  static const _labelMap = <String, String>{
    '서비스 개요': '서비스 개요',
    '지원 대상': '지원 대상',
    '선정 기준': '선정 기준',
    '지원 혜택': '지원 혜택',
    '신청 방법': '신청 방법',
    '신청 서류': '신청 서류',
    '문의처': '문의처',
    'rqutPdFrmCn': '신청 서류',       // 구버전 배치 데이터 호환
    'bizChrDeptNm': '담당 부서',
    'addr': '소재지',
    'wlfareSprtTrgtSlcrCn': '선정 기준',  // 선정 기준 없을 때 폴백
  };

  /// rawContent에서 특정 레이블의 내용을 추출 (여러 레이블 중 첫 번째 매칭)
  String _extractSection(String raw, List<String> labels) {
    final pattern = RegExp(r'\[([^\]]+)\]\n([\s\S]*?)(?=\n\n\[|$)');
    for (final m in pattern.allMatches(raw)) {
      final label = m.group(1)!.trim();
      if (labels.contains(label)) {
        final content = m.group(2)!.trim();
        if (content.isNotEmpty) return content;
      }
    }
    return '';
  }

  List<MapEntry<String, String>> _parseRawSections(String raw) {
    final sections = <MapEntry<String, String>>[];
    final usedLabels = <String>{};
    final pattern = RegExp(r'\[([^\]]+)\]\n([\s\S]*?)(?=\n\n\[|$)');
    for (final m in pattern.allMatches(raw)) {
      final rawLabel = m.group(1)!.trim();
      final content = m.group(2)!.trim();
      final displayLabel = _labelMap[rawLabel];
      if (displayLabel == null || content.isEmpty) continue;
      if (usedLabels.contains(displayLabel)) continue; // 중복 섹션 스킵
      usedLabels.add(displayLabel);
      sections.add(MapEntry(displayLabel, content));
    }
    return sections;
  }

  Widget _buildRawContentCard(WelfareService service) {
    final hasRaw = service.rawContent.isNotEmpty;
    final hasDetail = service.detailContent.isNotEmpty;
    if (!hasRaw && !hasDetail) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 헤더 (탭으로 접기/펼치기)
        InkWell(
          onTap: () => setState(() => _detailExpanded = !_detailExpanded),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.article_outlined, size: 16, color: AppTheme.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('원문 전체 보기',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600)),
              ),
              Icon(
                _detailExpanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: AppTheme.textSecondary,
              ),
            ]),
          ),
        ),

        // 펼쳐졌을 때 내용
        if (_detailExpanded) ...[
          const Divider(height: 1, color: AppTheme.divider),
          Padding(
            padding: const EdgeInsets.all(16),
            child: hasRaw
                ? _buildParsedSections(_parseRawSections(service.rawContent))
                : Text(service.detailContent,
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textPrimary, height: 1.6)),
          ),
        ],
      ]),
    );
  }

  Widget _buildParsedSections(List<MapEntry<String, String>> sections) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.asMap().entries.map((entry) {
        final idx = entry.key;
        final label = entry.value.key;
        final content = entry.value.value;
        final color = _sectionColors[label] ?? AppTheme.primary;
        final icon = _sectionIcons[label] ?? Icons.chevron_right;

        return Padding(
          padding: EdgeInsets.only(top: idx > 0 ? 10 : 0),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 레이블 헤더
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                ),
                child: Row(children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3)),
                ]),
              ),
              // 내용
              Padding(
                padding: const EdgeInsets.all(12),
                child: label == '문의처'
                    ? _buildPhoneContent(content, color)
                    : Text(content,
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textPrimary, height: 1.65)),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPhoneContent(String content, Color color) {
    final phoneRegex = RegExp(r'[\d]{2,4}-[\d]{3,4}-[\d]{4}');
    final phones = phoneRegex.allMatches(content).map((m) => m.group(0)!).toList();

    if (phones.isEmpty) {
      return Text(content,
          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.65));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: phones.map((phone) => GestureDetector(
        onTap: () => _confirmCall(phone),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.phone, size: 14, color: color),
            const SizedBox(width: 6),
            Text(phone,
                style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      )).toList(),
    );
  }

  Future<void> _confirmCall(String phone) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('전화 연결'),
        content: Text('$phone\n으로 전화하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('전화하기'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final uri = Uri(scheme: 'tel', path: phone);
      if (await canLaunchUrl(uri)) launchUrl(uri);
    }
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
    Color? iconColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: iconColor ?? AppTheme.primary),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _textOrPending(String text) {
    return text.trim().isNotEmpty
        ? Text(text, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.6))
        : _pendingText();
  }

  Widget _pendingText() {
    return Row(children: [
      Icon(Icons.hourglass_empty, size: 14, color: Colors.grey.shade400),
      const SizedBox(width: 6),
      Text('정보 수집 중', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
    ]);
  }

  Widget _applyMethods(List<Map<String, String>> methods) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: methods.map((m) {
        final name = m['method'] ?? '';
        final desc = m['description'] ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.arrow_right, color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 4),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (name.isNotEmpty)
                Text(name, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary, height: 1.5)),
              ],
            ])),
          ]),
        );
      }).toList(),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  // ─── 어드민 바텀시트 ───────────────────────────────────────

  void _showAdminSheet(WelfareService service) {
    final ageGroups = [
      ('unknown', '미분류'),
      ('elderly', '노년'),
      ('adult', '성인'),
      ('child', '아동'),
      ('veteran', '보훈'),
      ('disabled', '장애'),
      ('all', '전체'),
    ];

    String targetAge = service.targetAgeGroup;
    String region = service.region;
    int? minAge = service.minAge > 0 ? service.minAge : null;
    int maxIncome = service.maxIncomeLevel;
    bool ltcGrade = service.requiresLtcGrade;
    bool alone = service.requiresAlone;
    bool basic = service.requiresBasicRecipient;
    bool veteran = service.requiresVeteran;
    bool disability = service.requiresDisability;
    String summary = service.aiSummary;

    final summaryCtrl = TextEditingController(text: summary);
    final minAgeCtrl = TextEditingController(text: minAge?.toString() ?? '');
    bool aiLoading = false;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, sc) => Column(children: [
            // 핸들
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Icon(Icons.admin_panel_settings, size: 18, color: Colors.deepPurple),
                const SizedBox(width: 6),
                const Expanded(child: Text('어드민 수정',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.deepPurple))),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(controller: sc, padding: const EdgeInsets.all(16), children: [

                // ── AI 전체 자동 분류 ───────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF388E3C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: aiLoading ? null : () async {
                      setSt(() => aiLoading = true);
                      try {
                        final raw = service.rawContent.isNotEmpty
                            ? service.rawContent.substring(0, service.rawContent.length.clamp(0, 2500))
                            : '';
                        final prompt = '''당신은 한국 복지 서비스 분류 전문가입니다.
아래 복지 서비스를 분석하여 JSON 형식으로만 응답해주세요. 마크다운 없이 순수 JSON만 출력하세요.

서비스명: ${service.name}
지원 대상: ${service.targetInfo}
지원 혜택: ${service.benefitInfo}
${raw.isNotEmpty ? '원문:\n$raw' : ''}

반환할 JSON 형식:
{
  "target_age_group": "elderly",  // unknown/elderly/adult/child/veteran/disabled/all 중 하나
  "region": "전국",  // 전국/서울/부산/대구/인천/광주/대전/울산/세종/경기/강원/충북/충남/전북/전남/경북/경남/제주 중 하나
  "min_age": null,  // 최소 신청 나이 (숫자 또는 null)
  "max_income_level": 10,  // 소득분위 1~10 (제한 없으면 10)
  "requires_ltc_grade": false,  // 장기요양등급 필요 여부
  "requires_alone": false,  // 독거 필요 여부
  "requires_basic_recipient": false,  // 기초생활수급자 필요 여부
  "requires_veteran": false,  // 보훈대상자 필요 여부
  "requires_disability": false,  // 장애인 필요 여부
  "ai_summary": "..."  // 자녀가 부모님 혜택을 찾을 때 바로 이해할 수 있는 2~3문장 요약
}''';

                        final res = await http.post(
                          Uri.parse(
                            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$kGeminiApiKey',
                          ),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'contents': [{'parts': [{'text': prompt}]}],
                            'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 600},
                          }),
                        );
                        if (res.statusCode == 200) {
                          final data = jsonDecode(res.body);
                          var text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '';
                          // 마크다운 코드블럭 제거
                          text = text.replaceAll(RegExp(r'```json|```'), '').trim();
                          // 주석 제거 (// ...)
                          text = text.replaceAll(RegExp(r'//[^\n]*'), '').trim();
                          final j = jsonDecode(text) as Map<String, dynamic>;
                          setSt(() {
                            targetAge = j['target_age_group'] as String? ?? targetAge;
                            region = j['region'] as String? ?? region;
                            minAge = j['min_age'] as int?;
                            maxIncome = (j['max_income_level'] as int?) ?? maxIncome;
                            ltcGrade = j['requires_ltc_grade'] as bool? ?? ltcGrade;
                            alone = j['requires_alone'] as bool? ?? alone;
                            basic = j['requires_basic_recipient'] as bool? ?? basic;
                            veteran = j['requires_veteran'] as bool? ?? veteran;
                            disability = j['requires_disability'] as bool? ?? disability;
                            final s = j['ai_summary'] as String? ?? '';
                            if (s.isNotEmpty) {
                              summaryCtrl.text = s;
                              summary = s;
                            }
                            minAgeCtrl.text = minAge?.toString() ?? '';
                          });
                        }
                      } catch (_) {}
                      setSt(() => aiLoading = false);
                    },
                    icon: aiLoading
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(aiLoading ? 'AI 분석 중...' : 'AI 전체 자동 분류',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 4),
                const Text('분류 후 아래에서 수동으로 수정 가능합니다',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),

                // target_age_group
                _adminLabel('대상 연령'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6,
                  children: ageGroups.map((g) {
                    final sel = targetAge == g.$1;
                    return ChoiceChip(
                      label: Text(g.$2),
                      selected: sel,
                      onSelected: (_) => setSt(() => targetAge = g.$1),
                      selectedColor: Colors.deepPurple.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: sel ? Colors.deepPurple : AppTheme.textSecondary,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                        fontSize: 13,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // region
                _adminLabel('지역'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: [
                    '전국','서울','부산','대구','인천','광주','대전','울산','세종',
                    '경기','강원','충북','충남','전북','전남','경북','경남','제주',
                  ].map((r) {
                    final sel = region == r;
                    return ChoiceChip(
                      label: Text(r, style: const TextStyle(fontSize: 12)),
                      selected: sel,
                      onSelected: (_) => setSt(() => region = r),
                      selectedColor: Colors.deepPurple.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: sel ? Colors.deepPurple : AppTheme.textSecondary,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // min_age
                _adminLabel('최소 나이 (없으면 빈칸)'),
                const SizedBox(height: 6),
                TextField(
                  controller: minAgeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _adminInputDeco('예: 65'),
                  onChanged: (v) => minAge = int.tryParse(v),
                ),
                const SizedBox(height: 16),

                // max_income_level
                _adminLabel('최대 소득분위: $maxIncome분위'),
                Slider(
                  value: maxIncome.toDouble(),
                  min: 1, max: 10, divisions: 9,
                  activeColor: Colors.deepPurple,
                  label: '$maxIncome분위',
                  onChanged: (v) => setSt(() => maxIncome = v.round()),
                ),
                const SizedBox(height: 8),

                // 스위치들
                _adminSwitch('장기요양등급 필요', ltcGrade, (v) => setSt(() => ltcGrade = v)),
                _adminSwitch('독거 필요', alone, (v) => setSt(() => alone = v)),
                _adminSwitch('기초수급자 필요', basic, (v) => setSt(() => basic = v)),
                _adminSwitch('보훈 대상자', veteran, (v) => setSt(() => veteran = v)),
                _adminSwitch('장애인', disability, (v) => setSt(() => disability = v)),
                const SizedBox(height: 16),

                // ai_summary
                _adminLabel('AI 요약'),
                const SizedBox(height: 6),
                TextField(
                  controller: summaryCtrl,
                  maxLines: 4,
                  decoration: _adminInputDeco('AI 생성 후 수동 수정 가능'),
                  onChanged: (v) => summary = v,
                ),
                const SizedBox(height: 24),

                // 저장 버튼
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: saving ? null : () async {
                      setSt(() => saving = true);
                      try {
                        await Supabase.instance.client
                            .from('welfare_services')
                            .update({
                              'target_age_group': targetAge,
                              'region': region,
                              'min_age': minAge,
                              'max_income_level': maxIncome,
                              'requires_ltc_grade': ltcGrade,
                              'requires_alone': alone,
                              'requires_basic_recipient': basic,
                              'requires_veteran': veteran,
                              'requires_disability': disability,
                              'ai_summary': summaryCtrl.text.trim(),
                              'filter_updated_at': DateTime.now().toIso8601String(),
                            })
                            .eq('id', service.id);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          // 캐시 무시하고 DB에서 직접 재조회
                          final fresh = await Supabase.instance.client
                              .from('welfare_services')
                              .select()
                              .eq('id', service.id)
                              .single();
                          if (mounted) {
                            setState(() => _service = WelfareService.fromJson(fresh));
                          }
                        }
                      } catch (e) {
                        setSt(() => saving = false);
                      }
                    },
                    child: saving
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('저장', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 16),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _adminLabel(String text) => Text(text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textSecondary));

  Widget _adminSwitch(String label, bool value, ValueChanged<bool> onChanged) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary))),
      Switch(value: value, onChanged: onChanged, activeColor: Colors.deepPurple),
    ]),
  );

  InputDecoration _adminInputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
  );
}
