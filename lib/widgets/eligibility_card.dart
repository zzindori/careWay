import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/parent_profile.dart';
import '../providers/welfare_standards_provider.dart';
import '../providers/profile_provider.dart';
import '../config/app_theme.dart';

class EligibilityCard extends StatelessWidget {
  final ParentProfile profile;
  const EligibilityCard({super.key, required this.profile});

  void _navigateToService(BuildContext context, String keyword) {
    final services = context.read<ProfileProvider>().allServices;
    try {
      final svc = services.firstWhere(
        (s) => s.name.contains(keyword) || s.targetInfo.contains(keyword),
      );
      context.push('/welfare/${svc.id}');
    } catch (_) {
      context.push('/welfare');
    }
  }

  @override
  Widget build(BuildContext context) {
    final std = context.watch<WelfareStandardsProvider>();
    if (!std.isLoaded) return const SizedBox.shrink();

    final age = profile.age;
    final pension = std.checkBasicPension(age, profile.incomeLevel, false);
    final checkup = std.checkHealthCheckup(profile.birthYear);
    final ltc = std.getLtcBenefit(profile.ltcGrade);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.verified_user_outlined, size: 18, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text('${profile.name}님 예상 혜택',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          const Spacer(),
          Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
        ]),
        const SizedBox(height: 12),

        _buildRow(context, '기초연금', pension, '기초연금'),
        const SizedBox(height: 8),

        if (profile.hasLtcGrade && ltc != null) ...[
          _buildLtcRow(context, ltc),
          const SizedBox(height: 8),
        ] else if (profile.hasLtcGrade) ...[
          _buildRow(context, '장기요양 서비스',
              EligibilityResult.eligible('등급 보유 - 서비스 이용 가능'), '장기요양'),
          const SizedBox(height: 8),
        ],

        _buildRow(context, '건강검진 (${DateTime.now().year}년)', checkup, '건강검진'),

        if (profile.isBasicRecipient) ...[
          const SizedBox(height: 8),
          _buildRow(context, '기초생활수급',
              EligibilityResult.eligible('수급자 전용 복지 추가 혜택 있음'), '기초생활'),
        ],

        if (profile.liveAlone) ...[
          const SizedBox(height: 8),
          _buildRow(context, '독거노인 서비스',
              EligibilityResult.eligible('노인맞춤돌봄, 응급안전안심 등 대상'), '독거'),
        ],
      ]),
    );
  }

  Widget _buildRow(BuildContext context, String label, EligibilityResult result, String keyword) {
    final (icon, color, bg) = switch (result.status) {
      EligibilityStatus.eligible    => (Icons.check_circle, Colors.green.shade600, Colors.green.shade50),
      EligibilityStatus.unknown     => (Icons.help_outline, Colors.orange.shade600, Colors.orange.shade50),
      EligibilityStatus.notEligible => (Icons.cancel_outlined, Colors.grey.shade400, Colors.grey.shade100),
    };

    return GestureDetector(
      onTap: () => _navigateToService(context, keyword),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            Text(result.reason, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.85), height: 1.3)),
          ])),
          Icon(Icons.arrow_forward_ios, size: 11, color: color.withValues(alpha: 0.5)),
        ]),
      ),
    );
  }

  Widget _buildLtcRow(BuildContext context, ltc) {
    return GestureDetector(
      onTap: () => _navigateToService(context, '장기요양'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.elderly, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('장기요양 ${ltc.gradeName}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
            Text('${ltc.monthlyLimitLabel} · ${ltc.services.take(3).join(', ')} 등',
                style: TextStyle(fontSize: 11, color: AppTheme.primary.withValues(alpha: 0.85), height: 1.3)),
          ])),
          Icon(Icons.arrow_forward_ios, size: 11, color: AppTheme.primary.withValues(alpha: 0.5)),
        ]),
      ),
    );
  }
}
