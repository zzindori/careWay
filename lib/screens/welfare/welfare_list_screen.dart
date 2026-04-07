import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/welfare_service.dart';
import '../../config/app_theme.dart';
import '../../widgets/welfare_card.dart';

class WelfareListScreen extends StatefulWidget {
  const WelfareListScreen({super.key});

  @override
  State<WelfareListScreen> createState() => _WelfareListScreenState();
}

class _WelfareListScreenState extends State<WelfareListScreen> {
  String _selectedCategory = 'all';

  final _categories = [
    ('all', '전체'),
    ('medical', '의료'),
    ('care', '돌봄'),
    ('living', '생활지원'),
    ('housing', '주거'),
    ('finance', '경제'),
    ('mobility', '이동'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ProfileProvider>();
      final profile = provider.selectedProfile;
      if (provider.allServices.isEmpty) {
        provider.loadAllWelfareServices().then((_) {
          if (profile != null && mounted) provider.matchWelfareServices(profile);
        });
      } else if (profile != null) {
        provider.matchWelfareServices(profile);
      }
    });
  }

  List<WelfareService> _filter(List<WelfareService> list) {
    if (_selectedCategory == 'all') return list;
    return list.where((s) => s.category == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<ProfileProvider>(
          builder: (_, p, __) => Text(
            p.selectedProfile != null ? '${p.selectedProfile!.name}님 맞춤 혜택' : '복지 서비스',
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Consumer<ProfileProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final matched = _filter(provider.matchedServices);
            final notMatched = _filter(provider.notMatchedServices);
            final profile = provider.selectedProfile;

            return CustomScrollView(
              slivers: [
                // 카테고리 필터
                SliverToBoxAdapter(child: _buildCategoryFilter()),

                // ── 해당 서비스 ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(children: [
                      Container(
                        width: 4, height: 16,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('해당 서비스 ${matched.length}개',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    ]),
                  ),
                ),

                if (matched.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('조건에 맞는 서비스가 없습니다.',
                          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: WelfareCard(
                            service: matched[i],
                            isMatched: true,
                            onTap: () => context.push('/welfare/${matched[i].id}'),
                          ),
                        ),
                        childCount: matched.length,
                      ),
                    ),
                  ),

                // ── 구분선 + 해당 안되는 서비스 헤더 ──
                if (notMatched.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                      child: Row(
                        children: [
                          const Expanded(child: Divider(thickness: 1)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade500),
                                const SizedBox(width: 5),
                                Text(
                                  '현재 해당 안되는 서비스 ${notMatched.length}개',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Expanded(child: Divider(thickness: 1)),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final svc = notMatched[i];
                          final reasons = profile != null
                              ? svc.getMismatchReasons(profile)
                              : <String>[];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildNotMatchedCard(context, svc, reasons),
                          );
                        },
                        childCount: notMatched.length,
                      ),
                    ),
                  ),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildNotMatchedCard(BuildContext context, WelfareService svc, List<String> reasons) {
    return GestureDetector(
      onTap: () => context.push('/welfare/${svc.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(svc.name,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ]),
          if (svc.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(svc.description,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: reasons.map((r) => _buildReasonChip(r)).toList(),
          ),
        ]),
      ),
    );
  }

  Widget _buildReasonChip(String reason) {
    final (icon, color) = _reasonStyle(reason);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(reason, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  (IconData, Color) _reasonStyle(String reason) {
    if (reason.contains('나이') || reason.contains('세')) {
      return (Icons.cake_outlined, Colors.blue.shade600);
    }
    if (reason.contains('소득') || reason.contains('분위')) {
      return (Icons.account_balance_wallet_outlined, Colors.orange.shade700);
    }
    if (reason.contains('장기요양')) {
      return (Icons.elderly_outlined, Colors.purple.shade600);
    }
    if (reason.contains('독거')) {
      return (Icons.person_outlined, Colors.teal.shade600);
    }
    if (reason.contains('기초생활') || reason.contains('수급')) {
      return (Icons.support_outlined, Colors.red.shade600);
    }
    return (Icons.info_outline, Colors.grey.shade600);
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _categories.map((cat) {
          final isSelected = _selectedCategory == cat.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(cat.$2),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedCategory = cat.$1),
              selectedColor: AppTheme.primary.withValues(alpha: 0.15),
              checkmarkColor: AppTheme.primary,
              labelStyle: TextStyle(
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              side: BorderSide(color: isSelected ? AppTheme.primary : AppTheme.divider),
            ),
          );
        }).toList(),
      ),
    );
  }
}
