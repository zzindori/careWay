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
  bool _isRefreshing = false;

  final _categories = [
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

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    final provider = context.read<ProfileProvider>();
    final profile = provider.selectedProfile;
    if (profile != null) {
      await provider.loadAllWelfareServices(
        regionFilter: ProfileProvider.normalizeRegion(profile.region),
      );
      if (mounted) await provider.matchWelfareServices(profile);
    }
    if (mounted) setState(() => _isRefreshing = false);
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
        actions: [
          _isRefreshing
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '새로고침',
                  onPressed: _refresh,
                ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Consumer<ProfileProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final profile = provider.selectedProfile;

            final tier1 = _filter(provider.tier1Services);
            final tier2 = _filter(provider.tier2Services);
            final tier3 = _filter(provider.tier3Services);

            return Column(
              children: [
                _buildCategoryFilter(),
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      // ── Tier 1: 지금 바로 신청 ──
                SliverToBoxAdapter(
                  child: _buildTierHeader(
                    '우선 확인',
                    '${tier1.length}개',
                    const Color(0xFFE53935),
                    Icons.check_circle_outline,
                    '내 프로필과 가장 잘 맞는 서비스예요',
                  ),
                ),

                if (tier1.isEmpty)
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
                        (_, i) {
                          final svc = tier1[i];
                          final matchReasons = profile != null
                              ? svc.getMatchReasons(profile)
                              : <String>[];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: WelfareCard(
                              service: svc,
                              isMatched: true,
                              matchReasons: matchReasons,
                              onTap: () => context.push('/welfare/${svc.id}'),
                            ),
                          );
                        },
                        childCount: tier1.length,
                      ),
                    ),
                  ),

                // ── Tier 2: 등급 신청 후 가능 (신청 중인 경우만) ──
                if (profile?.ltcGradeStatus == 'applying' && tier2.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _buildTierHeader(
                      '등급 받으면 바로 신청 가능',
                      '${tier2.length}개',
                      const Color(0xFFF57C00),
                      Icons.hourglass_empty_outlined,
                      '장기요양 등급 신청 중 → 판정 후 즉시 가능',
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildTier2Card(context, tier2[i]),
                        ),
                        childCount: tier2.length,
                      ),
                    ),
                  ),
                ],

                // ── Tier 3: 알아두면 좋아요 ──
                if (tier3.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _buildTierHeader(
                      '알아두면 좋아요',
                      '${tier3.length}개',
                      AppTheme.secondary,
                      Icons.bookmark_border_outlined,
                      '일부 조건이 맞지 않지만 참고할 만한 서비스',
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final svc = tier3[i];
                          final reasons = profile != null
                              ? svc.getMismatchReasons(profile)
                              : <String>[];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildTier3Card(context, svc, reasons),
                          );
                        },
                        childCount: tier3.length,
                      ),
                    ),
                  ),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTierHeader(
      String title, String count, Color color, IconData icon, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
                Text(title,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(width: 5),
                Text(count,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(subtitle,
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _buildTier2Card(BuildContext context, WelfareService svc) {
    return GestureDetector(
      onTap: () => context.push('/welfare/${svc.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFE082)),
        ),
        child: Row(children: [
          const Icon(Icons.hourglass_empty, size: 18, color: Color(0xFFF57C00)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(svc.name,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              if (svc.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(svc.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ]),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFF57C00)),
        ]),
      ),
    );
  }

  Widget _buildTier3Card(
      BuildContext context, WelfareService svc, List<String> reasons) {
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
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600)),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ]),
          if (svc.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(svc.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: reasons.map((r) => _buildReasonChip(r)).toList(),
            ),
          ],
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
    if (reason.contains('노인') || reason.contains('어르신')) {
      return (Icons.elderly_outlined, Colors.blue.shade600);
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
    if (reason.contains('보훈')) {
      return (Icons.military_tech_outlined, Colors.indigo.shade600);
    }
    if (reason.contains('장애인')) {
      return (Icons.accessible_outlined, Colors.green.shade700);
    }
    if (reason.contains('지역')) {
      return (Icons.location_on_outlined, Colors.teal.shade600);
    }
    return (Icons.info_outline, Colors.grey.shade600);
  }


  Widget _buildCategoryFilter() {
    final cats = [('all', '전체'), ..._categories];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          children: cats.map((cat) {
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
      ),
    );
  }
}
