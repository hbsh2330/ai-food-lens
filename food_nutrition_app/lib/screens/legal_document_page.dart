part of '../main.dart';

/// 앱 안에서 제공하는 개인정보 처리방침과 이용약관 안내 화면입니다.
class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage.privacy({super.key}) : _document = _LegalDocument.privacy;
  const LegalDocumentPage.terms({super.key}) : _document = _LegalDocument.terms;

  final _LegalDocument _document;

  @override
  Widget build(BuildContext context) {
    final isPrivacy = _document == _LegalDocument.privacy;
    final title = isPrivacy ? '개인정보 처리방침' : '이용약관';
    final sections = isPrivacy ? _privacySections : _termsSections;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          children: [
            Text(title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('시행일: 2026년 8월 21일',
                style: TextStyle(color: Color(0xFF71817F))),
            const SizedBox(height: 20),
            ...sections.map((section) => _LegalSectionView(section: section)),
            const SizedBox(height: 12),
            const Text(
              '이 문서는 현재 Food Lens 앱 기능을 기준으로 작성된 안내문입니다. '
              '앱을 실제 공개·배포하기 전에는 담당자의 연락처와 실제 운영 정책을 확정하고 법률 검토를 거쳐야 합니다.',
              style: TextStyle(color: Color(0xFF71817F), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

enum _LegalDocument { privacy, terms }

class _LegalSectionData {
  const _LegalSectionData(this.title, this.body);
  final String title;
  final String body;
}

class _LegalSectionView extends StatelessWidget {
  const _LegalSectionView({required this.section});
  final _LegalSectionData section;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(section.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(section.body,
                style: const TextStyle(height: 1.6, color: Color(0xFF344543))),
          ],
        ),
      );
}

const _privacySections = [
  _LegalSectionData(
    '1. 수집하는 정보',
    'Food Lens는 로그인 제공자(구글 또는 카카오)의 고유 식별값과 표시 이름, '
        '사용자가 입력한 신체 정보(키·몸무게·목표 몸무게·나이·성별·활동량·목표), '
        '식사 기록, 영양 목표, 체중 기록, 직접 등록한 음식 정보 및 사진을 수집합니다.',
  ),
  _LegalSectionData(
    '2. 이용 목적',
    '수집한 정보는 계정 식별, 개인별 영양 목표 계산, 식사·체중 기록 저장, '
        '영양 리포트 제공 및 음식 사진 분석 결과 표시를 위해서만 사용합니다.',
  ),
  _LegalSectionData(
    '3. 보관 및 삭제',
    '정보는 계정 사용 기간 동안 PostgreSQL 데이터베이스에 보관됩니다. '
        '회원 탈퇴 시 계정, 식사 기록, 영양 목표, 체중 기록, 직접 등록 음식과 연결된 사진을 삭제합니다. '
        '다만 법령상 보관 의무가 있는 경우에는 해당 기간 동안 보관될 수 있습니다.',
  ),
  _LegalSectionData(
    '4. 제3자 제공과 처리 위탁',
    'Food Lens는 로그인 처리를 위해 구글 또는 카카오의 인증 서비스를 사용합니다. '
        '음식 사진 분석을 위해 Food Lens 서버에서 AI 모델을 실행합니다. '
        '사용자의 개인정보를 광고 목적이나 판매 목적으로 제3자에게 제공하지 않습니다.',
  ),
  _LegalSectionData(
    '5. 이용자의 권리',
    '사용자는 내 정보 및 직접 등록한 음식 관리 화면에서 자신의 정보를 수정할 수 있으며, '
        '회원 탈퇴 및 내 데이터 삭제 기능으로 계정과 저장 데이터를 삭제할 수 있습니다.',
  ),
];

const _termsSections = [
  _LegalSectionData(
    '1. 서비스 목적',
    'Food Lens는 음식 사진 AI 분석과 사용자가 입력한 정보를 바탕으로 영양 정보를 기록·조회하는 서비스입니다.',
  ),
  _LegalSectionData(
    '2. 계정과 이용',
    '서비스는 구글 또는 카카오 계정 로그인으로 이용할 수 있습니다. '
        '사용자는 본인의 정확한 정보를 입력하고 계정 사용에 관한 책임을 집니다.',
  ),
  _LegalSectionData(
    '3. AI 분석 결과의 한계',
    'AI 음식 인식과 영양 정보는 참고용이며, 모든 음식·중량·조리법을 정확히 판별하지 못할 수 있습니다. '
        '질병 치료, 진단 또는 전문 의료·영양 상담을 대체하지 않습니다.',
  ),
  _LegalSectionData(
    '4. 사용자 등록 정보',
    '사용자가 직접 등록한 음식 정보는 다른 사용자의 검색 결과에 표시될 수 있습니다. '
        '타인의 권리를 침해하거나 부정확·유해한 정보를 등록해서는 안 됩니다.',
  ),
  _LegalSectionData(
    '5. 서비스 변경 및 종료',
    '서비스 기능은 개선, 보안 또는 운영상 필요에 따라 변경·중단될 수 있습니다. '
        '중요한 변경이 있는 경우 앱 또는 배포 채널을 통해 안내합니다.',
  ),
];

