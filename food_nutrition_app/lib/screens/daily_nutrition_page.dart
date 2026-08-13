part of '../main.dart';

class DailyNutritionPage extends StatefulWidget {
  const DailyNutritionPage({super.key});

  @override
  State<DailyNutritionPage> createState() => _DailyNutritionPageState();
}

// 홈 화면의 선택 날짜, 식사 기록, 영양 목표를 관리하는 상태입니다.
class _DailyNutritionPageState extends State<DailyNutritionPage> {
  final ImagePicker _picker = ImagePicker();
  DateTime _selectedDate = DateTime.now();
  final List<MealRecord> _records = [];
  final Map<DateTime, List<MealRecord>> _calendarRecords = {};
  bool _isLoading = true;
  MealType? _analyzingMeal;
  String? _message;

  static const _defaultCalorieGoal = 2200.0;
  static const _defaultCarbGoal = 330.0;
  static const _defaultProteinGoal = 65.0;
  static const _defaultFatGoal = 70.0;
  double _calorieGoal = _defaultCalorieGoal;
  double _carbGoal = _defaultCarbGoal;
  double _proteinGoal = _defaultProteinGoal;
  double _fatGoal = _defaultFatGoal;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  // 영양 목표 수정 바텀시트를 열고, 선택에 따라 전체 또는 선택한 하루에 DB로 저장합니다.
  Future<void> _openNutritionTargetSettings() async {
    final targets = NutritionTargets(
        calories: _calorieGoal,
        carbs: _carbGoal,
        protein: _proteinGoal,
        fat: _fatGoal);
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: _NutritionTargetSheet(
                initialTargets: targets,
                onSave: (nextTargets, todayOnly) async {
                  await FoodDataApi.saveTargets(nextTargets,
                      day: todayOnly ? _selectedDate : null);
                  if (!mounted) return;
                  setState(() {
                    _calorieGoal = nextTargets.calories;
                    _carbGoal = nextTargets.carbs;
                    _proteinGoal = nextTargets.protein;
                    _fatGoal = nextTargets.fat;
                  });
                })));
  }

  // 선택 날짜의 식사·영양 목표를 PostgreSQL에서 읽고, 모든 날짜 기록은 달력 표시용으로 유지합니다.
  Future<void> _loadRecords() async {
    try {
      final allRecords =
          await FoodDataApi.mealsByDate(DateTime(2020), DateTime.now());
      final dailyTargets = await FoodDataApi.targets(_selectedDate);
      final key =
          DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      if (!mounted) return;
      setState(() {
        _records
          ..clear()
          ..addAll(allRecords[key] ?? const []);
        _calendarRecords
          ..clear()
          ..addAll(allRecords);
        _calorieGoal = dailyTargets.calories;
        _carbGoal = dailyTargets.carbs;
        _proteinGoal = dailyTargets.protein;
        _fatGoal = dailyTargets.fat;
        _isLoading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = 'DB 기록을 불러오지 못했어요. $error';
          _isLoading = false;
        });
      }
    }
  }

  // 날짜를 자정 기준으로 정규화한 후 해당 날짜의 기록을 다시 불러옵니다.
  Future<void> _setDate(DateTime date) async {
    final nextDate = DateTime(date.year, date.month, date.day);
    if (nextDate == _selectedDate) return;
    setState(() {
      _selectedDate = nextDate;
      _isLoading = true;
      _message = null;
    });
    await _loadRecords();
  }

  // 식사명이 표시되는 커스텀 달력을 열고, 날짜 선택 결과를 홈 화면에 반영합니다.
  Future<void> _openCalendar() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _MealCalendarSheet(
        selectedDate: _selectedDate,
        recordsByDate: _calendarRecords,
        onDateSelected: (date) async {
          Navigator.of(sheetContext).pop();
          await _setDate(date);
        },
      ),
    );
  }

  List<MealRecord> _recordsFor(MealType meal) =>
      _records.where((record) => record.meal == meal).toList();

  double get _totalCalories =>
      _records.fold(0, (sum, item) => sum + item.detection.energyKcal);
  double get _totalCarbs =>
      _records.fold(0, (sum, item) => sum + item.detection.carbohydrateG);
  double get _totalProtein =>
      _records.fold(0, (sum, item) => sum + item.detection.proteinG);
  double get _totalFat =>
      _records.fold(0, (sum, item) => sum + item.detection.fatG);

  // 음식 추가 화면에서 AI 사진 분석 또는 음식명 등록 결과를 받아 같은 식사 기록 형식으로 저장합니다.
  Future<void> _selectSource(MealType meal) async {
    final result = await Navigator.push<_FoodAddResult>(
      context,
      MaterialPageRoute(builder: (_) => FoodAddPage(meal: meal)),
    );
    if (result == null) return;
    if (result.kind == _FoodAddKind.ai && result.source != null) {
      await _pickAndAnalyze(meal, result.source!);
      return;
    }
    if (result.detection != null) {
      final draft = MealRecord(
        id: '',
        meal: meal,
        createdAt: DateTime.now(),
        imagePath: '',
        detection: result.detection!,
      );
      try {
        final saved = await FoodDataApi.addMeal(_selectedDate, draft,
            source: 'catalog');
        if (!mounted) return;
        setState(() {
          _records.add(saved);
          _message = '${meal.label} 식사를 저장했어요.';
        });
      } catch (error) {
        if (mounted) setState(() => _message = '식사 저장에 실패했어요: $error');
      }
    }
  }

  // 사진 선택 → FastAPI AI 분석 → 선택한 식사와 날짜에 로컬 저장까지 수행하는 핵심 흐름입니다.
  Future<void> _pickAndAnalyze(MealType meal, ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      _analyzingMeal = meal;
      _message = null;
    });

    try {
      final detection = await FoodApi.predict(File(picked.path));
      if (detection.foodName == null || detection.foodName!.isEmpty) {
        throw Exception('음식 이름과 영양정보가 연결되지 않은 결과입니다. 다른 사진으로 시도해 주세요.');
      }
      final record = MealRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        meal: meal,
        createdAt: DateTime.now(),
        imagePath: picked.path,
        detection: detection,
      );
      _records.add(record);

      if (!mounted) {
        return;
      }
      setState(
          () => _message = '${meal.label}에 ${detection.foodName}을(를) 저장했어요.');
    } catch (error) {
      if (mounted) setState(() => _message = '분석에 실패했어요. $error');
    } finally {
      if (mounted) setState(() => _analyzingMeal = null);
    }
  }

  // 아침·점심·저녁별로 저장된 음식과 영양소 합계를 바텀시트로 표시합니다.
  void _showMealDetails(MealType meal) {
    final mealRecords = _recordsFor(meal);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MealDetailsSheet(meal: meal, records: mealRecords),
    );
  }

  // DB에서 삭제한 뒤 현재 화면과 달력 데이터를 갱신합니다.
  Future<void> _deleteRecord(MealRecord record) async {
    final uuidPattern = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    // 예전에 화면에서만 만들었던 숫자 ID는 DB 레코드가 아니므로 로컬 목록에서만 제거합니다.
    if (uuidPattern.hasMatch(record.id)) {
      await FoodDataApi.deleteMeal(record.id);
    }
    if (!mounted) return;
    setState(() => _records.removeWhere((item) => item.id == record.id));
    _calendarRecords[DateTime(
            _selectedDate.year, _selectedDate.month, _selectedDate.day)] =
        List.of(_records);
  }

  @override
  Widget build(BuildContext context) {
    final dateText = '${_selectedDate.month}월 ${_selectedDate.day}일';
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadRecords,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('오늘의 식사',
                                  style: TextStyle(
                                      fontSize: 27,
                                      fontWeight: FontWeight.w800)),
                              SizedBox(height: 3),
                              Text('사진으로 간편하게 영양을 기록하세요',
                                  style: TextStyle(color: AppColors.muted)),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: _openCalendar,
                          borderRadius: BorderRadius.circular(30),
                          child: Container(
                            padding: const EdgeInsets.all(11),
                            decoration: const BoxDecoration(
                                color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.calendar_month_outlined,
                                color: AppColors.teal),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _DateStrip(
                        selectedDate: _selectedDate, onDateSelected: _setDate),
                    const SizedBox(height: 18),
                    _CalorieSummary(
                      calories: _totalCalories,
                      goal: _calorieGoal,
                      dateText: dateText,
                      onDetails: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NutritionDetailPage(
                            selectedDate: _selectedDate,
                            recordsByDate: Map.of(_calendarRecords),
                            targets: NutritionTargets(
                              calories: _calorieGoal,
                              carbs: _carbGoal,
                              protein: _proteinGoal,
                              fat: _fatGoal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _NutrientSummary(
                      carbs: _totalCarbs,
                      protein: _totalProtein,
                      fat: _totalFat,
                      carbGoal: _carbGoal,
                      proteinGoal: _proteinGoal,
                      fatGoal: _fatGoal,
                      onSettingsTap: _openNutritionTargetSettings,
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      _MessageCard(
                          message: _message!,
                          isError: _message!.startsWith('분석에 실패')),
                    ],
                    const SizedBox(height: 24),
                    const Text('식사 기록',
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    for (final meal in MealType.values) ...[
                      _MealCard(
                        meal: meal,
                        records: _recordsFor(meal),
                        isAnalyzing: _analyzingMeal == meal,
                        onAdd: () => _selectSource(meal),
                        onDelete: _deleteRecord,
                        onDetails: () => _showMealDetails(meal),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

// 날짜 칸에 식사별 색상과 음식명을 보여 주는 달력 바텀시트입니다.
class _MealCalendarSheet extends StatefulWidget {
  const _MealCalendarSheet(
      {required this.selectedDate,
      required this.recordsByDate,
      required this.onDateSelected});
  final DateTime selectedDate;
  final Map<DateTime, List<MealRecord>> recordsByDate;
  final ValueChanged<DateTime> onDateSelected;

  @override
  State<_MealCalendarSheet> createState() => _MealCalendarSheetState();
}

class _MealCalendarSheetState extends State<_MealCalendarSheet> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.selectedDate;
    _selectedDay = widget.selectedDate;
  }

  DateTime _key(DateTime day) => DateTime(day.year, day.month, day.day);

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          height: MediaQuery.sizeOf(context).height * 0.94,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
          decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFCCD4D1),
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 16),
            const Text('식사 달력',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('날짜 칸에서 아침·점심·저녁 음식명을 확인하세요.',
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            Row(children: [
              IconButton(
                tooltip: '이전 달',
                onPressed: () => _pageController?.previousPage(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                  child: Text('${_focusedDay.year}년 ${_focusedDay.month}월',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w900))),
              IconButton(
                tooltip: '다음 달',
                onPressed: () => _pageController?.nextPage(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut),
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return InteractiveViewer(
                      minScale: 1,
                      maxScale: 2.5,
                      panAxis: PanAxis.horizontal,
                      boundaryMargin:
                          const EdgeInsets.symmetric(horizontal: 80),
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: TableCalendar<MealRecord>(
                          firstDay: DateTime(2020),
                          lastDay: DateTime(2100),
                          focusedDay: _focusedDay,
                          locale: 'ko_KR',
                          headerVisible: false,
                          startingDayOfWeek: StartingDayOfWeek.sunday,
                          daysOfWeekHeight: 32,
                          rowHeight: 88,
                          availableGestures: AvailableGestures.horizontalSwipe,
                          selectedDayPredicate: (day) =>
                              isSameDay(_selectedDay, day),
                          onCalendarCreated: (controller) =>
                              _pageController = controller,
                          onDaySelected: (selectedDay, focusedDay) {
                            setState(() {
                              _selectedDay = selectedDay;
                              _focusedDay = focusedDay;
                            });
                            widget.onDateSelected(selectedDay);
                          },
                          onPageChanged: (focusedDay) =>
                              setState(() => _focusedDay = focusedDay),
                          eventLoader: (day) =>
                              widget.recordsByDate[_key(day)] ??
                              const <MealRecord>[],
                          calendarStyle: const CalendarStyle(
                            outsideDaysVisible: false,
                            cellMargin: EdgeInsets.all(3),
                            defaultDecoration: BoxDecoration(),
                            selectedDecoration: BoxDecoration(),
                            todayDecoration: BoxDecoration(),
                          ),
                          calendarBuilders: CalendarBuilders<MealRecord>(
                            defaultBuilder: (context, day, _) =>
                                _MealCalendarCell(
                                    day: day,
                                    records: widget.recordsByDate[_key(day)] ??
                                        const []),
                            todayBuilder: (context, day, _) =>
                                _MealCalendarCell(
                                    day: day,
                                    records: widget.recordsByDate[_key(day)] ??
                                        const [],
                                    isToday: true),
                            selectedBuilder: (context, day, _) =>
                                _MealCalendarCell(
                                    day: day,
                                    records: widget.recordsByDate[_key(day)] ??
                                        const [],
                                    isSelected: true),
                            markerBuilder: (context, day, events) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ]),
        ),
      );
}

// 빈 날짜도 동일한 크기를 유지하도록 만든 개별 달력 칸입니다.
class _MealCalendarCell extends StatelessWidget {
  const _MealCalendarCell(
      {required this.day,
      required this.records,
      this.isSelected = false,
      this.isToday = false});
  final DateTime day;
  final List<MealRecord> records;
  final bool isSelected;
  final bool isToday;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.fromLTRB(3, 3, 2, 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.teal.withValues(alpha: 0.12)
              : Colors.white,
          border: Border.all(
              color: isToday ? AppColors.teal : const Color(0xFFE5EBE8),
              width: isToday ? 1.5 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${day.day}',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: isSelected || isToday
                      ? AppColors.darkTeal
                      : Colors.black87)),
          const SizedBox(height: 2),
          ...MealType.values.map((meal) {
            final names = records
                .where((record) => record.meal == meal)
                .map((record) => record.detection.foodName)
                .whereType<String>()
                .toList();
            if (names.isEmpty) return const SizedBox.shrink();
            final name = names.length == 1
                ? names.first
                : '${names.first} +${names.length - 1}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Row(children: [
                Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                        color: meal.color, shape: BoxShape.circle)),
                const SizedBox(width: 2),
                Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 7.5, fontWeight: FontWeight.w700))),
              ]),
            );
          }),
        ]),
      );
}

class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selectedDate, required this.onDateSelected});
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final dates = List.generate(
        7, (index) => selectedDate.subtract(Duration(days: 3 - index)));
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: dates.map((date) {
          final selected = date.day == selectedDate.day &&
              date.month == selectedDate.month &&
              date.year == selectedDate.year;
          return InkWell(
            onTap: () => onDateSelected(date),
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: Column(
                children: [
                  Text(weekdays[date.weekday - 1],
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 7),
                  Container(
                    width: 31,
                    height: 31,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: selected ? AppColors.teal : Colors.transparent,
                        shape: BoxShape.circle),
                    child: Text('${date.day}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: selected ? Colors.white : Colors.black87)),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// 섭취량/목표 비율을 표시합니다. 막대는 100%까지만, 텍스트는 100% 초과도 그대로 보여 줍니다.
class _CalorieSummary extends StatelessWidget {
  const _CalorieSummary(
      {required this.calories,
      required this.goal,
      required this.dateText,
      required this.onDetails});
  final double calories;
  final double goal;
  final String dateText;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final actualProgress = calories / goal;
    final progress = actualProgress.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient:
            const LinearGradient(colors: [AppColors.darkTeal, AppColors.teal]),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle),
            child: Icon(Icons.local_fire_department_outlined,
                color: calories > goal ? Colors.redAccent : Colors.white,
                size: 31),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text('$dateText 섭취 칼로리',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600)),
                  ),
                  TextButton(
                    onPressed: onDetails,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('상세',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ]),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                          text: calories.toStringAsFixed(0),
                          style: const TextStyle(
                              fontSize: 34, fontWeight: FontWeight.w900)),
                      const TextSpan(
                          text: ' kcal',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      color: AppColors.orange,
                      backgroundColor: Colors.white24),
                ),
                const SizedBox(height: 5),
                Text(
                    '목표 ${goal.toStringAsFixed(0)} kcal 중 ${(actualProgress * 100).toStringAsFixed(0)}%',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NutrientSummary extends StatelessWidget {
  const _NutrientSummary(
      {required this.carbs,
      required this.protein,
      required this.fat,
      required this.carbGoal,
      required this.proteinGoal,
      required this.fatGoal,
      required this.onSettingsTap});
  final double carbs;
  final double protein;
  final double fat;
  final double carbGoal;
  final double proteinGoal;
  final double fatGoal;
  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(22)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                  child: Text('일일 영양 섭취량',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800))),
              TextButton(
                onPressed: onSettingsTap,
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.teal,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('수정',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                    child: _NutrientBar(
                        label: '탄수화물',
                        amount: carbs,
                        goal: carbGoal,
                        color: const Color(0xFFF4B942))),
                const SizedBox(width: 10),
                Expanded(
                    child: _NutrientBar(
                        label: '단백질',
                        amount: protein,
                        goal: proteinGoal,
                        color: const Color(0xFF51AF72))),
                const SizedBox(width: 10),
                Expanded(
                    child: _NutrientBar(
                        label: '지방',
                        amount: fat,
                        goal: fatGoal,
                        color: const Color(0xFF7396E4))),
              ],
            ),
          ],
        ),
      );
}

class _NutritionTargetSheet extends StatefulWidget {
  const _NutritionTargetSheet(
      {required this.initialTargets, required this.onSave});
  final NutritionTargets initialTargets;
  final Future<void> Function(NutritionTargets targets, bool todayOnly) onSave;

  @override
  State<_NutritionTargetSheet> createState() => _NutritionTargetSheetState();
}

class _NutritionTargetSheetState extends State<_NutritionTargetSheet> {
  late final TextEditingController _calorie;
  late final TextEditingController _carbs;
  late final TextEditingController _protein;
  late final TextEditingController _fat;
  bool _todayOnly = true;

  @override
  void initState() {
    super.initState();
    _calorie = TextEditingController(
        text: widget.initialTargets.calories.toStringAsFixed(0));
    _carbs = TextEditingController(
        text: widget.initialTargets.carbs.toStringAsFixed(0));
    _protein = TextEditingController(
        text: widget.initialTargets.protein.toStringAsFixed(0));
    _fat = TextEditingController(
        text: widget.initialTargets.fat.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _calorie.dispose();
    _carbs.dispose();
    _protein.dispose();
    _fat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final targets = NutritionTargets(
      calories: double.tryParse(_calorie.text) ?? 0,
      carbs: double.tryParse(_carbs.text) ?? 0,
      protein: double.tryParse(_protein.text) ?? 0,
      fat: double.tryParse(_fat.text) ?? 0,
    );
    if (targets.calories <= 0 ||
        targets.carbs <= 0 ||
        targets.protein <= 0 ||
        targets.fat <= 0) {
      return;
    }
    await widget.onSave(targets, _todayOnly);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('일일 영양 목표 설정',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text('기본값: 2,200 kcal · 탄수화물 330g · 단백질 65g · 지방 70g',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: _TargetField(
                          controller: _calorie, label: '칼로리', unit: 'kcal')),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _TargetField(
                          controller: _carbs, label: '탄수화물', unit: 'g')),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: _TargetField(
                          controller: _protein, label: '단백질', unit: 'g')),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _TargetField(
                          controller: _fat, label: '지방', unit: 'g')),
                ]),
                const SizedBox(height: 20),
                const Text('적용 범위',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(children: [
                  ChoiceChip(
                      label: const Text('오늘 하루만'),
                      selected: _todayOnly,
                      onSelected: (_) => setState(() => _todayOnly = true)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                      label: const Text('전체 적용'),
                      selected: !_todayOnly,
                      onSelected: (_) => setState(() => _todayOnly = false)),
                ]),
                const SizedBox(height: 8),
                Text(
                    _todayOnly
                        ? '선택한 날짜에만 이 목표값을 적용합니다.'
                        : '앞으로 모든 날짜의 기본 목표값으로 적용합니다.',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 20),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed: _submit, child: const Text('저장'))),
              ]),
        ),
      );
}

class _TargetField extends StatelessWidget {
  const _TargetField(
      {required this.controller, required this.label, required this.unit});
  final TextEditingController controller;
  final String label;
  final String unit;
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
            labelText: label,
            suffixText: unit,
            filled: true,
            fillColor: const Color(0xFFF4F7F5),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none)),
      );
}

class _NutrientBar extends StatelessWidget {
  const _NutrientBar(
      {required this.label,
      required this.amount,
      required this.goal,
      required this.color});
  final String label;
  final double amount;
  final double goal;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
                value: (amount / goal).clamp(0.0, 1.0),
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.16)),
          ),
          const SizedBox(height: 5),
          Text('${amount.toStringAsFixed(0)} / ${goal.toStringAsFixed(0)}g',
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      );
}

class _MealCard extends StatelessWidget {
  const _MealCard(
      {required this.meal,
      required this.records,
      required this.isAnalyzing,
      required this.onAdd,
      required this.onDelete,
      required this.onDetails});
  final MealType meal;
  final List<MealRecord> records;
  final bool isAnalyzing;
  final VoidCallback onAdd;
  final ValueChanged<MealRecord> onDelete;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final calories =
        records.fold(0.0, (sum, item) => sum + item.detection.energyKcal);
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: meal.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(meal.icon, color: meal.color),
              ),
              const SizedBox(width: 10),
              Text(meal.label,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('${calories.toStringAsFixed(0)} kcal',
                  style: TextStyle(
                      color: meal.color, fontWeight: FontWeight.w800)),
              IconButton(
                  tooltip: '식사 상세',
                  onPressed: onDetails,
                  icon: const Icon(Icons.menu_rounded)),
            ],
          ),
          const SizedBox(height: 11),
          if (records.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('아직 기록된 음식이 없어요.',
                  style: TextStyle(color: AppColors.muted)),
            )
          else
            ...records.map((record) => _FoodRecordTile(
                record: record, onDelete: () => onDelete(record))),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isAnalyzing ? null : onAdd,
              icon: isAnalyzing
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_a_photo_outlined),
              label: Text(
                  isAnalyzing ? 'AI가 음식을 분석하고 있어요' : '${meal.label} 음식 추가'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: meal.color,
                  side: BorderSide(color: meal.color.withValues(alpha: 0.45)),
                  minimumSize: const Size.fromHeight(43)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MealDetailsSheet extends StatelessWidget {
  const _MealDetailsSheet({required this.meal, required this.records});
  final MealType meal;
  final List<MealRecord> records;

  double _sum(double Function(FoodDetection food) select) =>
      records.fold(0, (sum, record) => sum + select(record.detection));

  @override
  Widget build(BuildContext context) {
    final calories = _sum((food) => food.energyKcal);
    final carbs = _sum((food) => food.carbohydrateG);
    final protein = _sum((food) => food.proteinG);
    final fat = _sum((food) => food.fatG);
    final sodium = _sum((food) => food.sodiumMg);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${meal.label} 식사 상세',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Text(
                  records.isEmpty
                      ? '아직 기록된 음식이 없어요.'
                      : '${records.length}개 음식의 영양정보입니다.',
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _MealNutrient(
                    label: '칼로리',
                    value: '${calories.toStringAsFixed(0)} kcal',
                    color: AppColors.orange),
                _MealNutrient(
                    label: '탄수화물',
                    value: '${carbs.toStringAsFixed(1)} g',
                    color: const Color(0xFFF0B844)),
                _MealNutrient(
                    label: '단백질',
                    value: '${protein.toStringAsFixed(1)} g',
                    color: const Color(0xFF4A9B72)),
                _MealNutrient(
                    label: '지방',
                    value: '${fat.toStringAsFixed(1)} g',
                    color: const Color(0xFF6B8FE0)),
                _MealNutrient(
                    label: '나트륨',
                    value: '${sodium.toStringAsFixed(0)} mg',
                    color: const Color(0xFFE47773)),
              ]),
              if (records.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('먹은 음식',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ...records.map((record) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _MealPhotoThumbnail(imagePath: record.imagePath),
                      title: Text(record.detection.foodName ?? '음식 정보 없음',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          '탄수화물 ${record.detection.carbohydrateG.toStringAsFixed(1)}g · 단백질 ${record.detection.proteinG.toStringAsFixed(1)}g · 나트륨 ${record.detection.sodiumMg.toStringAsFixed(0)}mg'),
                      trailing: Text(
                          '${record.detection.energyKcal.toStringAsFixed(0)} kcal',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    )),
              ],
            ]),
      ),
    );
  }
}

class _MealNutrient extends StatelessWidget {
  const _MealNutrient(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 104,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.w900, color: color)),
        ]),
      );
}

class _FoodRecordTile extends StatelessWidget {
  const _FoodRecordTile({required this.record, required this.onDelete});
  final MealRecord record;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            _MealPhotoThumbnail(imagePath: record.imagePath),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.detection.foodName ?? '음식 정보 없음',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                      'AI 인식 ${(record.detection.confidence * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
            Text('${record.detection.energyKcal.toStringAsFixed(0)} kcal',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.close, size: 19),
                color: AppColors.muted),
          ],
        ),
      );
}

class _MealPhotoThumbnail extends StatelessWidget {
  const _MealPhotoThumbnail({required this.imagePath});
  final String imagePath;

  @override
  Widget build(BuildContext context) {
    final imageFile = File(imagePath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 48,
        height: 48,
        child: imagePath.isNotEmpty && imageFile.existsSync()
            ? Image.file(
                imageFile,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _MealPhotoPlaceholder(),
              )
            : const _MealPhotoPlaceholder(),
      ),
    );
  }
}

class _MealPhotoPlaceholder extends StatelessWidget {
  const _MealPhotoPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFEAF5F2),
        alignment: Alignment.center,
        child: const Icon(Icons.restaurant, size: 22, color: AppColors.teal),
      );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: isError ? const Color(0xFFFFEEEE) : const Color(0xFFE7F5EA),
            borderRadius: BorderRadius.circular(16)),
        child: Text(message,
            style: TextStyle(
                color:
                    isError ? const Color(0xFFC43838) : const Color(0xFF287545),
                fontWeight: FontWeight.w600)),
      );
}
