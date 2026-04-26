import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/welfare_service.dart';
import '../../models/application_record.dart';
import '../../providers/profile_provider.dart';
import '../../providers/application_provider.dart';
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

  bool _isValidExternalUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return false;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return false;
    return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

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
      appBar: AppBar(
        title: Text(service.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                const Row(children: [
                  Icon(Icons.auto_awesome, size: 15, color: Color(0xFF388E3C)),
                  SizedBox(width: 6),
                  Text('AI 요약',
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

          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE0E6ED)),
            ),
            child: const Row(
              children: [
                Icon(Icons.fact_check_outlined, size: 14, color: AppTheme.textSecondary),
                SizedBox(width: 6),
                Text(
                  '신청 핵심 정보',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // ── 해당 사유 ──────────────────────────────────
          if (matchReasons.isNotEmpty) ...[
            const SizedBox(height: 20),
            _section(
              title: '해당 사유',
              icon: Icons.check_circle_outline,
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
            child: _textOrPending(
              _firstNonEmpty([
                service.targetInfo,
                _extractSection(service.rawContent, ['지원 대상', 'wlfareSprtTrgtCn']),
              ]),
            ),
          ),

          // ── 지원 내용 ──────────────────────────────────
          const SizedBox(height: 12),
          _section(
            title: '지원 내용',
            icon: Icons.card_giftcard_outlined,
            child: _textOrPending(
              _firstNonEmpty([
                (service.benefitInfo.contains('복지로') || service.benefitInfo.length < 10)
                    ? ''
                    : service.benefitInfo,
                _extractSection(service.rawContent, ['지원 혜택', 'wlfareSprtBnftCn', '서비스 개요', 'wlfareInfoOutlCn']),
              ]),
            ),
          ),

          // ── 신청 방법 ──────────────────────────────────
          const SizedBox(height: 12),
          _section(
            title: '신청 방법',
            icon: Icons.how_to_reg_outlined,
            child: service.applmetList.isNotEmpty
                ? _applyMethods(service.applmetList)
                : Builder(
                    builder: (_) {
                      final applyText = _formatCardText(
                        _firstNonEmpty([
                          service.applyPlace,
                          _extractSection(service.rawContent, ['신청 방법', 'aplyMtdDc']),
                        ]),
                      );
                      if (applyText.isEmpty) return _pendingText();
                      return Text(
                        applyText,
                        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.5),
                      );
                    },
                  ),
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
                child: Text(docs, style: const TextStyle(
                    fontSize: 14, color: AppTheme.textPrimary, height: 1.6)),
              ),
            );
          }),

          // ── 문의처 ─────────────────────────────────────
          const SizedBox(height: 12),
          _section(
            title: '문의처',
            icon: Icons.phone_outlined,
            child: service.inqPlace.isNotEmpty
                ? _buildPhoneContent(service.inqPlace, const Color(0xFF37474F))
                : _pendingText(),
          ),

          // ── 원문 안내 ──────────────────────────────────
          const SizedBox(height: 12),
          _buildRawContentCard(service),

          const SizedBox(height: 24),

          // ── 복지로 바로가기 ────────────────────────────
          if (_isValidExternalUrl(service.onlineUrl))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(service.onlineUrl!.trim());
                  if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('복지로에서 자세히 보기'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

          OutlinedButton.icon(
            onPressed: () => _handleApplicationButton(service),
            icon: Icon(context.watch<ApplicationProvider>().contains(service.id)
                ? Icons.assignment_outlined
                : Icons.bookmark_add_outlined),
            label: Text(context.watch<ApplicationProvider>().contains(service.id)
                ? '신청 관리 보기'
                : '신청 관리 추가'),
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

  static const _sectionOrder = <String, int>{
    '지원 대상': 0,
    '선정 기준': 1,
    '지원 혜택': 2,
    '서비스 개요': 3,
    '서비스 요약': 4,
    '신청 방법': 5,
    '신청 서류': 6,
    '문의처': 7,
    '담당 부서': 8,
    '소재지': 9,
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
    final sections = hasRaw ? _parseRawSections(service.rawContent) : const <MapEntry<String, String>>[];
    final sortedSections = [...sections]
      ..sort((a, b) {
        final ai = _sectionOrder[a.key] ?? 999;
        final bi = _sectionOrder[b.key] ?? 999;
        if (ai != bi) return ai.compareTo(bi);
        return a.key.compareTo(b.key);
      });

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
                child: Text('원문 상세 보기',
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
                ? SelectableText(
                    _buildRawTextView(sortedSections),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                      height: 1.6,
                    ),
                  )
                : Text(
                    service.detailContent,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                      height: 1.6,
                    ),
                  ),
          ),
        ],
      ]),
    );
  }

  String _buildRawTextView(List<MapEntry<String, String>> sections) {
    if (sections.isEmpty) return '';
    return sections
        .map((s) => '[${s.key}]\n${_decodeHtmlEntities(s.value.trim())}')
        .join('\n\n');
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

  Future<void> _handleApplicationButton(WelfareService service) async {
    final appProvider = context.read<ApplicationProvider>();
    if (appProvider.contains(service.id)) {
      context.push('/application/${service.id}');
      return;
    }
    // 서류 목록 추출 (rawContent에서 파싱)
    final docsRaw = _extractSection(service.rawContent, ['신청 서류', 'rqutPdFrmCn']);
    final docs = docsRaw.isNotEmpty
        ? docsRaw.split(RegExp(r'\n|,|·|•')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
        : <String>[];

    // 전화번호 추출
    final phoneMatch = RegExp(r'[\d]{2,4}-[\d]{3,4}-[\d]{4}').firstMatch(service.inqPlace);
    final phone = phoneMatch?.group(0) ?? '';

    final record = ApplicationRecord(
      serviceId: service.id,
      serviceName: service.name,
      category: service.category,
      savedAt: DateTime.now(),
      phone: phone,
      address: service.applyPlace,
      onlineUrl: service.onlineUrl,
      docs: docs,
      checkedDocs: List.filled(docs.length, false),
    );
    await appProvider.add(record);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('신청 관리에 추가되었습니다.'),
        action: SnackBarAction(label: '보기', onPressed: () => context.push('/application/${service.id}')),
        duration: const Duration(seconds: 3),
      ),
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
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _textOrPending(String text) {
    final formatted = _formatCardText(text);
    return formatted.isNotEmpty
        ? Text(formatted, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.6))
        : _pendingText();
  }

  String _firstNonEmpty(List<String> values) {
    for (final v in values) {
      final t = v.trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  String _formatCardText(String raw) {
    var text = _decodeHtmlEntities(raw).replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty) return '';

    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    final lines = text.split('\n');
    final out = <String>[];
    final numbered = RegExp(r'^\s*(\d+[\)\.])\s*(.+)$');
    final bullet = RegExp(r'^\s*[-•·]\s*(.+)$');
    bool previousWasListItem = false;

    for (final line in lines) {
      final ln = line.trim();
      if (ln.isEmpty) {
        if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
        previousWasListItem = false;
        continue;
      }

      final n = numbered.firstMatch(ln);
      if (n != null) {
        final marker = n.group(1)!; // 1) / 1. 형태 그대로 유지
        out.add('$marker ${n.group(2)}');
        previousWasListItem = true;
        continue;
      }

      final b = bullet.firstMatch(ln);
      if (b != null) {
        out.add('• ${b.group(1)}');
        previousWasListItem = true;
        continue;
      }

      // 번호/불릿 다음 줄은 같은 항목의 continuation으로 들여쓰기
      if (previousWasListItem) {
        // 고정 공백 대신 NBSP를 써서 들여쓰기가 눈에 보이게 유지되도록 한다.
        out.add('\u00A0\u00A0\u00A0$ln');
      } else {
        out.add(ln);
      }
    }

    final joined = out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return joined;
  }

  String _decodeHtmlEntities(String text) {
    if (text.isEmpty) return text;
    var out = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&middot;', '·')
        .replaceAll('&gt;', '>')
        .replaceAll('&lt;', '<')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      if (code == null) return m.group(0)!;
      return String.fromCharCode(code);
    });

    out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      if (code == null) return m.group(0)!;
      return String.fromCharCode(code);
    });

    return out;
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
        final name = _formatCardText(m['method'] ?? '');
        final desc = _formatCardText(m['description'] ?? '');
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.arrow_right, color: AppTheme.primary, size: 18),
            ),
            const SizedBox(width: 4),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (name.isNotEmpty)
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    height: 1.5,
                  ),
                ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    height: 1.6,
                  ),
                ),
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
