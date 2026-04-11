import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/welfare_standards_provider.dart';
import '../../models/parent_profile.dart';
import '../../config/app_theme.dart';

class ProfileFormScreen extends StatefulWidget {
  final String? profileId;
  const ProfileFormScreen({super.key, this.profileId});

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  int _birthYear = DateTime.now().year - 70;
  String _region = '서울특별시';
  String _subRegion = '';
  String _healthStatus = 'good';

  // 장기요양등급 상태
  String _ltcGradeStatus = 'none'; // 'has' / 'applying' / 'none'
  int? _ltcGrade;

  int _incomeLevel = 5;
  bool _isBasicRecipient = false;
  bool _liveAlone = false;

  // 건강 상태 상세 (복수 선택)
  final Set<String> _healthConditions = {};

  // 보훈 종류 (복수 선택)
  final Set<String> _veteranTypes = {};

  bool _isLoading = false;

  bool get _isEdit => widget.profileId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadExistingProfile();
  }

  void _loadExistingProfile() {
    final provider = context.read<ProfileProvider>();
    final profile = provider.profiles.firstWhere(
      (p) => p.id == widget.profileId,
    );
    _nameCtrl.text = profile.name;
    _birthYear = profile.birthYear;
    _region = profile.region;
    _subRegion = profile.subRegion;
    _healthStatus = profile.healthStatus;
    _ltcGradeStatus = profile.ltcGradeStatus;
    _ltcGrade = profile.ltcGrade;
    _incomeLevel = profile.incomeLevel ?? 5;
    _isBasicRecipient = profile.isBasicRecipient;
    _liveAlone = profile.liveAlone;
    _healthConditions.addAll(profile.healthConditions);
    _veteranTypes.addAll(profile.veteranTypes);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      final profileProvider = context.read<ProfileProvider>();
      final userId = authProvider.currentUser?.id;

      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('로그인이 필요합니다')),
          );
        }
        return;
      }

      final profile = ParentProfile(
        id: widget.profileId,
        userId: userId,
        name: _nameCtrl.text.trim(),
        birthYear: _birthYear,
        region: _region,
        subRegion: _subRegion,
        healthStatus: _healthStatus,
        ltcGradeStatus: _ltcGradeStatus,
        ltcGrade: _ltcGradeStatus == 'has' ? _ltcGrade : null,
        incomeLevel: _incomeLevel,
        isBasicRecipient: _isBasicRecipient,
        liveAlone: _liveAlone,
        healthConditions: _healthConditions.toList(),
        veteranTypes: _veteranTypes.toList(),
      );

      if (_isEdit) {
        await profileProvider.updateProfile(profile);
      } else {
        await profileProvider.addProfile(profile);
      }
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showHelp(String title, String content) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
              ]),
              const SizedBox(height: 12),
              Text(content,
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary, height: 1.7)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabelWithHelp(String label, String helpTitle, String helpContent) {
    return Row(children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
      const SizedBox(width: 4),
      GestureDetector(
        onTap: () => _showHelp(helpTitle, helpContent),
        child: const Icon(Icons.help_outline, size: 16, color: AppTheme.primary),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '프로필 수정' : '부모님 등록')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildSection('기본 정보', [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(hintText: '이름 (예: 홍길동)'),
                  validator: (v) => (v?.isEmpty ?? true) ? '이름을 입력하세요' : null,
                ),
                const SizedBox(height: 16),
                _buildYearPicker(),
                const SizedBox(height: 16),
                _buildRegionPicker(),
              ]),

              const SizedBox(height: 24),
              _buildSection('건강 상태', [
                Row(children: [
                  _buildLabelWithHelp(
                    '전반적인 건강 상태',
                    '건강 상태란?',
                    '부모님의 전반적인 건강 상태를 선택해 주세요.\n\n'
                    '• 양호: 일상생활을 혼자 무리없이 하실 수 있음\n'
                    '• 보통: 일부 도움이 필요하거나 만성질환이 있음\n'
                    '• 불량: 일상생활에 상당한 도움이 필요함',
                  ),
                ]),
                const SizedBox(height: 12),
                _buildHealthStatusSelector(),
                const SizedBox(height: 16),
                _buildLabelWithHelp(
                  '건강 문제 (해당 항목 모두 선택)',
                  '건강 문제 선택',
                  '부모님께 해당하는 건강 문제를 모두 선택해 주세요.\n\n'
                  '이 정보는 맞춤 복지 서비스를 찾는 데 사용됩니다.',
                ),
                const SizedBox(height: 8),
                _buildHealthConditionChips(),
              ]),

              const SizedBox(height: 24),
              _buildSection('장기요양등급', [
                _buildLabelWithHelp(
                  '장기요양등급 상태',
                  '장기요양등급이란?',
                  '국민건강보험공단에서 판정하는 등급으로,\n신체·인지 기능 저하로 6개월 이상 일상생활이 어려운 분께 발급됩니다.\n\n'
                  '• 1등급: 최중증 (일상생활 전적으로 의존)\n'
                  '• 2등급: 중증\n'
                  '• 3등급: 중등증\n'
                  '• 4등급: 경증\n'
                  '• 5등급: 치매 특별등급\n'
                  '• 인지지원등급: 치매 초기\n\n'
                  '등급이 있으면 요양보호사 파견, 요양시설 입소 등 혜택을 받을 수 있어요.',
                ),
                const SizedBox(height: 12),
                _buildLtcGradeStatusSelector(),
                if (_ltcGradeStatus == 'has') _buildLtcGradePicker(),
              ]),

              const SizedBox(height: 24),
              _buildSection('소득/수급 정보', [
                _buildIncomeLevelSlider(),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: _buildLabelWithHelp(
                    '기초생활수급자',
                    '기초생활수급자란?',
                    '소득과 재산이 일정 기준 이하인 분들께 정부가 생계, 의료, 주거 등을 지원하는 제도입니다.\n\n'
                    '주민센터에서 수급자 확인이 가능합니다.',
                  ),
                  value: _isBasicRecipient,
                  onChanged: (v) => setState(() => _isBasicRecipient = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.primary,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  title: _buildLabelWithHelp(
                    '독거 노인',
                    '독거 노인이란?',
                    '혼자 생활하시는 어르신을 말합니다.\n\n'
                    '독거 노인이시면 돌봄 서비스, 응급안전안심서비스 등 전용 혜택을 받을 수 있어요.',
                  ),
                  value: _liveAlone,
                  onChanged: (v) => setState(() => _liveAlone = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.primary,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ]),

              const SizedBox(height: 24),
              _buildSection('국가보훈', [
                _buildLabelWithHelp(
                  '보훈대상자 여부 (해당 항목 모두 선택)',
                  '국가보훈이란?',
                  '국가를 위해 희생·공헌하신 분들께 국가가 예우하는 제도입니다.\n\n'
                  '• 국가유공자: 전투·공무 수행 중 상이, 순직\n'
                  '• 참전유공자: 6·25전쟁 또는 월남전 참전\n'
                  '• 독립유공자: 독립운동 참여\n\n'
                  '보훈 대상자이시면 의료비 감면, 교통 할인, 생활지원금 등 다양한 혜택을 받을 수 있어요.',
                ),
                const SizedBox(height: 8),
                _buildVeteranTypeChips(),
              ]),

              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : Text(_isEdit ? '수정 완료' : '등록 완료'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildYearPicker() {
    return Row(children: [
      _buildLabelWithHelp(
        '출생연도',
        '출생연도',
        '부모님의 실제 출생연도를 입력해 주세요.\n\n만 65세 이상이면 기초연금, 노인 돌봄 서비스 등 나이 기준 혜택을 받을 수 있어요.',
      ),
      const Spacer(),
      IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: () => setState(() => _birthYear--),
      ),
      Text('$_birthYear년',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      IconButton(
        icon: const Icon(Icons.add_circle_outline),
        onPressed: () => setState(() => _birthYear++),
      ),
      Text('(${DateTime.now().year - _birthYear}세)',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
    ]);
  }

  Widget _buildRegionPicker() {
    const regions = [
      '서울특별시', '부산광역시', '대구광역시', '인천광역시', '광주광역시',
      '대전광역시', '울산광역시', '세종특별자치시', '경기도', '강원도',
      '충청북도', '충청남도', '전라북도', '전라남도', '경상북도', '경상남도', '제주도',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildLabelWithHelp(
        '거주 지역',
        '거주 지역이란?',
        '부모님이 현재 실제로 살고 계신 지역을 선택해 주세요.\n\n지역마다 지자체 복지 혜택이 다르기 때문에 정확한 지역 선택이 중요해요.',
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: _region,
        decoration: const InputDecoration(hintText: '시/도 선택'),
        items: regions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
        onChanged: (v) => setState(() => _region = v ?? _region),
      ),
    ]);
  }

  Widget _buildHealthStatusSelector() {
    const options = [
      ('good', '양호', Colors.green),
      ('fair', '보통', Colors.orange),
      ('poor', '불량', Colors.red),
    ];
    return Row(
      children: options.map((opt) {
        final isSelected = _healthStatus == opt.$1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => setState(() => _healthStatus = opt.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? opt.$3.withValues(alpha: 0.1)
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? opt.$3 : AppTheme.divider,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(opt.$2,
                      style: TextStyle(
                          color: isSelected ? opt.$3 : AppTheme.textSecondary,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.normal)),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHealthConditionChips() {
    const conditions = [
      ('hearing', '청각/보청기', Icons.hearing),
      ('vision', '시각/안과', Icons.visibility_outlined),
      ('mobility', '거동불편/이동지원', Icons.accessible_outlined),
      ('dementia', '치매', Icons.psychology_outlined),
      ('housework', '집안일 어려움', Icons.home_repair_service_outlined),
      ('hospital', '병원동행 필요', Icons.local_hospital_outlined),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: conditions.map((c) {
        final selected = _healthConditions.contains(c.$1);
        return FilterChip(
          avatar: Icon(c.$3, size: 16,
              color: selected ? AppTheme.primary : AppTheme.textSecondary),
          label: Text(c.$2),
          selected: selected,
          onSelected: (_) => setState(() {
            if (selected) {
              _healthConditions.remove(c.$1);
            } else {
              _healthConditions.add(c.$1);
            }
          }),
          selectedColor: AppTheme.primary.withValues(alpha: 0.12),
          checkmarkColor: AppTheme.primary,
          labelStyle: TextStyle(
            color: selected ? AppTheme.primary : AppTheme.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
          side: BorderSide(
              color: selected ? AppTheme.primary : AppTheme.divider),
        );
      }).toList(),
    );
  }

  Widget _buildLtcGradeStatusSelector() {
    const options = [
      ('none', '없음', Icons.close, Colors.grey),
      ('applying', '신청 중', Icons.hourglass_empty, Color(0xFFF57C00)),
      ('has', '보유 중', Icons.check_circle_outline, AppTheme.primary),
    ];
    return Row(
      children: options.map((opt) {
        final isSelected = _ltcGradeStatus == opt.$1;
        final color = opt.$4;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => setState(() => _ltcGradeStatus = opt.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (color is MaterialColor
                          ? color.withValues(alpha: 0.1)
                          : color.withValues(alpha: 0.1))
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? color : AppTheme.divider,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(children: [
                  Icon(opt.$3, size: 18, color: isSelected ? color : AppTheme.textSecondary),
                  const SizedBox(height: 4),
                  Text(opt.$2,
                      style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? color : AppTheme.textSecondary,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal)),
                ]),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLtcGradePicker() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('등급 선택', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            ...List.generate(6, (i) {
              final grade = i + 1;
              final isSelected = _ltcGrade == grade;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _ltcGrade = grade),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary : Colors.transparent,
                      border: Border.all(
                          color: isSelected ? AppTheme.primary : AppTheme.divider),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        grade == 6 ? '인지\n지원' : '$grade등급',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.textSecondary,
                            fontSize: grade == 6 ? 9 : 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ]),
        ],
      ),
    );
  }

  Widget _buildIncomeLevelSlider() {
    final standards = context.watch<WelfareStandardsProvider>();
    final label = standards.isLoaded
        ? standards.getIncomeLevelLabel(_incomeLevel)
        : '소득분위 $_incomeLevel분위';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _buildLabelWithHelp(
          '소득분위',
          '소득분위란?',
          '소득분위는 전체 가구를 소득 순서대로 10등분한 것입니다.\n\n'
          '• 1~2분위: 기초생활수급자·차상위계층 수준\n'
          '• 3~4분위: 기준중위소득 47~50% 이하\n'
          '• 5~6분위: 기준중위소득 60~70% 이하 (기초연금 기준)\n'
          '• 7~8분위: 기준중위소득 80~100% 이하\n'
          '• 9~10분위: 중위소득 이상\n\n'
          '정확히 모르시면 5분위(중간)로 설정해도 됩니다.',
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('$_incomeLevel분위',
              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
        ),
      ]),
      Slider(
        value: _incomeLevel.toDouble(),
        min: 1,
        max: 10,
        divisions: 9,
        activeColor: AppTheme.primary,
        onChanged: (v) => setState(() => _incomeLevel = v.round()),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary, height: 1.5)),
      ),
      const SizedBox(height: 4),
      const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('1분위 (최저)', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          Text('10분위 (최고)', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ),
    ]);
  }

  Widget _buildVeteranTypeChips() {
    const types = [
      ('국가유공자', Icons.military_tech_outlined),
      ('참전유공자', Icons.flag_outlined),
      ('독립유공자', Icons.star_border_outlined),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((t) {
        final selected = _veteranTypes.contains(t.$1);
        return FilterChip(
          avatar: Icon(t.$2, size: 16,
              color: selected ? Colors.indigo.shade700 : AppTheme.textSecondary),
          label: Text(t.$1),
          selected: selected,
          onSelected: (_) => setState(() {
            if (selected) {
              _veteranTypes.remove(t.$1);
            } else {
              _veteranTypes.add(t.$1);
            }
          }),
          selectedColor: Colors.indigo.shade50,
          checkmarkColor: Colors.indigo.shade700,
          labelStyle: TextStyle(
            color: selected ? Colors.indigo.shade700 : AppTheme.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
          side: BorderSide(
              color: selected ? Colors.indigo.shade300 : AppTheme.divider),
        );
      }).toList(),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }
}
