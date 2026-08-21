part of '../main.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.onSignOut});

  /// 로그아웃 후 로그인 화면으로 이동시키는 상위(AuthGate) 콜백입니다.
  final Future<void> Function() onSignOut;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _targetWeightController = TextEditingController();
  List<WeightRecord> _weightRecords = [];
  bool _loading = true;
  String? _message;
  String? _goalType;
  String? _activityLevel;
  UserProfile? _savedProfile;
  bool _isSaving = false;
  bool _isSigningOut = false;
  bool _isDeletingAccount = false;

  @override
  void initState() {
    super.initState();
    _heightController.addListener(_refreshGoalWarning);
    _weightController.addListener(_refreshGoalWarning);
    _targetWeightController.addListener(_refreshGoalWarning);
    _loadProfile();
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _targetWeightController.dispose();
    super.dispose();
  }

  String? get _goalWarning {
    final current = double.tryParse(_weightController.text.trim());
    final target = double.tryParse(_targetWeightController.text.trim());
    final goal = _goalType ?? 'maintain';
    if (current == null || target == null) return null;
    if (goal == 'gain' && target <= current) {
      return '증량은 목표 몸무게가 현재 몸무게보다 높을 때만 저장할 수 있어요. 유지 목표는 언제든 선택할 수 있어요.';
    }
    if (goal == 'loss' && target >= current) {
      return '감량은 목표 몸무게가 현재 몸무게보다 낮을 때만 저장할 수 있어요. 유지 목표는 언제든 선택할 수 있어요.';
    }
    return null;
  }

  void _refreshGoalWarning() {
    if (mounted) setState(() {});
  }
  /// 확인 창을 거쳐 인증 세션을 지우고 로그인 화면으로 돌아갑니다.
  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text(
          '계정과 식사 기록, 영양 목표, 체중 기록, 직접 등록한 음식 및 사진이 영구 삭제됩니다.\n\n삭제한 데이터는 복구할 수 없습니다.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62828)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('탈퇴하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isDeletingAccount = true);
    try {
      await AuthApi.deleteAccount();
      await widget.onSignOut();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회원 탈퇴 처리에 실패했습니다. 다시 시도해주세요.')),
      );
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('현재 기기에서 로그아웃할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSigningOut = true);
    try {
      await widget.onSignOut();
    } catch (_) {
      if (mounted) {
        setState(() => _isSigningOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그아웃에 실패했어요. 다시 시도해 주세요.')),
        );
      }
    }
  }

  // PostgreSQL에서 신체 정보와 월별 체중 기록을 불러옵니다.
  Future<void> _loadProfile() async {
    final profile = await FoodDataApi.profile();
    final weights = await FoodDataApi.weights();
    if (!mounted) return;
    setState(() {
      _heightController.text = profile.heightCm?.toStringAsFixed(1) ?? '';
      _weightController.text = profile.weightKg?.toStringAsFixed(1) ?? '';
      _targetWeightController.text =
          profile.targetWeightKg?.toStringAsFixed(1) ?? '';
      _goalType = profile.goalType ?? 'maintain';
       _activityLevel = profile.activityLevel ?? 'low';
      _savedProfile = profile;
      _weightRecords = weights;
      _loading = false;
    });
  }


  bool _sameNumber(double? left, double? right) {
    if (left == null || right == null) return left == right;
    return (left - right).abs() < 0.01;
  }

  bool get _hasProfileChanges {
    final saved = _savedProfile;
    if (saved == null) return true;
    return !_sameNumber(double.tryParse(_heightController.text.trim()), saved.heightCm) ||
        !_sameNumber(double.tryParse(_weightController.text.trim()), saved.weightKg) ||
        !_sameNumber(double.tryParse(_targetWeightController.text.trim()), saved.targetWeightKg) ||
        (_goalType ?? 'maintain') != (saved.goalType ?? 'maintain') ||
         (_activityLevel ?? 'low') != (saved.activityLevel ?? 'low');
  }
  Future<void> _saveProfile() async {
    final height = double.tryParse(_heightController.text.trim());
    final weight = double.tryParse(_weightController.text.trim());
    final target = double.tryParse(_targetWeightController.text.trim());
    if (height == null || weight == null || target == null ||
        height <= 0 || weight <= 0 || target <= 0) {
      setState(() => _message = '키, 현재 몸무게, 목표 몸무게를 숫자로 입력해 주세요.');
      return;
    }
    if (!_hasProfileChanges) {
      setState(() => _message = '변경한 내용이 없어요. 값을 변경한 뒤 저장해 주세요.');
      return;
    }
    final goalWarning = _goalWarning;
    if (goalWarning != null) {
      setState(() => _message = goalWarning);
      return;
    }
    setState(() {
      _isSaving = true;
      _message = null;
    });
    try {
      final saved = UserProfile(
        heightCm: height,
        weightKg: weight,
        targetWeightKg: target,
        goalType: _goalType ?? 'maintain',
         activityLevel: _activityLevel ?? 'low',
      );
      await FoodDataApi.saveProfile(saved);
      if (!mounted) return;
      setState(() {
        _savedProfile = saved;
        _isSaving = false;
        _message = '기본 신체정보와 맞춤 일일 영양 목표를 저장했어요.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기본 신체정보를 저장했어요.')),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _message = '저장에 실패했어요. $error';
        });
      }
    }
  }
  Future<void> _recordThisMonth() async {
    final weight = double.tryParse(_weightController.text.trim());
    if (weight == null || weight <= 0) {
      setState(() => _message = '먼저 현재 몸무게를 입력해 주세요.');
      return;
    }
    final now = DateTime.now();
    // 체중 변화 차트는 월별 기록이므로, 어느 날 저장해도 해당 월의 1일로 통일합니다.
    final monthStart = DateTime(now.year, now.month);
    final record = WeightRecord(date: monthStart, weightKg: weight);
    await FoodDataApi.saveWeight(record);
    final updated = _weightRecords
        .where((item) =>
            item.date.year != monthStart.year || item.date.month != monthStart.month)
        .toList()
      ..add(record);
    updated.sort((a, b) => b.date.compareTo(a.date));
    if (mounted) setState(() => _weightRecords = updated);
  }

  @override
  Widget build(BuildContext context) {
    final records = [..._weightRecords]
      ..sort((a, b) => b.date.compareTo(a.date));
    final latestWeight = records.isEmpty ? null : records.first.weightKg;
    final previousWeight = records.length < 2 ? null : records[1].weightKg;
    final difference = latestWeight != null && previousWeight != null
        ? latestWeight - previousWeight
        : null;
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                children: [
                  const Text('내 정보',
                      style:
                          TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('기본 신체 정보와 월별 체중 변화를 기록하세요.',
                      style: TextStyle(color: AppColors.muted)),
                  if (_goalType != null) ...[
                    const SizedBox(height: 10),
                    Text(
                       '현재 목표: ${_goalType == 'loss' ? '감량' : _goalType == 'gain' ? '증량' : '유지'} · 현재 ${_weightController.text}kg → 목표 ${_targetWeightController.text}kg',
                      style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w800),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('기본 신체 정보',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                                child: _ProfileField(
                                    controller: _heightController,
                                    label: '키',
                                    suffix: 'cm')),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _ProfileField(
                                    controller: _weightController,
                                    label: '현재 몸무게',
                                    suffix: 'kg')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _ProfileField(
                            controller: _targetWeightController,
                            label: '목표 몸무게',
                            suffix: 'kg'),
                         const SizedBox(height: 14),
                        const Text('몸무게 목표',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: SegmentedButton<String>(
                            style: const ButtonStyle(
                              minimumSize: WidgetStatePropertyAll(Size.fromHeight(48)),
                            ),
                            segments: const [
                              ButtonSegment(value: 'loss', label: Text('감량'), icon: Icon(Icons.trending_down)),
                              ButtonSegment(value: 'maintain', label: Text('유지'), icon: Icon(Icons.balance)),
                              ButtonSegment(value: 'gain', label: Text('증량'), icon: Icon(Icons.trending_up)),
                            ],
                            selected: {_goalType ?? 'maintain'},
                            onSelectionChanged: (value) =>
                                setState(() => _goalType = value.first),
                          ),
                        ),                        
                         const SizedBox(height: 16),
                         const Text('평소 활동량',
                             style: TextStyle(fontWeight: FontWeight.w800)),
                         const SizedBox(height: 8),
                         DropdownButtonFormField<String>(
                           initialValue: _activityLevel ?? 'low',
                           isExpanded: true,
                           decoration: InputDecoration(
                             filled: true,
                             fillColor: const Color(0xFFF7F9F8),
                             contentPadding: const EdgeInsets.symmetric(
                                 horizontal: 14, vertical: 4),
                             border: OutlineInputBorder(
                               borderRadius: BorderRadius.circular(12),
                               borderSide: BorderSide.none,
                             ),
                           ),
                           items: const [
                             DropdownMenuItem(value: 'low', child: Text('낮음 · 운동 거의 없음')),
                             DropdownMenuItem(value: 'light', child: Text('가벼움 · 주 1~2회 운동')),
                             DropdownMenuItem(value: 'moderate', child: Text('보통 · 주 2~3회 운동')),
                             DropdownMenuItem(value: 'high', child: Text('높음 · 주 4회 이상 운동')),
                             DropdownMenuItem(value: 'very_high', child: Text('매우 높음 · 육체 활동량이 많음')),
                           ],
                           onChanged: (value) =>
                               setState(() => _activityLevel = value),
                         ),
if (_goalWarning != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: const Color(0xFFFFECEC),
                                borderRadius: BorderRadius.circular(12)),
                            child: Text(_goalWarning!,
                                style: const TextStyle(
                                    color: Color(0xFFC62828), height: 1.35)),
                          ),
                        ],
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed: _isSaving ? null : _saveProfile,
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('내정보 저장'),
                          ),
                        ),                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _BmiSummaryCard(
                    heightCm: double.tryParse(_heightController.text.trim()),
                    currentWeightKg:
                        double.tryParse(_weightController.text.trim()),
                    targetWeightKg:
                        double.tryParse(_targetWeightController.text.trim()),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    _MessageCard(
                        message: _message!, isError: _message!.contains('입력') || _message!.contains('증량') || _message!.contains('감량') || _message!.contains('실패')),
                  ],
                  const SizedBox(height: 22),
                  const Text('월별 몸무게 변화',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE7F4F1),
                        borderRadius: BorderRadius.circular(22)),
                    child: Row(
                      children: [
                        const CircleAvatar(
                            radius: 25,
                            backgroundColor: Colors.white,
                            child: Icon(Icons.monitor_weight_outlined,
                                color: AppColors.teal)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('최근 기록',
                                  style: TextStyle(color: AppColors.muted)),
                              Text(
                                  latestWeight == null
                                      ? '아직 기록 없음'
                                      : '${latestWeight.toStringAsFixed(1)} kg',
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900)),
                              if (difference != null)
                                Text(
                                    '지난 기록 대비 ${difference > 0 ? '+' : ''}${difference.toStringAsFixed(1)} kg',
                                    style: TextStyle(
                                        color: difference <= 0
                                            ? const Color(0xFF287545)
                                            : const Color(0xFFC06A2E),
                                        fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _WeightLineChart(records: records),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _recordThisMonth,
                      icon: const Icon(Icons.add_chart_outlined),
                      label: const Text('이번 달 몸무게 기록'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (records.isEmpty)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('이번 달 몸무게를 입력한 뒤 기록 버튼을 눌러 보세요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted)))
                  else
                    ...records.asMap().entries.map((entry) {
                      final index = entry.key;
                      final record = entry.value;
                      final older = index + 1 < records.length
                          ? records[index + 1]
                          : null;
                      final change = older == null
                          ? null
                          : record.weightKg - older.weightKg;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 9),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(17)),
                        child: Row(
                          children: [
                            Text(
                                '${record.date.year}.${record.date.month.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            const Spacer(),
                            Text('${record.weightKg.toStringAsFixed(1)} kg',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w900)),
                            if (change != null) ...[
                              const SizedBox(width: 10),
                              Text(
                                  '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}',
                                  style: TextStyle(
                                      color: change <= 0
                                          ? const Color(0xFF287545)
                                          : const Color(0xFFC06A2E),
                                      fontWeight: FontWeight.w700)),
                            ],
                          ],
                        ),
                      );
                    }),
                   const SizedBox(height: 28),
                   SizedBox(
                     width: double.infinity,
                     height: 50,
                     child: OutlinedButton.icon(
                       onPressed: () => Navigator.of(context).push(
                         MaterialPageRoute(builder: (_) => const MyFoodsPage()),
                       ),
                       icon: const Icon(Icons.restaurant_menu_rounded),
                       label: const Text('내 등록 음식 관리'),
                       style: OutlinedButton.styleFrom(
                         foregroundColor: const Color(0xFF145A57),
                         side: const BorderSide(color: Color(0xFF9DD7D1)),
                         shape: RoundedRectangleBorder(
                           borderRadius: BorderRadius.circular(14),
                         ),
                       ),
                     ),
                   ),
                    const SizedBox(height: 20),
                    const Text('앱 및 계정',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 0,
                      color: const Color(0xFFF7FAF9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Color(0xFFE0EBE9)),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.privacy_tip_outlined),
                            title: const Text('개인정보 처리방침'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const LegalDocumentPage.privacy(),
                            )),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: const Text('이용약관'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const LegalDocumentPage.terms(),
                            )),
                          ),
                          const Divider(height: 1),
                          const ListTile(
                            leading: Icon(Icons.info_outline_rounded),
                            title: Text('앱 버전'),
                            trailing: Text('1.0.0+1',
                                style: TextStyle(color: Color(0xFF71817F))),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _isDeletingAccount ? null : _confirmDeleteAccount,
                        icon: _isDeletingAccount
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.person_remove_outlined),
                        label: Text(_isDeletingAccount ? '회원 탈퇴 처리 중...' : '회원 탈퇴 및 내 데이터 삭제'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFC62828),
                          side: const BorderSide(color: Color(0xFFEF9A9A)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                   SizedBox(
                     width: double.infinity,
                     height: 50,
                     child: OutlinedButton.icon(
                       onPressed: _isSigningOut ? null : _confirmSignOut,
                       icon: _isSigningOut
                           ? const SizedBox(
                               width: 18,
                               height: 18,
                               child: CircularProgressIndicator(strokeWidth: 2),
                             )
                           : const Icon(Icons.logout_rounded),
                       label: Text(_isSigningOut ? '로그아웃 중...' : '로그아웃'),
                       style: OutlinedButton.styleFrom(
                         foregroundColor: const Color(0xFFC62828),
                         side: const BorderSide(color: Color(0xFFEF9A9A)),
                         shape: RoundedRectangleBorder(
                           borderRadius: BorderRadius.circular(14),
                         ),
                       ),
                     ),
                   ),
                ],
              ),
      ),
    );
  }
}

// 키와 현재 몸무게로 BMI 및 목표 몸무게와의 차이를 자동 계산해 표시합니다.
class _BmiSummaryCard extends StatelessWidget {
  const _BmiSummaryCard(
      {required this.heightCm,
      required this.currentWeightKg,
      required this.targetWeightKg});
  final double? heightCm;
  final double? currentWeightKg;
  final double? targetWeightKg;

  @override
  Widget build(BuildContext context) {
    final bmi = heightCm == null || currentWeightKg == null || heightCm! <= 0
        ? null
        : currentWeightKg! / ((heightCm! / 100) * (heightCm! / 100));
    final status = bmi == null
        ? '키와 현재 몸무게를 저장하면 BMI가 계산됩니다.'
        : bmi < 18.5
            ? '저체중'
            : bmi < 23
                ? '정상'
                : bmi < 25
                    ? '과체중'
                    : '비만';
    final difference = currentWeightKg != null && targetWeightKg != null
        ? currentWeightKg! - targetWeightKg!
        : null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: const Color(0xFFEAF5F2),
          borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        const CircleAvatar(
            radius: 25,
            backgroundColor: Colors.white,
            child:
                Icon(Icons.health_and_safety_outlined, color: AppColors.teal)),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              bmi == null
                  ? 'BMI 정보'
                  : 'BMI ${bmi.toStringAsFixed(1)} · $status',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(
              difference == null
                  ? '목표 몸무게를 입력하면 차이를 알려드려요.'
                  : difference == 0
                      ? '목표 몸무게에 도달했어요!'
                      : difference > 0
                          ? '목표까지 ${difference.toStringAsFixed(1)} kg 남았어요.'
                          : '목표보다 ${(-difference).toStringAsFixed(1)} kg 적어요.',
              style: const TextStyle(color: AppColors.muted)),
        ])),
      ]),
    );
  }
}

// 저장된 월별 체중 기록을 시간순으로 정렬해 선 그래프로 전달합니다.
class _WeightLineChart extends StatelessWidget {
  const _WeightLineChart({required this.records});
  final List<WeightRecord> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const SizedBox(
          height: 120,
          child: Center(
              child: Text('체중 기록을 추가하면 월별 변화 그래프가 표시됩니다.',
                  style: TextStyle(color: AppColors.muted))));
    }
    final points = [...records]..sort((a, b) => a.date.compareTo(b.date));
    return Container(
      height: 190,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('월별 몸무게 변화', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Expanded(
            child: CustomPaint(
                size: Size.infinite, painter: _WeightChartPainter(points))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${points.first.date.year}.${points.first.date.month}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          Text('${points.last.date.year}.${points.last.date.month}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ]),
      ]),
    );
  }
}

// Canvas에 눈금, 체중 변화 선, 각 월의 점을 직접 그리는 그래프 구현입니다.
class _WeightChartPainter extends CustomPainter {
  const _WeightChartPainter(this.points);
  final List<WeightRecord> points;
  @override
  void paint(Canvas canvas, Size size) {
    var minimum =
        points.map((point) => point.weightKg).reduce((a, b) => a < b ? a : b);
    var maximum =
        points.map((point) => point.weightKg).reduce((a, b) => a > b ? a : b);
    if (minimum == maximum) {
      minimum -= 1;
      maximum += 1;
    }
    final grid = Paint()
      ..color = const Color(0xFFE8EEEC)
      ..strokeWidth = 1;
    for (var index = 0; index < 4; index++) {
      final y = size.height * index / 3;
      canvas.drawLine(Offset.zero + Offset(0, y), Offset(size.width, y), grid);
    }
    Offset position(int index) {
      final x = points.length == 1
          ? size.width / 2
          : size.width * index / (points.length - 1);
      final ratio = (points[index].weightKg - minimum) / (maximum - minimum);
      return Offset(x, size.height - 8 - ratio * (size.height - 16));
    }

    final line = Paint()
      ..color = AppColors.teal
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(position(0).dx, position(0).dy);
    for (var index = 1; index < points.length; index++) {
      path.lineTo(position(index).dx, position(index).dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = AppColors.teal;
    for (var index = 0; index < points.length; index++) {
      canvas.drawCircle(position(index), 4.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _ProfileField extends StatelessWidget {
  const _ProfileField(
      {required this.controller, required this.label, required this.suffix});
  final TextEditingController controller;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
            labelText: label,
            suffixText: suffix,
            filled: true,
            fillColor: const Color(0xFFF5F7F6),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none)),
      );
}
