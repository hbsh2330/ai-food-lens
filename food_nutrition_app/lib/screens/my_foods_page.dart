part of '../main.dart';

/// 내가 직접 등록한 음식의 영양 정보와 사진을 관리하는 화면입니다.
/// 기본 데이터와 다른 사용자가 등록한 음식은 여기에서 수정할 수 없습니다.
class MyFoodsPage extends StatefulWidget {
  const MyFoodsPage({super.key});

  @override
  State<MyFoodsPage> createState() => _MyFoodsPageState();
}

class _MyFoodsPageState extends State<MyFoodsPage> {
  List<Map<String, dynamic>> _foods = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFoods();
  }

  Future<void> _loadFoods() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final foods = await FoodDataApi.myFoods();
      if (!mounted) return;
      setState(() => _foods = foods);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '등록한 음식 목록을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editFood(Map<String, dynamic> food) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MyFoodEditPage(food: food)),
    );
    if (saved == true && mounted) _loadFoods();
  }

  Future<void> _deleteFood(Map<String, dynamic> food) async {
    final name = food['name']?.toString() ?? '이 음식';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('등록 음식 삭제'),
        content: Text('$name을(를) 삭제할까요?\n과거 식사 기록은 유지됩니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC73D3D)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FoodDataApi.deleteMyFood(food['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('등록한 음식을 삭제했습니다.')));
      _loadFoods();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('음식을 삭제하지 못했습니다. 다시 시도해주세요.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('내 등록 음식 관리')),
        body: RefreshIndicator(
          onRefresh: _loadFoods,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorView(message: _error!, retry: _loadFoods)
                  : _foods.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 180),
                            Icon(Icons.restaurant_menu_rounded,
                                size: 52, color: Color(0xFF8DA5A2)),
                            SizedBox(height: 14),
                            Center(
                              child: Text('직접 등록한 음식이 없습니다.',
                                  style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            SizedBox(height: 8),
                            Center(
                              child: Text('음식 추가에서 직접 등록한 음식이 이곳에 표시됩니다.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFF71817F))),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
                          itemCount: _foods.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final food = _foods[index];
                            return _MyFoodCard(
                              food: food,
                              onEdit: () => _editFood(food),
                              onDelete: () => _deleteFood(food),
                            );
                          },
                        ),
        ),
      );
}

class _MyFoodCard extends StatelessWidget {
  const _MyFoodCard(
      {required this.food, required this.onEdit, required this.onDelete});

  final Map<String, dynamic> food;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _number(Object? value, {int digits = 0}) =>
      ((value as num?)?.toDouble() ?? 0).toStringAsFixed(digits);

  @override
  Widget build(BuildContext context) {
    final path = food['image_url'] as String?;
    final grams = _number(food['serving_grams']);
    final kcal = _number(food['calories_kcal']);
    final count = (food['use_count'] as num?)?.toInt() ?? 0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE0EBE9)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              _FoodThumbnail(path: path),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SourceChip(),
                    const SizedBox(height: 5),
                    Text(food['name']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('1인분 $grams' 'g · $kcal kcal',
                        style: const TextStyle(color: Color(0xFF758481))),
                    const SizedBox(height: 4),
                    Text('$count회 식사에 등록됨',
                        style: const TextStyle(
                            color: Color(0xFF2B7770), fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '음식 메뉴',
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('수정')),
                  PopupMenuItem(value: 'delete', child: Text('삭제')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFDDF2EF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('내가 등록한 음식',
            style: TextStyle(
                color: Color(0xFF176C65), fontSize: 10, fontWeight: FontWeight.w800)),
      );
}

class _FoodThumbnail extends StatelessWidget {
  const _FoodThumbnail({required this.path});
  final String? path;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 58,
          height: 58,
          child: path?.isEmpty ?? true
              ? Container(
                  color: const Color(0xFFF0F5F4),
                  child: const Icon(Icons.restaurant_rounded,
                      color: Color(0xFF5F8580)),
                )
              : Image.network(
                  FoodDataApi.imageUrl(path!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFF0F5F4),
                    child: const Icon(Icons.restaurant_rounded,
                        color: Color(0xFF5F8580)),
                  ),
                ),
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          const SizedBox(height: 180),
          const Icon(Icons.cloud_off_rounded, size: 50, color: Color(0xFF8DA5A2)),
          const SizedBox(height: 12),
          Center(child: Text(message)),
          const SizedBox(height: 12),
          Center(child: OutlinedButton(onPressed: retry, child: const Text('다시 시도'))),
        ],
      );
}

/// 직접 등록한 음식 한 개를 수정하는 폼입니다.
class MyFoodEditPage extends StatefulWidget {
  const MyFoodEditPage({super.key, required this.food});
  final Map<String, dynamic> food;

  @override
  State<MyFoodEditPage> createState() => _MyFoodEditPageState();
}

class _MyFoodEditPageState extends State<MyFoodEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _name;
  late final TextEditingController _grams;
  late final TextEditingController _calories;
  late final TextEditingController _carbs;
  late final TextEditingController _protein;
  late final TextEditingController _fat;
  late final TextEditingController _sodium;
  XFile? _pickedImage;
  late String? _imageUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.food['name']?.toString() ?? '');
    _grams = _controller(widget.food['serving_grams']);
    _calories = _controller(widget.food['calories_kcal']);
    _carbs = _controller(widget.food['carbohydrate_g']);
    _protein = _controller(widget.food['protein_g']);
    _fat = _controller(widget.food['fat_g']);
    _sodium = _controller(widget.food['sodium_mg']);
    _imageUrl = widget.food['image_url'] as String?;
  }

  TextEditingController _controller(Object? value) => TextEditingController(
      text: ((value as num?)?.toDouble() ?? 0).toStringAsFixed(0));

  @override
  void dispose() {
    for (final controller in [_name, _grams, _calories, _carbs, _protein, _fat, _sodium]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await _picker.pickImage(source: source, imageQuality: 85);
    if (image != null && mounted) setState(() => _pickedImage = image);
  }

  double _value(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? -1;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;
    setState(() => _saving = true);
    try {
      var imageUrl = _imageUrl;
      if (_pickedImage != null) {
        imageUrl = await FoodDataApi.uploadFoodImage(File(_pickedImage!.path));
      }
      await FoodDataApi.updateMyFood(widget.food['id'].toString(), {
        'name': _name.text.trim(),
        'serving_grams': _value(_grams),
        'calories_kcal': _value(_calories),
        'carbohydrate_g': _value(_carbs),
        'protein_g': _value(_protein),
        'fat_g': _value(_fat),
        'sodium_mg': _value(_sodium),
        'image_url': imageUrl,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('음식 정보를 저장하지 못했습니다. 다시 시도해주세요.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController controller, String unit) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            suffixText: unit,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: (value) {
            final number = double.tryParse(value?.trim() ?? '');
            if (number == null || number < 0) return '0 이상의 숫자를 입력해주세요.';
            return null;
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final preview = _pickedImage != null
        ? Image.file(File(_pickedImage!.path), fit: BoxFit.cover)
        : _imageUrl == null || _imageUrl!.isEmpty
            ? const Icon(Icons.restaurant_rounded, size: 46, color: Color(0xFF5F8580))
            : Image.network(FoodDataApi.imageUrl(_imageUrl!), fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.restaurant_rounded,
                    size: 46, color: Color(0xFF5F8580)));
    return Scaffold(
      appBar: AppBar(title: const Text('등록 음식 수정')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 120,
                    height: 120,
                    color: const Color(0xFFF0F5F4),
                    child: preview,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_outlined),
                      label: const Text('앨범')), 
                  TextButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('카메라')),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: '음식명',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '음식명을 입력해주세요.'
                    : null,
              ),
              const SizedBox(height: 16),
              const Text('1인분 기준 영양정보',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 12),
              _field('1인분 중량', _grams, 'g'),
              _field('칼로리', _calories, 'kcal'),
              _field('탄수화물', _carbs, 'g'),
              _field('단백질', _protein, 'g'),
              _field('지방', _fat, 'g'),
              _field('나트륨', _sodium, 'mg'),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0A756E),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('변경 저장'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}