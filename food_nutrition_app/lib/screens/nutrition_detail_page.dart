part of '../main.dart';

enum NutritionDetailRange { daily, weekly, monthly }

enum NutritionDetailMetric { carbs, protein, fat }

// 홈의 상세 버튼에서 열리는 분석 화면입니다. 선택 날짜를 기준으로 일간·주간·해당 월 전체 기록을 비교합니다.
class NutritionDetailPage extends StatefulWidget {
  const NutritionDetailPage({
    super.key,
    required this.selectedDate,
    required this.recordsByDate,
    required this.targets,
  });

  final DateTime selectedDate;
  final Map<DateTime, List<MealRecord>> recordsByDate;
  final NutritionTargets targets;

  @override
  State<NutritionDetailPage> createState() => _NutritionDetailPageState();
}

class _NutritionDetailPageState extends State<NutritionDetailPage> {
  NutritionDetailRange _range = NutritionDetailRange.daily;

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  DateTime get _weekStart =>
      _day(widget.selectedDate.subtract(const Duration(days: 7)));
  DateTime get _monthStart =>
      DateTime(widget.selectedDate.year, widget.selectedDate.month, 1);
  DateTime get _monthEnd =>
      DateTime(widget.selectedDate.year, widget.selectedDate.month + 1, 0);

  // 일간은 선택 날짜, 주간은 7일 전~선택 날짜(양끝 포함), 월간은 해당 월 전체 기록을 합산합니다.
  List<MealRecord> get _records {
    final start = switch (_range) {
      NutritionDetailRange.daily => _day(widget.selectedDate),
      NutritionDetailRange.weekly => _weekStart,
      NutritionDetailRange.monthly => _monthStart,
    };
    final end = switch (_range) {
      NutritionDetailRange.daily => _day(widget.selectedDate),
      NutritionDetailRange.weekly => _day(widget.selectedDate),
      NutritionDetailRange.monthly => _monthEnd,
    };
    return widget.recordsByDate.entries
        .where((entry) {
          final date = _day(entry.key);
          return !date.isBefore(start) && !date.isAfter(end);
        })
        .expand((entry) => entry.value)
        .toList();
  }

  String _formatDate(DateTime date) => '${date.month}월 ${date.day}일';

  String get _periodLabel => switch (_range) {
        NutritionDetailRange.daily => _formatDate(widget.selectedDate),
        NutritionDetailRange.weekly =>
          '${_formatDate(_weekStart)} ~ ${_formatDate(widget.selectedDate)}',
        NutritionDetailRange.monthly =>
          '${widget.selectedDate.year}년 ${widget.selectedDate.month}월 전체',
      };

  String get _rangeLabel => switch (_range) {
        NutritionDetailRange.daily => '일간',
        NutritionDetailRange.weekly => '주간',
        NutritionDetailRange.monthly => '월간',
      };

  double _sum(double Function(FoodDetection food) select) =>
      _records.fold(0, (sum, record) => sum + select(record.detection));

  @override
  Widget build(BuildContext context) {
    final calories = _sum((food) => food.energyKcal);
    final carbs = _sum((food) => food.carbohydrateG);
    final protein = _sum((food) => food.proteinG);
    final fat = _sum((food) => food.fatG);
    final totalMacro = carbs + protein + fat;

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('영양소 상세', style: TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: true,
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          _RangeSelector(
            selected: _range,
            onChanged: (range) => setState(() => _range = range),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
            decoration: BoxDecoration(
              color: const Color(0xFF80ADD1),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                Text(_periodLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                Text('${calories.toStringAsFixed(0)} kcal',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 29,
                        fontWeight: FontWeight.w900)),
                Text('$_rangeLabel 총 섭취 열량',
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                _MacroBubbles(
                    carbs: carbs,
                    protein: protein,
                    fat: fat,
                    total: totalMacro),
                const SizedBox(height: 22),
                Row(children: [
                  _MacroAmount(
                      label: '탄수화물', value: carbs, color: Colors.white),
                  _WhiteDivider(),
                  _MacroAmount(
                      label: '단백질',
                      value: protein,
                      color: const Color(0xFFFFFF91)),
                  _WhiteDivider(),
                  _MacroAmount(
                      label: '지방', value: fat, color: const Color(0xFF28476F)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('먹은 음식 분석',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('영양소별로 가장 많이 섭취한 음식 3개를 보여줍니다.',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          _FoodRankingSection(
            title: '탄수화물',
            total: carbs,
            goal: widget.targets.carbs * _targetMultiplier,
            metric: NutritionDetailMetric.carbs,
            records: _records,
            color: const Color(0xFFF0B844),
          ),
          const SizedBox(height: 14),
          _FoodRankingSection(
            title: '단백질',
            total: protein,
            goal: widget.targets.protein * _targetMultiplier,
            metric: NutritionDetailMetric.protein,
            records: _records,
            color: const Color(0xFF4A9B72),
          ),
          const SizedBox(height: 14),
          _FoodRankingSection(
            title: '지방',
            total: fat,
            goal: widget.targets.fat * _targetMultiplier,
            metric: NutritionDetailMetric.fat,
            records: _records,
            color: const Color(0xFF527AD5),
          ),
        ],
      ),
    );
  }

  // 기간별 섭취 목표: 주간은 양끝을 포함한 8일, 월간은 해당 월의 실제 일수를 사용합니다.
  double get _targetMultiplier => switch (_range) {
        NutritionDetailRange.daily => 1,
        NutritionDetailRange.weekly => 8,
        NutritionDetailRange.monthly => _monthEnd.day.toDouble(),
      };
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.selected, required this.onChanged});
  final NutritionDetailRange selected;
  final ValueChanged<NutritionDetailRange> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: NutritionDetailRange.values.map((range) {
          final active = range == selected;
          final label = switch (range) {
            NutritionDetailRange.daily => '일간',
            NutritionDetailRange.weekly => '주간',
            NutritionDetailRange.monthly => '월간',
          };
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                label: SizedBox(
                    width: double.infinity,
                    child: Text(label, textAlign: TextAlign.center)),
                selected: active,
                onSelected: (_) => onChanged(range),
                selectedColor: const Color(0xFF80ADD1),
                backgroundColor: const Color(0xFFECEFF2),
                labelStyle: TextStyle(
                    color: active ? Colors.white : AppColors.muted,
                    fontWeight: FontWeight.w900,
                    fontSize: 16),
                side: BorderSide.none,
                shape: const StadiumBorder(),
              ),
            ),
          );
        }).toList(),
      );
}

class _MacroBubbles extends StatelessWidget {
  const _MacroBubbles({
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.total,
    this.showGramValues = false,
  });
  final double carbs;
  final double protein;
  final double fat;
  final double total;
  // 중량 선택 화면에서는 퍼센트 대신 실제 섭취 g를 표시합니다.
  final bool showGramValues;

  // 비율이 큰 영양소일수록 원형을 크게 표시합니다.
  double _bubbleSize(double ratio) => 70 + ratio.clamp(0.0, 1.0) * 70;

  @override
  Widget build(BuildContext context) {
    final safeTotal = total <= 0 ? 1.0 : total;
    final carbRatio = carbs / safeTotal;
    final proteinRatio = protein / safeTotal;
    final fatRatio = fat / safeTotal;
    return SizedBox(
      height: 178,
      child: Stack(alignment: Alignment.center, children: [
        Positioned(
          left: 28,
          top: 8,
          child: _Bubble(
            label: '탄수화물',
            grams: carbs,
            value: carbRatio,
            color: Colors.white,
            textColor: const Color(0xFF28476F),
            size: _bubbleSize(carbRatio),
            showGramValues: showGramValues,
          ),
        ),
        Positioned(
          right: 28,
          top: 8,
          child: _Bubble(
            label: '지방',
            grams: fat,
            value: fatRatio,
            color: const Color(0xFF28476F),
            textColor: Colors.white,
            size: _bubbleSize(fatRatio),
            showGramValues: showGramValues,
          ),
        ),
        Positioned(
          bottom: 0,
          child: _Bubble(
            label: '단백질',
            grams: protein,
            value: proteinRatio,
            color: const Color(0xFFFFFF91),
            textColor: const Color(0xFF28476F),
            size: _bubbleSize(proteinRatio),
            showGramValues: showGramValues,
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.label,
    required this.grams,
    required this.value,
    required this.color,
    required this.textColor,
    required this.size,
    required this.showGramValues,
  });
  final String label;
  final double grams;
  final double value;
  final Color color;
  final Color textColor;
  final double size;
  final bool showGramValues;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: showGramValues
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label,
                    style: TextStyle(
                        color: textColor,
                        fontSize: size * 0.13,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${grams.toStringAsFixed(1)}g',
                        style: TextStyle(
                            color: textColor,
                            fontSize: size * 0.18,
                            fontWeight: FontWeight.w900)),
                  ),
                )
                  ),
                )
              ])
            : Text('${(value * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    color: textColor,
                    fontSize: size * 0.27,
                    fontWeight: FontWeight.w900)),
      );
}
class _WhiteDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 48, color: Colors.white38);
}

class _MacroAmount extends StatelessWidget {
  const _MacroAmount(
      {required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 5),
          Text('${value.toStringAsFixed(1)}g',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900)),
        ]),
      );
}

class _FoodRankingSection extends StatelessWidget {
  const _FoodRankingSection(
      {required this.title,
      required this.total,
      required this.goal,
      required this.metric,
      required this.records,
      required this.color});
  final String title;
  final double total;
  final double goal;
  final NutritionDetailMetric metric;
  final List<MealRecord> records;
  final Color color;

  double _amount(FoodDetection food) => switch (metric) {
        NutritionDetailMetric.carbs => food.carbohydrateG,
        NutritionDetailMetric.protein => food.proteinG,
        NutritionDetailMetric.fat => food.fatG,
      };

  @override
  Widget build(BuildContext context) {
    final foods = <String, _FoodRank>{};
    for (final record in records) {
      final name = record.detection.foodName;
      if (name == null || name.isEmpty) continue;
      final previous = foods[name] ?? const _FoodRank(count: 0, amount: 0);
      foods[name] = _FoodRank(
          count: previous.count + 1,
          amount: previous.amount + _amount(record.detection));
    }
    final ranking = foods.entries.toList()
      ..sort((a, b) => b.value.amount.compareTo(a.value.amount));
    final progress = goal == 0 ? 0.0 : (total / goal).clamp(0.0, 1.0);
    final status = total == 0
        ? '기록 없음'
        : total >= goal
            ? '충분해요'
            : '부족해요';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900))),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(status,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                color: color,
                backgroundColor: const Color(0xFFE9EEF0))),
        const SizedBox(height: 8),
        Row(children: [
          Text('${total.toStringAsFixed(1)}g 먹었어요',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('목표 ${goal.toStringAsFixed(0)}g',
              style: const TextStyle(color: AppColors.muted)),
        ]),
        const Divider(height: 28),
        if (ranking.isEmpty)
          const Text('이 기간에 저장된 음식이 없어요.',
              style: TextStyle(color: AppColors.muted))
        else
          ...List.generate(ranking.take(3).length, (index) {
            final entry = ranking[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFF0F2F4),
                    child: Text('${index + 1}',
                        style: const TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w900))),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(entry.key,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800))),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${entry.value.count}회',
                      style: const TextStyle(
                          color: AppColors.muted, fontWeight: FontWeight.w700)),
                  Text('총 ${entry.value.amount.toStringAsFixed(1)}g',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ]),
              ]),
            );
          }),
      ]),
    );
  }
}

class _FoodRank {
  const _FoodRank({required this.count, required this.amount});
  final int count;
  final double amount;
}
