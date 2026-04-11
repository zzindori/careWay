import 'package:flutter/material.dart';
import '../models/parent_profile.dart';
import '../config/app_theme.dart';

class ProfileCard extends StatelessWidget {
  final ParentProfile profile;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final int? tier1Count;
  final int? tier2Count;
  final int? tier3Count;

  const ProfileCard({
    super.key,
    required this.profile,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    this.tier1Count,
    this.tier2Count,
    this.tier3Count,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // 아바타
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.elderly, color: AppTheme.primary, size: 28),
              ),
            ),
            const SizedBox(width: 14),
            // 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${profile.age}세',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${profile.region} · ${_healthLabel(profile.healthStatus)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildTags(profile),
                  if (_hasAnyCounts) ...[
                    const SizedBox(height: 8),
                    _buildTierSummary(),
                  ],
                ],
              ),
            ),
            // 수정 버튼
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 18, color: AppTheme.textSecondary),
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasAnyCounts =>
      (tier1Count ?? 0) > 0 || (tier2Count ?? 0) > 0 || (tier3Count ?? 0) > 0;

  Widget _buildTierSummary() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if ((tier1Count ?? 0) > 0)
          _tierBadge('즉시신청 $tier1Count건', const Color(0xFFE53935)),
        if ((tier2Count ?? 0) > 0)
          _tierBadge('등급후신청 $tier2Count건', const Color(0xFFF57C00)),
        if ((tier3Count ?? 0) > 0)
          _tierBadge('참고 $tier3Count건', AppTheme.secondary),
      ],
    );
  }

  Widget _tierBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _healthLabel(String status) {
    switch (status) {
      case 'good':
        return '건강 양호';
      case 'fair':
        return '건강 보통';
      case 'poor':
        return '건강 불량';
      default:
        return '';
    }
  }

  Widget _buildTags(ParentProfile profile) {
    final tags = <String>[];
    if (profile.isBasicRecipient) tags.add('기초수급');
    if (profile.liveAlone) tags.add('독거');
    if (profile.ltcGradeStatus == 'has') tags.add('장기요양 ${profile.ltcGrade}등급');
    if (profile.ltcGradeStatus == 'applying') tags.add('장기요양 신청 중');
    if (profile.isVeteran) tags.add('보훈대상자');
    if (tags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      children: tags
          .map((t) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  t,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ))
          .toList(),
    );
  }
}
