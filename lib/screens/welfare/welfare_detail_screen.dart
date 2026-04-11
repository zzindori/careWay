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

          // ── 상세 안내 ──────────────────────────────────
          const SizedBox(height: 12),
          _section(
            title: '상세 안내',
            icon: Icons.article_outlined,
            child: service.detailContent.isNotEmpty
                ? Text(service.detailContent,
                    style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.6))
                : _pendingText(),
          ),

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
