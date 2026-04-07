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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('서비스 상세')),
        body: Center(child: Text(_error ?? '서비스를 찾을 수 없습니다.',
            style: const TextStyle(color: AppTheme.textSecondary))),
      );
    }
    return _buildDetail(context, _service!);
  }

  Widget _buildDetail(BuildContext context, WelfareService service) {
    return Scaffold(
      appBar: AppBar(title: Text(service.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 배지
          Row(children: [
            _buildCategoryBadge(service),
            const SizedBox(width: 8),
            _buildDifficultyBadge(service),
            if (service.isDeadlineSoon) ...[
              const SizedBox(width: 8),
              _buildDeadlineBadge(service),
            ],
          ]),
          const SizedBox(height: 16),
          // 개요
          Text(
            service.description,
            style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary, height: 1.6),
          ),

          // 지원 대상
          if (service.targetInfo.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildInfoSection('지원 대상', service.targetInfo, Icons.group_outlined),
          ],

          // 지원 내용
          if (service.benefitInfo.isNotEmpty &&
              !service.benefitInfo.contains('복지로') &&
              service.benefitInfo.length >= 10) ...[
            const SizedBox(height: 16),
            _buildInfoSection('지원 내용', service.benefitInfo, Icons.card_giftcard_outlined),
          ],

          // 상세 내용 (배치 수집)
          if (service.detailContent.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildInfoSection('상세 내용', service.detailContent, Icons.article_outlined),
          ],

          // 신청 방법 (배치 수집)
          if (service.applmetList.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildApplyMethods(service.applmetList),
          ] else if (service.applyPlace.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildInfoSection('신청처', service.applyPlace, Icons.location_on_outlined),
          ],

          // 문의처 (배치 수집)
          if (service.inqPlace.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildInfoSection('문의처', service.inqPlace, Icons.phone_outlined),
          ],

          const SizedBox(height: 32),
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

  Widget _buildApplyMethods(List<Map<String, String>> methods) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.how_to_reg_outlined, color: AppTheme.primary, size: 20),
          SizedBox(width: 8),
          Text('신청 방법', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        ]),
        const SizedBox(height: 12),
        ...methods.map((m) {
          final name = m['method'] ?? '';
          final desc = m['description'] ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.arrow_right, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 4),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(desc, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.5)),
                ],
              ])),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _buildInfoSection(String title, String content, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppTheme.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(content, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.5)),
        ])),
      ]),
    );
  }

  Widget _buildCategoryBadge(WelfareService service) {
    final color = AppTheme.categoryColors[service.category] ?? AppTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(service.categoryLabel, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildDifficultyBadge(WelfareService service) {
    final colors = [Colors.green, Colors.orange, Colors.red];
    final color = colors[(service.difficulty - 1).clamp(0, 2)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text('신청 ${service.difficultyLabel}', style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Widget _buildDeadlineBadge(WelfareService service) {
    final days = service.deadline!.difference(DateTime.now()).inDays;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppTheme.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text('D-$days 마감 임박', style: const TextStyle(color: AppTheme.warning, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
