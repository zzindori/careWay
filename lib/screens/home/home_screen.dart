import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/parent_profile.dart';
import '../../config/app_theme.dart';
import '../../widgets/profile_card.dart';
import '../../widgets/eligibility_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProfileProvider>().loadProfiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CareWay'),
        actions: [
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
          const Icon(
            Icons.elderly_outlined,
            size: 72,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 16),
          const Text(
            '등록된 부모님 정보가 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '부모님 정보를 등록하면\n맞춤 복지 혜택을 찾아드려요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => context.push('/profile/new'),
            icon: const Icon(Icons.add),
            label: const Text('지금 등록하기'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(200, 48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileList(BuildContext context, ProfileProvider provider) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 선택된 프로필 복지 서비스 바로가기
        if (provider.selectedProfile != null) ...[
          _buildWelfareShortcut(context, provider.selectedProfile!),
          const SizedBox(height: 12),
          EligibilityCard(profile: provider.selectedProfile!),
          const SizedBox(height: 12),
        ],
        const Text(
          '등록된 부모님',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ...provider.profiles.map(
          (profile) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ProfileCard(
              profile: profile,
              isSelected: provider.selectedProfile?.id == profile.id,
              onTap: () {
                provider.selectProfile(profile);
                context.push('/welfare');
              },
              onEdit: () => context.push('/profile/edit/${profile.id}'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWelfareShortcut(BuildContext context, ParentProfile profile) {
    return GestureDetector(
      onTap: () {
        context.read<ProfileProvider>().selectProfile(profile);
        context.push('/welfare');
      },
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${profile.name}님 맞춤 혜택 찾기',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  '신청 가능한 복지 서비스를 확인하세요',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
        ],
      ),
      ),
    );
  }
}
