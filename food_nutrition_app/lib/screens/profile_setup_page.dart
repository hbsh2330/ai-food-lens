part of '../main.dart';

// Google 로그인 직후 한 번만 보여 주는 개인 목표 및 영양 기본값 설정 화면입니다.
class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key, required this.displayName, required this.onCompleted});
  final String displayName;
  final VoidCallback onCompleted;

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _targetWeight = TextEditingController();
  String _sex = 'male';
  String _activity = 'low';
  String _goal = 'maintain';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    _targetWeight.dispose();
    super.dispose();
  }

  double? _number(String value) => double.tryParse(value.trim());

  String? get _goalWarning {
    final current = _number(_weight.text);
    final target = _number(_targetWeight.text);
    if (current == null || target == null) return null;
    if (_goal == 'gain' && target <= current) {
      return '증량 목표는 목표 몸무게가 현재 몸무게보다 높아야 해요. 유지 목표는 언제든 선택할 수 있어요.';
    }
    if (_goal == 'loss' && target >= current) {
      return '감량 목표는 목표 몸무게가 현재 몸무게보다 낮아야 해요. 유지 목표는 언제든 선택할 수 있어요.';
    }
    return null;
  }
  Future<void> _complete() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final goalWarning = _goalWarning;
    if (goalWarning != null) { setState(() => _error = goalWarning); return; }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final targets = await FoodDataApi.completeProfileSetup({
        'age': int.parse(_age.text.trim()),
        'height_cm': _number(_height.text),
        'weight_kg': _number(_weight.text),
        'target_weight_kg': _number(_targetWeight.text),
        'biological_sex': _sex,
        'activity_level': _activity,
        'goal_type': _goal,
      });
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('맞춤 목표를 만들었어요'),
                content: Text(
                    '하루 ${targets.calories.toStringAsFixed(0)} kcal\n'
                    '탄수화물 ${targets.carbs.toStringAsFixed(0)}g · '
                    '단백질 ${targets.protein.toStringAsFixed(0)}g · '
                    '지방 ${targets.fat.toStringAsFixed(0)}g\n\n'
                    '내 정보와 홈의 수정 버튼에서 언제든 바꿀 수 있어요.'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('시작하기'))],
              ));
      if (mounted) widget.onCompleted();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validNumber(String? value, {double min = 1, double max = 999}) {
    final number = _number(value ?? '');
    if (number == null || number < min || number > max) return '올바른 숫자를 입력해 주세요.';
    return null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('맞춤 목표 설정')),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
              children: [
                Text('${widget.displayName}님, 반가워요!',
                    style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('기본 정보를 바탕으로 하루 영양 목표를 계산해 드릴게요.',
                    style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 24),
                _section('기초대사량 계산 정보'),
                Row(children: [
                  Expanded(child: _field(_age, '나이', '세', min: 19, max: 80, integer: true)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _sex,
                      decoration: _decoration('계산용 성별'),
                      items: const [
                        DropdownMenuItem(value: 'male', child: Text('남성')),
                        DropdownMenuItem(value: 'female', child: Text('여성')),
                      ],
                      onChanged: (value) => setState(() => _sex = value!),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _activity,
                  decoration: _decoration('평소 활동량'),
                  items: const [
                             DropdownMenuItem(value: 'low', child: Text('낮음 · 운동 거의 없음')),
                             DropdownMenuItem(value: 'light', child: Text('가벼움 · 주 1~2회 운동')),
                             DropdownMenuItem(value: 'moderate', child: Text('보통 · 주 2~3회 운동')),
                             DropdownMenuItem(value: 'high', child: Text('높음 · 주 4회 이상 운동')),
                             DropdownMenuItem(value: 'very_high', child: Text('매우 높음 · 육체 활동량이 많음')),
                  ],
                  onChanged: (value) => setState(() => _activity = value!),
                ),
                const SizedBox(height: 24),
                _section('몸무게 목표'),
                _field(_height, '키', 'cm', min: 100, max: 250),
                const SizedBox(height: 12),
                _field(_weight, '현재 몸무게', 'kg', min: 25, max: 350),
                const SizedBox(height: 12),
                _field(_targetWeight, '목표 몸무게', 'kg', min: 25, max: 350),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'loss', label: Text('감량'), icon: Icon(Icons.trending_down)),
                      ButtonSegment(value: 'maintain', label: Text('유지'), icon: Icon(Icons.balance)),
                      ButtonSegment(value: 'gain', label: Text('증량'), icon: Icon(Icons.trending_up)),
                    ],
                    selected: {_goal},
                    onSelectionChanged: (value) => setState(() => _goal = value.first),
                  ),
                ),                if (_goalWarning != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFFECEC),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(_goalWarning!,
                        style: const TextStyle(color: Color(0xFFC62828), height: 1.35)),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFEAF5F2), borderRadius: BorderRadius.circular(16)),
                  child: const Text(
                    '성인(19~80세)용 추정치입니다. 감량은 유지 열량에서 약 500 kcal, 증량은 약 300 kcal를 조정해 계산합니다. '
                    '임신·수유 중이거나 질환 및 섭식장애가 있다면 의료진과 목표를 정해 주세요.',
                    style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.muted),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _complete,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  child: _saving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('맞춤 영양 목표 만들기'),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
      );

  Widget _field(TextEditingController controller, String label, String suffix,
          {required double min, required double max, bool integer = false}) =>
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: !integer),
        validator: (value) => _validNumber(value, min: min, max: max),
        onChanged: (_) => setState(() {}),
        decoration: _decoration(label).copyWith(suffixText: suffix),
      );

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF5F7F6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );
}