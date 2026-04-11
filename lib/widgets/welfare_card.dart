import 'package:flutter/material.dart';
import '../models/welfare_service.dart';
import '../config/app_theme.dart';

class WelfareCard extends StatelessWidget {
  final WelfareService service;
  final VoidCallback onTap;
  final bool? isMatched;
  final List<String> matchReasons;

  const WelfareCard({
    super.key,
    required this.service,
    required this.onTap,
    this.isMatched,
    this.matchReasons = const [],
  });

  // benefitInfo가 복지로 안내 문구인 경우 targetInfo로 폴백
  String get _displayText {
    final b = service.benefitInfo.trim();
    if (b.isEmpty || b.contains('복지로') || b.contains('홈페이지') || b.length < 10) {
      final t = service.targetInfo.trim();
      if (t.isNotEmpty) return t;
      return service.description.trim();
    }
    return b;
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor =
        AppTheme.categoryColors[service.category] ?? AppTheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (isMatched == true && service.canShowMatchedBadge)
                ? Colors.green.withValues(alpha: 0.4)
                : AppTheme.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 카테고리 아이콘
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _categoryIcon(service.category),
                    color: categoryColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Row(children: [
                        Text(
                          service.categoryLabel,
                          style: TextStyle(fontSize: 12, color: categoryColor),
                        ),
                        if (isMatched == true && service.canShowMatchedBadge) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('✓ 해당됨',
                                style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                    ],
                  ),
                ),
                // 마감 임박 알림
                if (service.isDeadlineSoon)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '마감 임박',
                      style: TextStyle(
                        color: AppTheme.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_ios,
                    size: 14, color: AppTheme.textSecondary),
              ],
            ),
            const SizedBox(height: 8),
            // 지원 내용 (복지로 안내문 폴백 처리)
            Text(
              _displayText,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            // 해당 사유 칩 (Tier 1 전용)
            if (matchReasons.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: matchReasons.map((r) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Text(r,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.w500)),
                )).toList(),
              ),
              const SizedBox(height: 8),
            ],
            // 신청처 + 금액 + 난이도
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    service.applyPlace,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                // 혜택 금액
                if (service.benefitAmount != null) ...[
                  const Icon(Icons.attach_money,
                      size: 14, color: AppTheme.secondary),
                  const SizedBox(width: 2),
                  Text(
                    '월 ${_formatAmount(service.benefitAmount!)}원',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                // 신청 난이도
                Icon(
                  Icons.signal_cellular_alt,
                  size: 14,
                  color: _difficultyColor(service.difficulty),
                ),
                const SizedBox(width: 2),
                Text(
                  '신청 ${service.difficultyLabel}',
                  style: TextStyle(
                    fontSize: 12,
                    color: _difficultyColor(service.difficulty),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'medical':
        return Icons.local_hospital_outlined;
      case 'care':
        return Icons.favorite_outline;
      case 'living':
        return Icons.shopping_bag_outlined;
      case 'housing':
        return Icons.home_outlined;
      case 'finance':
        return Icons.account_balance_wallet_outlined;
      case 'mobility':
        return Icons.directions_bus_outlined;
      default:
        return Icons.star_outline;
    }
  }

  Color _difficultyColor(int difficulty) {
    switch (difficulty) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatAmount(int amount) {
    if (amount >= 10000) {
      return '${(amount / 10000).toStringAsFixed(0)}만';
    }
    return amount.toString();
  }
}
