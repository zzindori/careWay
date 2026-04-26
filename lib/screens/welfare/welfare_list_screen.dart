import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _isRefreshing = false;
  List<Map<String, String>> _localProviders = [];
  bool _providersLoading = false;

  final _categories = [
    ('medical', '의료'),
    ('care', '돌봄'),
    ('living', '생활지원'),
    ('housing', '주거'),
    ('finance', '경제'),
    ('mobility', '교통'),
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _normalizeSearchText(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^0-9a-zA-Z가-힣\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _queryTokens(String query) {
    final normalized = _normalizeSearchText(query.replaceAll('#', ''));
    if (normalized.isEmpty) return const [];
    return normalized
        .split(' ')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  bool _matchesSearch(WelfareService s) {
    final tokens = _queryTokens(_searchQuery);
    if (tokens.isEmpty) return true;

    final searchableFields = <String>[
      s.name,
      s.targetInfo,
      s.benefitInfo,
      s.aiSummary,
      s.description,
      s.applyPlace,
      s.categoryLabel,
      s.region,
      s.subRegion,
      ...s.serviceTags,
    ];
    final normalizedText = _normalizeSearchText(searchableFields.join(' '));

    final normalizedSearchTokens = s.searchTokens
        .map((e) => _normalizeSearchText(e))
        .where((e) => e.isNotEmpty)
        .toSet();
    final normalizedTextTokens = normalizedText.split(' ').where((e) => e.isNotEmpty).toSet();

    for (final token in tokens) {
      final isShortToken = token.length <= 2;
      final inSearchTokens = isShortToken
          ? normalizedSearchTokens.contains(token)
          : (normalizedSearchTokens.contains(token) ||
              normalizedSearchTokens.any((t) => t.contains(token)));
      final inText = isShortToken
          ? normalizedTextTokens.contains(token)
          : normalizedText.contains(token);
      if (!inSearchTokens && !inText) return false;
    }
    return true;
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
    return list.where((s) {
      if (!_matchesSearch(s)) return false;

      if (_selectedCategory == 'all') return true;

      // 배치 AI 분류가 덜 된 데이터 보완:
      // 카테고리별 신호를 기반으로 "대표 카테고리"를 하나 정해 중복 노출을 막는다.
      final text = '${s.name} ${s.description} ${s.targetInfo} ${s.benefitInfo}';
      final careKeywords = ['돌봄', '요양', '방문요양', '간병', '목욕', '식사', '일상생활', '재가'];
      final hasCareKeyword = careKeywords.any(text.contains);
      final hasCareTag = s.serviceTags.any((t) => t == 'daily_care' || t == 'dementia');
      final hasStrongCareSignal = s.requiresLtcGrade || hasCareTag || hasCareKeyword;
      final medicalKeywords = ['의료', '치료', '병원', '약제', '투약', '건강검진', '진료', '보청기', '안경'];
      final hasMedicalKeyword = medicalKeywords.any(text.contains);
      final hasMedicalTag = s.serviceTags.any((t) => t == 'medical' || t == 'hearing' || t == 'vision');
      final hasStrongMedicalSignal = hasMedicalTag || hasMedicalKeyword;
      final housingKeywords = ['주거', '임대', '집수리', '주택개조', '주택', '전세', '월세'];
      final hasHousingSignal = housingKeywords.any(text.contains);
      final livingKeywords = ['생활', '식품', '문화', '여가', '교육', '통신비', '이동전화', '냉난방', '생필품'];
      final hasLivingSignal = livingKeywords.any(text.contains);
      final financeKeywords = ['연금', '수당', '현금', '바우처', '생계급여', '지원금', '급여'];
      final hasFinanceSignal = financeKeywords.any(text.contains);
      final mobilityKeywords = ['교통', '이동', '병원동행', '차량', '버스', '택시'];
      final hasMobilityTag = s.serviceTags.any((t) => t == 'mobility');
      final hasMobilitySignal = hasMobilityTag || mobilityKeywords.any(text.contains);

      String effectiveCategory = s.category;
      if (hasStrongCareSignal) {
        effectiveCategory = 'care';
      } else if (hasStrongMedicalSignal) {
        effectiveCategory = 'medical';
      } else if (hasHousingSignal) {
        effectiveCategory = 'housing';
      } else if (hasLivingSignal) {
        effectiveCategory = 'living';
      } else if (hasFinanceSignal) {
        effectiveCategory = 'finance';
      } else if (hasMobilitySignal) {
        effectiveCategory = 'mobility';
      }

      return effectiveCategory == _selectedCategory;
    }).toList();
  }

  Future<void> _loadLocalProviders(String category, String region) async {
    setState(() { _localProviders = []; _providersLoading = true; });
    try {
      final normalizedRegion = ProfileProvider.normalizeRegion(region);
      final rows = await Supabase.instance.client
          .from('service_providers')
          .select('name,address,phone')
          .eq('category', category)
          .eq('region', normalizedRegion)
          .limit(20);
      final list = (rows as List)
          .map((row) {
            final r = row as Map<String, dynamic>;
            return {
              'name': (r['name'] ?? '').toString(),
              'addr': (r['address'] ?? '').toString(),
              'phone': (r['phone'] ?? '').toString(),
            };
          })
          .where((p) => p['name']!.isNotEmpty)
          .toList();
      if (mounted) setState(() => _localProviders = list);
    } catch (_) {}
    if (mounted) setState(() => _providersLoading = false);
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
            final tier3Ids = provider.tier3Services.map((s) => s.id).toSet();
            final matchedIds = {
              ...provider.tier1Services.map((s) => s.id),
              ...provider.tier2Services.map((s) => s.id),
              ...tier3Ids,
            };
            // tier3 매칭 + 일반 참고 목록. 명시적으로 숨긴 서비스는 재노출하지 않는다.
            final tier3 = [
              ..._filter(provider.tier3Services),
              ..._filter(provider.allServices)
                  .where((s) => !matchedIds.contains(s.id) && s.shouldShowInGeneralList),
            ];

            return Column(
              children: [
                _buildCategoryFilter(),
                _buildSearchBar(),
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

                // ── Tier 2: 장기요양 등급 필요 ──
                if (tier2.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _buildTierHeader(
                      profile?.ltcGradeStatus == 'applying'
                          ? '등급 받으면 바로 신청 가능'
                          : '장기요양 등급 필요',
                      '${tier2.length}개',
                      const Color(0xFFF57C00),
                      Icons.hourglass_empty_outlined,
                      profile?.ltcGradeStatus == 'applying'
                          ? '장기요양 등급 신청 중 → 판정 후 즉시 가능'
                          : '현재는 신청 전 단계예요. 등급 신청 후 진행할 수 있어요',
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildTier2Card(context, tier2[i], profile),
                        ),
                        childCount: tier2.length,
                      ),
                    ),
                  ),
                ],

                // ── 우리 지역 서비스 기관 ──
                if (_selectedCategory != 'all' && (_providersLoading || _localProviders.isNotEmpty)) ...[
                  SliverToBoxAdapter(
                    child: _buildTierHeader(
                      '우리 지역 서비스 기관',
                      _providersLoading ? '' : '${_localProviders.length}개',
                      const Color(0xFF00796B),
                      Icons.location_on_outlined,
                      '지역 내 실제 서비스 제공 기관',
                    ),
                  ),
                  if (_providersLoading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildProviderCard(_localProviders[i]),
                          ),
                          childCount: _localProviders.length,
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
                      '참고할 만한 서비스 전체 목록',
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

  Widget _aiBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F5E9),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFA5D6A7)),
    ),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.auto_awesome, size: 10, color: Color(0xFF388E3C)),
      SizedBox(width: 3),
      Text('AI', style: TextStyle(
          fontSize: 10, color: Color(0xFF388E3C), fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _buildProviderCard(Map<String, String> provider) {
    const teal = Color(0xFF00796B);
    const tealLight = Color(0xFFE0F2F1);
    const tealBorder = Color(0xFF80CBC4);
    final name = provider['name'] ?? '';
    final addr = provider['addr'] ?? '';
    final phone = provider['phone'] ?? '';

    return GestureDetector(
      onTap: phone.isNotEmpty
          ? () async {
              final uri = Uri(scheme: 'tel', path: phone);
              if (await canLaunchUrl(uri)) launchUrl(uri);
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tealLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tealBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // 기관 아이콘
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: teal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.business_outlined, color: teal, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                Row(children: [
                  const Text('서비스 기관', style: TextStyle(fontSize: 12, color: teal)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('📍 지역',
                        style: TextStyle(fontSize: 10, color: teal, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ]),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: teal),
          ]),
          if (addr.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(addr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
          ],
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.phone_outlined, size: 13, color: teal),
              const SizedBox(width: 4),
              Text(phone, style: const TextStyle(
                  fontSize: 12, color: teal, fontWeight: FontWeight.w600)),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _buildTier2Card(BuildContext context, WelfareService svc, dynamic profile) {
    final reasons = profile != null ? svc.getMismatchReasons(profile) : <String>[];
    final hint = reasons.isNotEmpty ? reasons.first : '장기요양 등급 확인이 필요해요';
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
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 12, color: Color(0xFFE65100)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '미충족 사유: $hint',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0xFFE65100)),
                    ),
                  ),
                ],
              ),
            ]),
          ),
          if (svc.aiSummary.isNotEmpty) ...[
            _aiBadge(),
            const SizedBox(width: 6),
          ],
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
            if (svc.aiSummary.isNotEmpty) ...[
              _aiBadge(),
              const SizedBox(width: 6),
            ],
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
                onSelected: (_) {
                  setState(() => _selectedCategory = cat.$1);
                  final profile = context.read<ProfileProvider>().selectedProfile;
                  if (profile != null) _loadLocalProviders(cat.$1, profile.region);
                },
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

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '서비스명/대상/혜택/태그 키워드 검색',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          filled: true,
          fillColor: const Color(0xFFF7F8FA),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary),
          ),
        ),
      ),
    );
  }
}
