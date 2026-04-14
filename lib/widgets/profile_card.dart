import 'package:flutter/material.dart';
import '../models/parent_profile.dart';
import '../config/app_theme.dart';

class ProfileCard extends StatelessWidget {
  final ParentProfile profile;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final int? tier1Count;
  final int? tier2Count;
  final int? tier3Count;

  const ProfileCard({
    super.key,
    required this.profile,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.tier1Count,
    this.tier2Count,
    this.tier3Count,
  });

  static const _red = Color(0xFFE53935);
  static const _orange = Color(0xFFF57C00);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: AppTheme.primary, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 상단: 프로필 정보 ─────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 이름 + 나이/지역
                        Row(children: [
                          Text(
                            profile.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${profile.age}세 · ${profile.region}',
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.textSecondary),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        // 요양등급 + 기타 태그
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _ltcBadge(),
                            ..._otherTags(),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 16, color: AppTheme.textSecondary),
                        onPressed: onEdit,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 16, color: Color(0xFFD32F2F)),
                        onPressed: onDelete,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: '삭제',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── 권고 사항 ─────────────────────────────────────
            _buildAdvisory(),

            // ── 중단: 혜택 건수 ───────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '맞춤 혜택 현황',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: _tierBox(
                              '우선 확인', tier1Count ?? 0, _red)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _tierBox(
                              '검토 후', tier2Count ?? 0, _orange)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _tierBox('알아두기',
                              tier3Count ?? 0, AppTheme.secondary)),
                    ],
                  ),
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildAdvisory() {
    final tip = _advisoryTip();
    if (tip == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tip.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tip.color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(tip.icon, size: 13, color: tip.color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.condition,
                  style: TextStyle(
                    fontSize: 10,
                    color: tip.color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tip.message,
                  style: TextStyle(
                    fontSize: 11,
                    color: tip.color.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _AdvisoryTip? _advisoryTip() {
    // 1순위: 등급 없음 + 고령/건강 문제 → 신청 권고
    if (profile.ltcGradeStatus == 'none') {
      final needsLtc = profile.age >= 65 ||
          profile.healthConditions.isNotEmpty ||
          profile.healthStatus != 'good';
      if (needsLtc) {
        final reason = profile.age >= 65
            ? '${profile.age}세 이상 · 장기요양등급 미신청'
            : '건강 상태 확인 필요 · 장기요양등급 미신청';
        return _AdvisoryTip(
          icon: Icons.assignment_outlined,
          condition: reason,
          message: '등급 신청 시 받을 수 있는 혜택이 크게 늘어납니다',
          color: const Color(0xFFE65100),
        );
      }
    }

    // 2순위: 등급 신청중
    if (profile.ltcGradeStatus == 'applying') {
      return _AdvisoryTip(
        icon: Icons.hourglass_top_rounded,
        condition: '장기요양등급 심사 중',
        message: '판정 결과에 따라 이용 가능한 혜택이 추가될 예정이에요',
        color: const Color(0xFF1565C0),
      );
    }

    // 3순위: 소득 낮음 + 기초수급 미해당
    if (!profile.isBasicRecipient &&
        profile.incomeLevel != null &&
        profile.incomeLevel! <= 3) {
      return _AdvisoryTip(
        icon: Icons.info_outline,
        condition: '소득 하위 30% · 기초수급 미신청',
        message: '기초생활수급 신청 자격이 있을 수 있어요',
        color: const Color(0xFF2E7D32),
      );
    }

    // 4순위: 독거 + 등급 없음
    if (profile.liveAlone && profile.ltcGradeStatus == 'none') {
      return _AdvisoryTip(
        icon: Icons.home_outlined,
        condition: '독거 · 장기요양등급 미신청',
        message: '독거 어르신 전용 돌봄 서비스를 확인해보세요',
        color: const Color(0xFF00695C),
      );
    }

    return null;
  }

  Widget _tierBox(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
      ]),
    );
  }

  Widget _ltcBadge() {
    if (profile.ltcGradeStatus == 'has') {
      return _tag('요양 ${profile.ltcGrade}등급', AppTheme.primary, isBold: true);
    } else if (profile.ltcGradeStatus == 'applying') {
      return _tag('요양등급 신청중', _orange, isBold: true);
    }
    return const SizedBox.shrink();
  }

  List<Widget> _otherTags() {
    final tags = <Widget>[];
    if (profile.gender == 'male') {
      tags.add(_tag('남성', Colors.blue.shade600));
    } else if (profile.gender == 'female') {
      tags.add(_tag('여성', Colors.pink.shade500));
    }
    if (profile.isBasicRecipient) {
      tags.add(_tag('기초수급', Colors.indigo.shade700));
    } else if (profile.incomeLevel != null && profile.incomeLevel! <= 3) {
      tags.add(_tag('저소득', Colors.indigo.shade400));
    }
    if (profile.liveAlone) tags.add(_tag('독거', Colors.teal.shade700));
    if (profile.isVeteran) tags.add(_tag('보훈', Colors.brown.shade600));
    for (final c in profile.healthConditions) {
      tags.add(_tag(_conditionLabel(c), Colors.grey.shade600));
    }
    if (profile.ltcGradeStatus == 'none' && tags.isEmpty) {
      tags.add(_tag('등급없음', Colors.grey.shade500));
    }
    return tags;
  }

  String _conditionLabel(String code) {
    switch (code) {
      case 'dementia':   return '치매';
      case 'mobility':   return '거동불편';
      case 'hearing':    return '청각저하';
      case 'vision':     return '시력저하';
      case 'housework':  return '가사불편';
      case 'hospital':   return '병원동행 필요';
      default:           return code;
    }
  }

  Widget _tag(String label, Color color, {bool isBold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }

}

class _AdvisoryTip {
  final IconData icon;
  final String condition;
  final String message;
  final Color color;
  const _AdvisoryTip({required this.icon, required this.condition, required this.message, required this.color});
}