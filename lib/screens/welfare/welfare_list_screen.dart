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
  final Set<String> _disabledConditions = {};  // 비활성화된 필터 조건

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

            final tier1 = _filter(provider.tier1Services);
            final tier2 = _filter(provider.tier2Services);
            final tier3 = _filter(provider.tier3Services);
            final profile = provider.selectedProfile;

            // 조건 해제 시 추가 서비스 (이전에 숨겨진 것들)
            final alreadyShownIds = {
              for (final s in [...provider.tier1Services, ...provider.tier2Services, ...provider.tier3Services]) s.id,
            };
            final relaxed = profile != null
                ? _getRelaxedServices(provider.allServices, profile, alreadyShownIds)
                : <WelfareService>[];
            final relaxedFiltered = _selectedCategory == 'all'
                ? relaxed
                : relaxed.where((s) => s.category == _selectedCategory).toList();

            return Column(
              children: [
                _buildCategoryFilter(),
                if (profile != null) _buildConditionFilter(profile),
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

                // ── 조건 해제 추가 서비스 ──────────────────────
                if (relaxedFiltered.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _buildTierHeader(
                      '조건 해제 시 추가',
                      '${relaxedFiltered.length}개',
                      Colors.blueGrey.shade400,
                      Icons.lock_open_outlined,
                      '해제한 조건을 끄면 볼 수 있는 서비스예요',
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final svc = relaxedFiltered[i];
                          final reasons = profile != null
                              ? svc.getMismatchReasons(profile)
                              : <String>[];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildTier3Card(context, svc, reasons),
                          );
                        },
                        childCount: relaxedFiltered.length,
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

  // ─── 조건 필터 ─────────────────────────────────────────────

  static const _conditionDefs = [
    ('region',   '지역',   Icons.location_on_outlined),
    ('income',   '소득',   Icons.account_balance_wallet_outlined),
    ('ltcGrade', '장기요양', Icons.elderly_outlined),
    ('alone',    '독거',   Icons.person_outlined),
    ('basic',    '기초수급', Icons.support_outlined),
  ];

  List<(String, String, IconData)> _getAvailableConditions(profile) {
    final list = <(String, String, IconData)>[];
    list.add(_conditionDefs[0]); // 지역 항상 표시
    if (profile.incomeLevel != null && profile.incomeLevel! <= 8) {
      list.add(_conditionDefs[1]); // 소득: 설정된 경우
    }
    if (!profile.hasLtcGrade) {
      list.add(_conditionDefs[2]); // 장기요양: 등급 없는 경우
    }
    if (!profile.liveAlone) {
      list.add(_conditionDefs[3]); // 독거: 독거 아닌 경우
    }
    if (!profile.isBasicRecipient) {
      list.add(_conditionDefs[4]); // 기초수급: 비수급 경우
    }
    return list;
  }

  Widget _buildConditionFilter(profile) {
    final available = _getAvailableConditions(profile);
    if (available.isEmpty) return const SizedBox.shrink();

    final anyDisabled = _disabledConditions.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: anyDisabled ? const Color(0xFFFFF8E1) : const Color(0xFFF8F9FA),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(children: [
              Icon(Icons.tune, size: 11, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                anyDisabled ? '일부 조건 해제됨 · 더 많은 서비스 표시 중' : '적용 중인 조건',
                style: TextStyle(
                  fontSize: 11,
                  color: anyDisabled ? const Color(0xFFF57C00) : Colors.grey.shade500,
                  fontWeight: anyDisabled ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ]),
          ),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: available.map((c) {
                final isOn = !_disabledConditions.contains(c.$1);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    avatar: Icon(c.$3, size: 12,
                        color: isOn ? AppTheme.primary : Colors.grey.shade400),
                    label: Text(c.$2),
                    selected: isOn,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      if (isOn) { _disabledConditions.add(c.$1); }
                      else { _disabledConditions.remove(c.$1); }
                    }),
                    selectedColor: AppTheme.primary.withValues(alpha: 0.12),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      color: isOn ? AppTheme.primary : Colors.grey.shade400,
                      fontWeight: isOn ? FontWeight.w600 : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isOn ? AppTheme.primary : Colors.grey.shade300,
                    ),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<WelfareService> _getRelaxedServices(
    List<WelfareService> allServices,
    profile,
    Set<String> alreadyShownIds,
  ) {
    if (_disabledConditions.isEmpty) return [];
    return allServices
        .where((s) => !alreadyShownIds.contains(s.id) && _matchesRelaxed(s, profile))
        .toList();
  }

  bool _matchesRelaxed(WelfareService svc, profile) {
    // 항상 제외: 근본적으로 다른 대상
    final tg = svc.targetAgeGroup;
    if (tg == 'youth' || tg == 'child' || tg == 'infant') return false;
    if (svc.requiresVeteran && !profile.isVeteran) return false;
    if (svc.requiresDisability) return false;

    // 나이는 항상 적용 (바꿀 수 없음)
    if (svc.minAge > 0 && profile.age < svc.minAge) return false;

    // 지역: 비활성이면 스킵
    if (!_disabledConditions.contains('region')) {
      if (svc.region.isNotEmpty && svc.region != '전국') {
        if (svc.region != ProfileProvider.normalizeRegion(profile.region)) return false;
      }
    }

    // 소득: 비활성이면 스킵
    if (!_disabledConditions.contains('income')) {
      if (svc.maxIncomeLevel < 10 && profile.incomeLevel != null) {
        if (profile.incomeLevel! > svc.maxIncomeLevel) return false;
      }
    }

    // 장기요양: 비활성이면 스킵
    if (!_disabledConditions.contains('ltcGrade')) {
      if (svc.requiresLtcGrade && !profile.hasLtcGrade) return false;
    }

    // 독거: 비활성이면 스킵
    if (!_disabledConditions.contains('alone')) {
      if (svc.requiresAlone && !profile.liveAlone) return false;
    }

    // 기초수급: 비활성이면 스킵
    if (!_disabledConditions.contains('basic')) {
      if (svc.requiresBasicRecipient && !profile.isBasicRecipient) return false;
    }

    return true;
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
