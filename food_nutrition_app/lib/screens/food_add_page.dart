part of '../main.dart';

enum _FoodAddKind { ai, manual }

class _FoodAddResult {
  const _FoodAddResult.ai(this.source)
      : kind = _FoodAddKind.ai,
        detection = null;
  const _FoodAddResult.manual(this.detection)
      : kind = _FoodAddKind.manual,
        source = null;
  final _FoodAddKind kind;
  final ImageSource? source;
  final FoodDetection? detection;
}

// 음식 추가의 진입 화면입니다. AI 사진 분석과 음식명 검색·직접 등록을 분리합니다.
class FoodAddPage extends StatelessWidget {
  const FoodAddPage({super.key, required this.meal});
  final MealType meal;

  Future<void> _chooseAiSource(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('AI 사진으로 등록',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            _AddOption(
                icon: Icons.camera_alt_outlined,
                title: '사진 촬영',
                subtitle: '카메라로 음식을 촬영합니다',
                onTap: () => Navigator.pop(context, ImageSource.camera)),
            const SizedBox(height: 10),
            _AddOption(
                icon: Icons.photo_library_outlined,
                title: '앨범에서 선택',
                subtitle: '저장된 음식 사진을 분석합니다',
                onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ]),
        ),
      ),
    );
    if (context.mounted && source != null) {
      Navigator.pop(context, _FoodAddResult.ai(source));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            backgroundColor: AppColors.background,
            surfaceTintColor: AppColors.background),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(26, 34, 26, 28),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${meal.label} 음식 추가',
                style:
                    const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('어떤 방식으로 식사를 기록할까요?',
                style: TextStyle(color: AppColors.muted, fontSize: 16)),
            const SizedBox(height: 32),
            _AddOption(
                icon: Icons.auto_awesome,
                title: 'AI 사진으로 등록',
                subtitle: '사진을 촬영하거나 앨범에서 선택해 AI가 음식을 분석합니다.',
                color: AppColors.teal,
                onTap: () => _chooseAiSource(context)),
            const SizedBox(height: 14),
            _AddOption(
                icon: Icons.search_rounded,
                title: '음식명으로 등록',
                subtitle: '기본 음식 데이터를 검색하거나 직접 영양정보를 입력합니다.',
                color: const Color(0xFF4E7FBC),
                onTap: () async {
                  final detection = await Navigator.push<FoodDetection>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const FoodNameSearchPage()));
                  if (context.mounted && detection != null) {
                    Navigator.pop(context, _FoodAddResult.manual(detection));
                  }
                }),
            const Spacer(),
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFFE8F2F1),
                    borderRadius: BorderRadius.circular(18)),
                child: const Text(
                    '음식명 등록의 기본 목록은 보유한 영양 데이터 400종을 사용합니다.\n직접 등록한 음식은 이 기기에서 다시 검색할 수 있습니다.',
                    style: TextStyle(color: AppColors.darkTeal))),
          ]),
        ),
      );
}

class _AddOption extends StatelessWidget {
  const _AddOption(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.color = Colors.black});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(children: [
              Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(17)),
                  child: Icon(icon, color: color, size: 28)),
              const SizedBox(width: 17),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 5),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.muted, height: 1.35))
                  ])),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ]),
          ),
        ),
      );
}

// 기본 카탈로그와 이 기기에서 직접 등록한 음식을 검색합니다. 서버 DB 연결 전의 임시 로컬 구현입니다.
class FoodNameSearchPage extends StatefulWidget {
  const FoodNameSearchPage({super.key});
  @override
  State<FoodNameSearchPage> createState() => _FoodNameSearchPageState();
}

class _FoodNameSearchPageState extends State<FoodNameSearchPage> {
  final _controller = TextEditingController();
  List<_FoodCatalogItem> _foods = [];
  bool _loading = false;
  String? _loadError;
  bool _onlyMyFoods = false;
  int _requestSequence = 0;

  @override
  void initState() {
    super.initState();
    // 검색 화면을 열 때는 목록을 자동으로 불러오지 않습니다.
    // 사용자가 검색어를 입력한 뒤에만 서버에서 결과를 조회합니다.

  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 각 입력은 비동기 요청으로 보내되, 기존 목록을 유지합니다.
  // 늦게 도착한 이전 요청은 무시해 한글 조합 중 결과가 뒤섞이지 않게 합니다.
  Future<void> _loadFoods([String? query]) async {
    final keyword = (query ?? _controller.text).trim();
    final requestId = ++_requestSequence;
    if (keyword.isEmpty) {
      if (mounted) {
        setState(() {
          _foods = [];
          _loading = false;
          _loadError = null;
        });
      }
      return;
    }
    // 검색 중에도 기존 결과 목록을 유지해 화면 전체가 로딩 화면으로 바뀌지 않게 합니다.
    setState(() {
      _loadError = null;
    });
    try {
      final raw = await FoodDataApi.foods(keyword, mineOnly: _onlyMyFoods);
      if (!mounted || requestId != _requestSequence) return;
      setState(() {
        _foods = raw.map(_FoodCatalogItem.fromJson).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestSequence) return;
      setState(() {
        _loading = false;
        _loadError = '$error';
      });
    }
  }

  List<_FoodCatalogItem> get _results => _foods;

  Future<void> _choosePortion(_FoodCatalogItem item) async {
    final detection = await Navigator.push<FoodDetection>(context, MaterialPageRoute(builder: (_) => _FoodPortionPage(food: item)));
    if (mounted && detection != null) Navigator.pop(context, detection);
  }
  // 음식 카드 본문은 기본 1인분으로 바로 식사에 추가합니다.
  void _addImmediately(_FoodCatalogItem item) {
    Navigator.pop(context, FoodDetection.manual(
      foodName: item.name,
      servingGrams: item.servingGrams,
      calories: item.calories,
      carbohydrate: item.carbohydrate,
      protein: item.protein,
      fat: item.fat,
      sodium: item.sodium,
      imageUrl: item.imageUrl, foodId: item.id,
      servingUnit: 'servings',
      servingCount: 1,
    ));
  }
  Future<void> _openDirectRegistration() async {
    final item = await Navigator.push<_FoodCatalogItem>(context,
        MaterialPageRoute(builder: (_) => const DirectFoodRegistrationPage()));
    if (item == null || !mounted) return;
    // 직접 등록은 DB에만 저장합니다. 검색 결과는 사용자가 입력해 조회한 음식만 표시합니다.
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name}을(를) 내 등록 음식에 저장했어요.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            backgroundColor: AppColors.background,
            surfaceTintColor: AppColors.background),
        body: SafeArea(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.cloud_off_outlined,
                            size: 42, color: AppColors.muted),
                        const SizedBox(height: 12),
                        const Text('음식 목록을 불러오지 못했어요.'),
                        const SizedBox(height: 8),
                        Text(_loadError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.muted)),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                            onPressed: _loadFoods,
                            icon: const Icon(Icons.refresh),
                            label: const Text('다시 시도'))
                      ]))
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(22, 15, 22, 18),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Expanded(
                                    child: Text('무슨 음식을\n먹었나요?',
                                        style: TextStyle(
                                            fontSize: 30,
                                            fontWeight: FontWeight.w900,
                                            height: 1.15))),
                                FilledButton.icon(
                                    onPressed: _openDirectRegistration,
                                    icon: const Icon(Icons.add),
                                    label: const Text('직접 등록'))
                              ]),
                              const SizedBox(height: 26),
                              TextField(
                                  controller: _controller,
                                  onChanged: _loadFoods,
                                  decoration: InputDecoration(
                                      hintText: '음식명 입력',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon: _controller.text.isEmpty
                                          ? null
                                          : IconButton(
                                              onPressed: () {
                                                _controller.clear();
                                                _loadFoods('');
                                              },
                                              icon: const Icon(Icons.close)),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                          borderSide: BorderSide.none,
                                          borderRadius:
                                              BorderRadius.circular(26)))),
                              const SizedBox(height: 13),
                              Row(children: [
                                ChoiceChip(
                                    label: const Text('전체'),
                                    selected: !_onlyMyFoods,
                                    onSelected: (_) {
                                      setState(() => _onlyMyFoods = false);
                                      _loadFoods();
                                    }),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                    label: const Text('내가 등록한 음식만'),
                                    selected: _onlyMyFoods,
                                    onSelected: (_) {
                                      setState(() => _onlyMyFoods = true);
                                      _loadFoods();
                                    }),
                              ]),
                              const SizedBox(height: 12),
                              Expanded(
                                  child: _results.isEmpty
                                      ? Center(
                                          child: Text(
                                               _controller.text.isEmpty ? '음식명을 검색해 보세요.' : '검색 결과가 없어요.\n직접 등록해 보세요.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  color: AppColors.muted)))
                                      : ListView.separated(
                                          itemCount: _results.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 10),
                                          itemBuilder: (context, index) {
                                            final food = _results[index];
                                            return _FoodSearchTile(
                                                food: food,
                                                 onAdd: () => _choosePortion(food),
                                                 onTileTap: () => _addImmediately(food));
                                          })),
                            ]),
                      )),
      );
}

class _FoodSearchTile extends StatelessWidget {
  const _FoodSearchTile({
    required this.food,
    required this.onAdd,
    required this.onTileTap,
  });

  final _FoodCatalogItem food;
  final VoidCallback onAdd;
  final VoidCallback onTileTap;

  String get _sourceLabel {
    if (food.isMine) return '내 등록 데이터';
    return food.source == 'user' ? '유저 등록 데이터' : '기본 데이터';
  }

  Color get _sourceColor {
    if (food.isMine) return AppColors.teal;
    return food.source == 'user'
        ? const Color(0xFF7B61B5)
        : const Color(0xFF5A7EBA);
  }

  // 숫자가 너무 길어지지 않도록 한국어 단위로 누적 식사 등록 횟수를 표시합니다.
  String get _useCountLabel {
    final count = food.useCount;
    if (count >= 100000000) return '${count ~/ 100000000}억회';
    if (count >= 10000) return '${count ~/ 10000}만회';
    if (count >= 1000) return '${count ~/ 1000}천회';
    return '$count회';
  }

  // 등록 횟수가 커질수록 음식의 인기 정도를 색상으로 구분합니다.
  Color get _useCountColor {
    if (food.useCount >= 100000000) return const Color(0xFFC62828); // 1억회 이상
    if (food.useCount >= 10000) return const Color(0xFFE07A19); // 1만회 이상
    if (food.useCount >= 1000) return const Color(0xFF27834F); // 1천회 이상
    return AppColors.muted; // 천회 미만
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTileTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(17, 14, 12, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: food.imageUrl != null && food.imageUrl!.isNotEmpty
                      ? Image.network(
                          FoodDataApi.imageUrl(food.imageUrl!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const _MealPhotoPlaceholder(),
                        )
                      : const _MealPhotoPlaceholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _badge(_sourceLabel, _sourceColor),
                        if (food.useCount > 0) ...[
                          const SizedBox(width: 6),
                          _badge('$_useCountLabel 등록', _useCountColor),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      food.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '1인분 ${food.servingGrams.toStringAsFixed(0)}g · '
                      '${food.calories.toStringAsFixed(0)} kcal',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onAdd,
                icon: const Icon(
                  Icons.add_circle,
                  size: 33,
                  color: AppColors.teal,
                ),
              ),
            ],
          ),
        ),
      );
}
class DirectFoodRegistrationPage extends StatefulWidget {
  const DirectFoodRegistrationPage({super.key});
  @override
  State<DirectFoodRegistrationPage> createState() =>
      _DirectFoodRegistrationPageState();
}

class _DirectFoodRegistrationPageState
    extends State<DirectFoodRegistrationPage> {
  final _name = TextEditingController();
  final _serving = TextEditingController();
  final _calories = TextEditingController();
  final _carbohydrate = TextEditingController();
  final _protein = TextEditingController();
  final _fat = TextEditingController();
  final _sodium = TextEditingController();
  final _picker = ImagePicker();
  XFile? _image;
  @override
  void dispose() {
    for (final controller in [
      _name,
      _serving,
      _calories,
      _carbohydrate,
      _protein,
      _fat,
      _sodium
    ]) {
      controller.dispose();
    }
    super.dispose();
  }


  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
        source: source, imageQuality: 82, maxWidth: 1600);
    if (picked != null && mounted) setState(() => _image = picked);
  }

  double? _value(TextEditingController controller) =>
      double.tryParse(controller.text.trim());
  Future<void> _save() async {
    final serving = _value(_serving);
    final calories = _value(_calories);
    final carbohydrate = _value(_carbohydrate);
    final protein = _value(_protein);
    final fat = _value(_fat);
    final sodium = _value(_sodium);
    if (_name.text.trim().isEmpty ||
        [serving, calories, carbohydrate, protein, fat, sodium]
            .any((value) => value == null || value < 0) ||
        serving == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('음식명과 1인분·칼로리·탄수화물·단백질·지방·나트륨을 입력해 주세요.')));
      return;
    }
    final imageUrl = _image == null
        ? null
        : await FoodDataApi.uploadFoodImage(File(_image!.path));

    final item = _FoodCatalogItem(
        id: 'mine_${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim(),
        servingGrams: serving!,
        calories: calories!,
        carbohydrate: carbohydrate!,
        protein: protein!,
        fat: fat!,
        sodium: sodium!,
        imageUrl: imageUrl,
        isMine: true);
    final saved = await FoodDataApi.createFood({
      'name': item.name,
      'serving_grams': item.servingGrams,
      'calories_kcal': item.calories,
      'carbohydrate_g': item.carbohydrate,
      'protein_g': item.protein,
      'fat_g': item.fat,
      'sodium_mg': item.sodium,
      'image_url': imageUrl,
    });
    final savedItem = _FoodCatalogItem.fromJson(saved);
    if (mounted) Navigator.pop(context, savedItem);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('음식 직접 등록'), centerTitle: true),
      body: ListView(padding: const EdgeInsets.all(22), children: [
        const Text('직접 영양정보 입력',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('입력한 음식은 이후 음식명 검색에서 가장 먼저 찾을 수 있습니다.',
            style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 24),
        const Text('음식 사진 (선택)',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('사진 촬영'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('앨범 선택'))),
        ]),
        if (_image != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(File(_image!.path),
                height: 160, width: double.infinity, fit: BoxFit.cover),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _image = null),
              icon: const Icon(Icons.close),
              label: const Text('사진 삭제'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _InputField(controller: _name, label: '음식명', unit: ''),
        const SizedBox(height: 12),
        _InputField(controller: _serving, label: '1인분 중량', unit: 'g'),
        const SizedBox(height: 12),
        _InputField(controller: _calories, label: '칼로리', unit: 'kcal'),
        const SizedBox(height: 12),
        _InputField(controller: _carbohydrate, label: '탄수화물', unit: 'g'),
        const SizedBox(height: 12),
        _InputField(controller: _protein, label: '단백질', unit: 'g'),
        const SizedBox(height: 12),
        _InputField(controller: _fat, label: '지방', unit: 'g'),
        const SizedBox(height: 12),
        _InputField(controller: _sodium, label: '나트륨', unit: 'mg'),
        const SizedBox(height: 28),
        FilledButton(
            onPressed: _save,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            child: const Text('음식 등록하기'))
      ]));
}

class _InputField extends StatelessWidget {
  const _InputField(
      {required this.controller, required this.label, required this.unit});
  final TextEditingController controller;
  final String label;
  final String unit;
  @override
  Widget build(BuildContext context) => TextField(
      controller: controller,
      keyboardType: label == '음식명'
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none)));
}

class _FoodCatalogItem {
  const _FoodCatalogItem(
      {required this.id,
      required this.name,
      required this.servingGrams,
      required this.calories,
      required this.carbohydrate,
      required this.protein,
      required this.fat,
      required this.sodium,
       this.isMine = false,
       this.source = 'catalog',
       this.imageUrl,
       this.useCount = 0});
  final String id;
  final String name;
  final double servingGrams;
  final double calories;
  final double carbohydrate;
  final double protein;
  final double fat;
  final double sodium;
  final bool isMine;
  final String source;
  final String? imageUrl;
  final int useCount;
  // 기본 asset JSON과 PostgreSQL API는 영양소 키 이름이 다르므로 둘 다 지원합니다.
  factory _FoodCatalogItem.fromJson(Map<String, dynamic> json) =>
      _FoodCatalogItem(
        id: json['id'].toString(),
        name: json['name'] as String,
        servingGrams: (json['serving_grams'] as num).toDouble(),
        calories:
            ((json['calories_kcal'] ?? json['calories']) as num).toDouble(),
        carbohydrate: ((json['carbohydrate_g'] ?? json['carbohydrate'] ?? 0) as num).toDouble(),
        protein: ((json['protein_g'] ?? json['protein']) as num).toDouble(),
        fat: ((json['fat_g'] ?? json['fat']) as num).toDouble(),
        sodium: ((json['sodium_mg'] ?? json['sodium']) as num).toDouble(),
        isMine: json['origin'] == 'mine' || json['is_mine'] == true || (json['is_mine'] == null && json['source'] == 'user'),
        source: (json['source'] ?? (json['origin'] == 'mine' ? 'user' : 'catalog')) as String,
        imageUrl: json['image_url'] as String?,
        useCount: (json['use_count'] as num?)?.toInt() ?? 0,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'serving_grams': servingGrams,
        'calories': calories,
        'carbohydrate': carbohydrate,
        'protein': protein,
        'fat': fat,
        'sodium': sodium,
        'origin': isMine ? 'mine' : 'catalog',
        'source': source,
        'image_url': imageUrl,
      };
  FoodDetection toDetection() => FoodDetection.manual(
      foodName: name,
      servingGrams: servingGrams,
      calories: calories,
      carbohydrate: carbohydrate,
      protein: protein,
      fat: fat,
      sodium: sodium,
      imageUrl: imageUrl, foodId: id);
}


// 선택한 음식의 1인분 수(0.5~6) 또는 그램을 지정하고 영양 성분을 비율에 맞게 계산합니다.
class _FoodPortionPage extends StatefulWidget {
  const _FoodPortionPage({required this.food, this.submitLabel = '식사에 추가'});
  final _FoodCatalogItem food;
  final String submitLabel;
  @override
  State<_FoodPortionPage> createState() => _FoodPortionPageState();
}
class _FoodPortionPageState extends State<_FoodPortionPage> {
  double _servings = 1;
  bool _gramsMode = false;
  late final _grams = TextEditingController(text: widget.food.servingGrams.toStringAsFixed(0));
  double get _gramsValue => double.tryParse(_grams.text) ?? widget.food.servingGrams * _servings;
  double get _factor => _gramsMode ? _gramsValue / widget.food.servingGrams : _servings;
  @override void dispose() { _grams.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final food=widget.food; final factor=_factor;
    return Scaffold(
      backgroundColor: const Color(0xFFE8F1F5),
      appBar: AppBar(backgroundColor: const Color(0xFFE8F1F5), foregroundColor: const Color(0xFF17365C)),
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(food.name, style: const TextStyle(color: Color(0xFF17365C), fontSize: 32, fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          _MacroBubbles(
            carbs: food.carbohydrate * factor,
            protein: food.protein * factor,
            fat: food.fat * factor,
            total: (food.carbohydrate + food.protein + food.fat) * factor,
            showGramValues: true,
          ),          const SizedBox(height: 22),
          Text('${(food.calories * factor).toStringAsFixed(0)} kcal', style: const TextStyle(color: Color(0xFF17365C), fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('나트륨 ${(food.sodium * factor).toStringAsFixed(0)} mg', style: const TextStyle(color: Color(0xFF355B75), fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: ChoiceChip(label: const Text('인분으로 지정'), selected: !_gramsMode, onSelected: (_) => setState(() => _gramsMode=false))),
            const SizedBox(width: 8), Expanded(child: ChoiceChip(label: const Text('그램으로 지정'), selected: _gramsMode, onSelected: (_) => setState(() => _gramsMode=true))),
          ]), const SizedBox(height: 14),
          SizedBox(
            height: 76,
            child: !_gramsMode
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF203C62),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(children: [
                      IconButton(onPressed: _servings <= .5 ? null : () => setState(() => _servings -= .5), icon: const Icon(Icons.remove, color: Colors.white, size: 32)),
                      Expanded(child: Text('${_servings.toStringAsFixed(_servings % 1 == 0 ? 0 : 1)}인분 (${(food.servingGrams * _servings).toStringAsFixed(0)}g)', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
                      IconButton(onPressed: _servings >= 6 ? null : () => setState(() => _servings += .5), icon: const Icon(Icons.add, color: Colors.white, size: 32)),
                    ]),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF203C62),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: _grams,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(
                        hintText: '섭취한 그램',
                        hintStyle: TextStyle(color: Colors.white70),
                        suffixText: 'g',
                        suffixStyle: TextStyle(color: Colors.white),
                        contentPadding: EdgeInsets.symmetric(horizontal: 20),
                        border: InputBorder.none,
                      ),
                    ),
                  ),          ),          const Spacer(), SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context, FoodDetection.manual(foodName: food.name, servingGrams: _gramsMode ? _gramsValue : food.servingGrams * _servings, calories: food.calories * factor, carbohydrate: food.carbohydrate * factor, protein: food.protein * factor, fat: food.fat * factor, sodium: food.sodium * factor, imageUrl: food.imageUrl, foodId: food.id, servingUnit: _gramsMode ? 'grams' : 'servings', servingCount: _gramsMode ? null : _servings)), style: FilledButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size.fromHeight(56)), child: Text(widget.submitLabel))),
        ]),
      )),
    );
  }
}
