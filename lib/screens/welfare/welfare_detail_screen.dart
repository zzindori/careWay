import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/welfare_service.dart';
import '../../providers/profile_provider.dart';
import '../../config/app_theme.dart';

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
      appBar: AppBar(title: Text(service.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [

          // ── 헤더 배지 ──────────────────────────────────
          Wrap(spacing: 8, runSpacing: 6, children: [
            _badge(service.categoryLabel, categoryColor),
            if (tier == 1) _badge('✓ 즉시 신청 가능', Colors.green),
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

          // ── 원문 안내 ──────────────────────────────────
          const SizedBox(height: 12),
          _buildRawContentCard(service),

          // ── 문의처 ─────────────────────────────────────
          const SizedBox(height: 12),
          _section(
            title: '문의처',
            icon: Icons.phone_outlined,
            child: service.inqPlace.isNotEmpty
                ? Text(service.inqPlace,
                    style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.5))
                : _pendingText(),
          ),

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

  // ─── 원문 안내 카드 ─────────────────────────────────────────

  static const _sectionIcons = <String, IconData>{
    '서비스 개요': Icons.info_outline,
    '지원 대상': Icons.group_outlined,
    '선정 기준': Icons.rule_outlined,
    '지원 혜택': Icons.card_giftcard_outlined,
    '신청 방법': Icons.how_to_reg_outlined,
    '문의처': Icons.phone_outlined,
  };

  static const _sectionColors = <String, Color>{
    '서비스 개요': Color(0xFF1565C0),
    '지원 대상': Color(0xFF2E7D32),
    '선정 기준': Color(0xFF6A1B9A),
    '지원 혜택': Color(0xFFE65100),
    '신청 방법': Color(0xFF00695C),
    '문의처': Color(0xFF37474F),
  };

  List<MapEntry<String, String>> _parseRawSections(String raw) {
    final sections = <MapEntry<String, String>>[];
    final pattern = RegExp(r'\[([^\]]+)\]\n([\s\S]*?)(?=\n\n\[|$)');
    for (final m in pattern.allMatches(raw)) {
      final label = m.group(1)!.trim();
      final content = m.group(2)!.trim();
      if (content.isNotEmpty) sections.add(MapEntry(label, content));
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

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (idx > 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: Color(0xFFEEEEEE)),
            ),
          // 섹션 레이블
          Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3)),
          ]),
          const SizedBox(height: 7),
          // 섹션 내용
          Text(content,
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textPrimary, height: 1.65)),
        ]);
      }).toList(),
    );
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
}
