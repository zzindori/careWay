import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/parent_profile.dart';
import '../../models/welfare_service.dart';
import '../../config/app_theme.dart';
import '../../widgets/profile_card.dart';

import '../../providers/application_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _confirmDeleteProfile(ParentProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('부모님 프로필 삭제'),
        content: Text('${profile.name} 프로필을 삭제할까요?\n삭제 후 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Color(0xFFD32F2F))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted || profile.id == null) return;

    await context.read<ProfileProvider>().deleteProfile(profile.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${profile.name} 프로필을 삭제했습니다.')),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<ProfileProvider>();
      await provider.loadProfiles();
      if (!mounted) return;
      if (provider.allServices.isEmpty && provider.selectedProfile != null) {
        provider.loadAllWelfareServices(
          regionFilter: ProfileProvider.normalizeRegion(provider.selectedProfile!.region),
        );
      }
    });
  }

  // 프로필별 tier 카운트 계산
  ({int t1, int t2, int t3}) _tierCounts(
      List<WelfareService> services, ParentProfile profile) {
    int t1 = 0, t2 = 0, t3 = 0;
    for (final svc in services) {
      switch (svc.getMatchTier(profile)) {
        case 1: t1++; break;
        case 2: t2++; break;
        case 3: t3++; break;
      }
    }
    return (t1: t1, t2: t2, t3: t3);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CareWay'),
        actions: [
          Consumer<ApplicationProvider>(
            builder: (_, appProvider, __) {
              final count = appProvider.records.length;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.assignment_outlined),
                    tooltip: '신청 관리',
                    onPressed: () => context.push('/application'),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 6, top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppTheme.primary, shape: BoxShape.circle),
                        child: Text('$count',
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => context.read<AuthProvider>().signOut(),
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
            if (provider.profiles.isEmpty) {
              return _buildEmptyState(context);
            }
            return _buildProfileList(context, provider);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/profile/new'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('부모님 등록'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.elderly_outlined, size: 72, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          const Text(
            '등록된 부모님 정보가 없습니다',
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          const Text(
            '부모님 정보를 등록하면\n맞춤 복지 혜택을 찾아드려요',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => context.push('/profile/new'),
            icon: const Icon(Icons.add),
            label: const Text('지금 등록하기'),
            style: ElevatedButton.styleFrom(minimumSize: const Size(200, 48)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileList(BuildContext context, ProfileProvider provider) {
    final services = provider.allServices;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        // ── 헤더 ─────────────────────────────────────────────
        const Text(
          '부모님 맞춤 혜택',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          services.isEmpty
              ? '혜택 정보를 불러오는 중이에요...'
              : '${provider.profiles.length}명의 부모님 혜택을 확인해보세요',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 20),
        ...provider.profiles.map((profile) {
          final counts = services.isNotEmpty
              ? _tierCounts(services, profile)
              : (t1: 0, t2: 0, t3: 0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ProfileCard(
              profile: profile,
              isSelected: provider.selectedProfile?.id == profile.id,
              tier1Count: counts.t1,
              tier2Count: counts.t2,
              tier3Count: counts.t3,
              onTap: () {
                provider.selectProfile(profile);
                context.push('/welfare');
              },
              onEdit: () => context.push('/profile/edit/${profile.id}'),
              onDelete: () => _confirmDeleteProfile(profile),
            ),
          );
        }),
      ],
    );
  }
}
