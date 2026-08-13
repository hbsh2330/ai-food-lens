part of '../main.dart';

enum ReportMetric { calories, protein }

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

// 날짜별 식사 기록을 읽어 7일·30일 통계를 계산하는 리포트 상태입니다.
class _ReportPageState extends State<ReportPage> {
  final Map<DateTime, DailySummary> _days = {};

  bool _loading = true;
  double _calorieGoal = 2200;
  UserProfile? _profile;
  ReportMetric _metric = ReportMetric.calories;

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  // PostgreSQL에서 모든 식사 기록을 받아 날짜별 요약으로 변환합니다.
  Future<void> _loadReport() async {
    try {
      final recordsByDate =
          await FoodDataApi.mealsByDate(DateTime(2020), DateTime.now());
      final profile = await FoodDataApi.profile();
      final targets = await FoodDataApi.targets();
      final summaries = <DateTime, DailySummary>{};
      recordsByDate.forEach((date, records) {
        summaries[date] = DailySummary.fromRecords(records);
      });
      if (!mounted) return;
      setState(() {
        _days
          ..clear()
          ..addAll(summaries);
        _calorieGoal = targets.calories;
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('리포트 데이터를 불러오지 못했어요. $error')));
    }
  }

  DailySummary _summary(DateTime date) =>
      _days[_day(date)] ?? const DailySummary.empty();

  // 종료일을 포함해 연속된 기간만큼의 일별 요약을 만듭니다. 기록 없는 날은 빈 요약입니다.
  List<DailySummary> _period(DateTime end, int length) => List.generate(
        length,
        (index) => _summary(end.subtract(Duration(days: length - 1 - index))),
      );

  // 기록이 있는 날만 분모에 포함해 평균을 계산합니다.
  double _average(
      List<DailySummary> values, double Function(DailySummary) select) {
    final recorded = values.where((value) => value.hasRecords).toList();
    if (recorded.isEmpty) return 0;
    return recorded.fold(0.0, (sum, value) => sum + select(value)) /
        recorded.length;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final today = _day(DateTime.now());
    final todaySummary = _summary(today);
    final weekDates =
        List.generate(7, (index) => today.subtract(Duration(days: 6 - index)));
    final week = weekDates.map(_summary).toList();
    final month = _period(today, 30);
    final previousMonth = _period(today.subtract(const Duration(days: 30)), 30);
    // 최근 30일에 먹은 음식의 횟수를 합산해 Top 3 순위를 만듭니다.
    final foods = <String, int>{};
    for (final summary in month) {
      summary.foodCounts.forEach((name, count) {
        foods[name] = (foods[name] ?? 0) + count;
      });
    }
    final topFoods = foods.entries.toList()
      ..sort((first, second) => second.value.compareTo(first.value));
    final currentWeight = _profile?.weightKg;
    final targetWeight = _profile?.targetWeightKg;
    final isWeightGainGoal = currentWeight != null &&
        targetWeight != null &&
        targetWeight > currentWeight;
    final isWeightLossGoal = currentWeight != null &&
        targetWeight != null &&
        targetWeight < currentWeight;
    // 증량은 목표 칼로리 초과일, 감량은 목표 칼로리 이하일을 달성일로 셉니다.
    // 섭취 기록이 없는 0kcal 날짜는 어느 경우에도 집계하지 않습니다.
    final goalDays = month.where((value) {
      if (value.calories <= 0) return false;
      if (isWeightGainGoal) return value.calories > _calorieGoal;
      if (isWeightLossGoal) return value.calories <= _calorieGoal;
      return false;
    }).length;
    final goalDescription = isWeightGainGoal
        ? '증량 목표 · 목표 칼로리 초과일'
        : isWeightLossGoal
            ? '감량 목표 · 목표 칼로리 이하일'
            : '내 정보에서 현재·목표 몸무게를 설정해 주세요';
    final chartValues = _metric == ReportMetric.calories
        ? week.map((value) => value.calories).toList()
        : week.map((value) => value.protein).toList();
    final recordDays = _days.values.where((value) => value.hasRecords).length;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadReport,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              const Text('영양 리포트',
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('저장된 식사 기록 $recordDays일을 분석했어요.',
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 20),
              _TodayReport(summary: todaySummary),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                      child: Text('최근 7일 섭취 그래프',
                          style: TextStyle(
                              fontSize: 21, fontWeight: FontWeight.w800))),
                  ChoiceChip(
                      label: const Text('칼로리'),
                      selected: _metric == ReportMetric.calories,
                      onSelected: (_) =>
                          setState(() => _metric = ReportMetric.calories)),
                  const SizedBox(width: 4),
                  ChoiceChip(
                      label: const Text('단백질'),
                      selected: _metric == ReportMetric.protein,
                      onSelected: (_) =>
                          setState(() => _metric = ReportMetric.protein)),
                ],
              ),
              const SizedBox(height: 10),
              _WeeklyGraph(
                  dates: weekDates,
                  values: chartValues,
                  metric: _metric,
                  calorieGoal: _calorieGoal),
              const SizedBox(height: 22),
              _WeeklyAverage(
                calories: _average(week, (value) => value.calories),
                carbs: _average(week, (value) => value.carbs),
                protein: _average(week, (value) => value.protein),
                fat: _average(week, (value) => value.fat),
                sodium: _average(week, (value) => value.sodium),
              ),
              const SizedBox(height: 22),
              _MonthlySummary(
                averageCalories: _average(month, (value) => value.calories),
                previousAverageCalories:
                    _average(previousMonth, (value) => value.calories),
                goalDays: goalDays,
                goalDescription: goalDescription,
                topFoods: topFoods.take(3).toList(),
                carbs: _average(month, (value) => value.carbs),
                protein: _average(month, (value) => value.protein),
                fat: _average(month, (value) => value.fat),
                sodium: _average(month, (value) => value.sodium),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 여러 식사 기록을 하루 단위의 칼로리·영양소·식사별 합계로 묶는 중간 모델입니다.
class DailySummary {
  const DailySummary(
      {required this.calories,
      required this.carbs,
      required this.protein,
      required this.fat,
      required this.sodium,
      required this.meals,
      required this.foodCounts});
  const DailySummary.empty()
      : calories = 0,
        carbs = 0,
        protein = 0,
        fat = 0,
        sodium = 0,
        meals = const {},
        foodCounts = const {};

  final double calories;
  final double carbs;
  final double protein;
  final double fat;
  final double sodium;
  final Map<MealType, double> meals;
  final Map<String, int> foodCounts;
  bool get hasRecords => meals.isNotEmpty;

  // 음식별 영양소를 합산하고, 음식명은 빈도 집계용으로 따로 세어 둡니다.
  factory DailySummary.fromRecords(List<MealRecord> records) {
    var calories = 0.0;
    var carbs = 0.0;
    var protein = 0.0;
    var fat = 0.0;
    var sodium = 0.0;
    final meals = <MealType, double>{};
    // 최근 30일에 먹은 음식의 횟수를 합산해 Top 3 순위를 만듭니다.
    final foods = <String, int>{};
    for (final record in records) {
      final food = record.detection;
      calories += food.energyKcal;
      carbs += food.carbohydrateG;
      protein += food.proteinG;
      fat += food.fatG;
      sodium += food.sodiumMg;
      meals[record.meal] = (meals[record.meal] ?? 0) + food.energyKcal;
      if (food.foodName != null && food.foodName!.isNotEmpty) {
        foods[food.foodName!] = (foods[food.foodName!] ?? 0) + 1;
      }
    }
    return DailySummary(
        calories: calories,
        carbs: carbs,
        protein: protein,
        fat: fat,
        sodium: sodium,
        meals: meals,
        foodCounts: foods);
  }
}

class _TodayReport extends StatelessWidget {
  const _TodayReport({required this.summary});
  final DailySummary summary;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(21),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            gradient: const LinearGradient(
                colors: [AppColors.darkTeal, AppColors.teal])),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('오늘 총 섭취량',
                style: TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w700)),
            Text('${summary.calories.toStringAsFixed(0)} kcal',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            Row(
              children: MealType.values
                  .map((meal) => Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(meal.label,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              Text(
                                  '${(summary.meals[meal] ?? 0).toStringAsFixed(0)} kcal',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800)),
                            ]),
                      ))
                  .toList(),
            ),
          ],
        ),
      );
}

// 최근 7일의 칼로리 또는 단백질을 막대 그래프로 표시합니다.
class _WeeklyGraph extends StatelessWidget {
  const _WeeklyGraph(
      {required this.dates,
      required this.values,
      required this.metric,
      required this.calorieGoal});
  final List<DateTime> dates;
  final List<double> values;
  final ReportMetric metric;
  final double calorieGoal;

  @override
  Widget build(BuildContext context) {
    final goal = metric == ReportMetric.calories ? calorieGoal : 65.0;
    final maximum = values.fold(
        goal, (current, value) => value > current ? value : current);
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final color = metric == ReportMetric.calories
        ? AppColors.orange
        : const Color(0xFF4A9B72);
    return Container(
      height: 230,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              metric == ReportMetric.calories
                  ? '하루 목표  kcal'
                  : '하루 목표 단백질 65 g',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(values.length, (index) {
                final value = values[index];
                final height = value == 0
                    ? 4.0
                    : (value / maximum * 125).clamp(8.0, 125.0);
                return Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(value == 0 ? '-' : value.toStringAsFixed(0),
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Container(
                            width: 20,
                            height: height,
                            decoration: BoxDecoration(
                                color: value == 0
                                    ? const Color(0xFFE7ECEA)
                                    : color,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(7)))),
                        const SizedBox(height: 7),
                        Text(weekdays[dates[index].weekday - 1],
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.muted)),
                      ]),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyAverage extends StatelessWidget {
  const _WeeklyAverage(
      {required this.calories,
      required this.carbs,
      required this.protein,
      required this.fat,
      required this.sodium});
  final double calories;
  final double carbs;
  final double protein;
  final double fat;
  final double sodium;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('최근 7일 평균',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Row(children: [
            _MetricValue(
                label: '칼로리',
                value: '${calories.toStringAsFixed(0)} kcal',
                color: AppColors.orange),
            _MetricValue(
                label: '탄수화물',
                value: '${carbs.toStringAsFixed(0)} g',
                color: const Color(0xFFF0B844)),
            _MetricValue(
                label: '단백질',
                value: '${protein.toStringAsFixed(0)} g',
                color: const Color(0xFF4A9B72)),
            _MetricValue(
                label: '지방',
                value: '${fat.toStringAsFixed(0)} g',
                color: const Color(0xFF6B8FE0)),
            _MetricValue(
                label: '나트륨',
                value: '${sodium.toStringAsFixed(0)} mg',
                color: const Color(0xFFE47773)),
          ]),
        ]),
      );
}

class _MetricValue extends StatelessWidget {
  const _MetricValue(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      ]));
}

// 최근 30일 평균, 목표 달성일, 30일 음식 Top 3을 표시합니다.
class _MonthlySummary extends StatelessWidget {
  const _MonthlySummary(
      {required this.averageCalories,
      required this.previousAverageCalories,
      required this.goalDays,
      required this.goalDescription,
      required this.topFoods,
      required this.carbs,
      required this.protein,
      required this.fat,
      required this.sodium});
  final double averageCalories;
  final double previousAverageCalories;
  final int goalDays;
  final String goalDescription;
  final List<MapEntry<String, int>> topFoods;
  final double carbs;
  final double protein;
  final double fat;
  final double sodium;

  @override
  Widget build(BuildContext context) {
    final calorieText = previousAverageCalories == 0
        ? '이전 30일 기록이 더 필요해요.'
        : '이전 30일 대비 ${(averageCalories - previousAverageCalories).toStringAsFixed(0)} kcal';
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('최근 30일 요약',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
          Text('목표 달성 $goalDays일',
              style: const TextStyle(
                  color: AppColors.teal, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 15),
        Text('평균 ${averageCalories.toStringAsFixed(0)} kcal',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        Text(calorieText,
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 3),
        Text(goalDescription,
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const Divider(height: 27),
        Column(children: [
          Row(children: [
            Expanded(
                child: _MonthlyNutrient(
                    label: '탄수화물',
                    value: '${carbs.toStringAsFixed(0)} g',
                    color: const Color(0xFFF0B844))),
            const SizedBox(width: 10),
            Expanded(
                child: _MonthlyNutrient(
                    label: '단백질',
                    value: '${protein.toStringAsFixed(0)} g',
                    color: const Color(0xFF4A9B72))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _MonthlyNutrient(
                    label: '지방',
                    value: '${fat.toStringAsFixed(0)} g',
                    color: const Color(0xFF6B8FE0))),
            const SizedBox(width: 10),
            Expanded(
                child: _MonthlyNutrient(
                    label: '나트륨',
                    value: '${sodium.toStringAsFixed(0)} mg',
                    color: const Color(0xFFE47773))),
          ]),
        ]),
        const Divider(height: 28),
        const Text('가장 자주 먹은 음식',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (topFoods.isEmpty)
          const Text('최근 30일 식사 기록이 쌓이면 음식 순위가 표시됩니다.',
              style: TextStyle(color: AppColors.muted))
        else
          ...List.generate(topFoods.length, (index) {
            final food = topFoods[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('Top${index + 1} : ${food.key} (${food.value}회)',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            );
          }),
      ]),
    );
  }
}

class _MonthlyNutrient extends StatelessWidget {
  const _MonthlyNutrient(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.w900, color: color)),
        ]),
      );
}
