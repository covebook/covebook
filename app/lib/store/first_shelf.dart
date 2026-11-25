// 처음 켤 때 책장 준비: 보기 책 책등 비율을 기억해 둔다. 빈 서재는 빈 선반 그대로 연다
// (예시 책장은 2026-11-25 사용자 '예시 책들 없애버려'로 없앴다. 예전에 깔린 예시 자리는 서재를 읽을 때 치운다, domain/sample_cleanup).
// 시험 빌드(--dart-define=QA_SEED_LIB=true)는 지금 앱 QA 비교 서재(store/seed.dart)를 넣는다(두 앱을 같은 데이터로 견줄 때)
library;

import 'seed.dart';

const _qaSeedLib = bool.fromEnvironment('QA_SEED_LIB');

Future<void>? _preparing;

/// 한 번만(여러 곳에서 불러도 같은 작업을 기다린다)
Future<void> prepareFirstShelf() => _preparing ??= _prepare();

/// 로그아웃으로 기기 기록을 지운 뒤: 다음에 읽을 때 다시 준비한다
void resetFirstShelf() => _preparing = null;

Future<void> _prepare() async {
  // 보기 책 책등 비율(지금 앱이 잰 실제 두께): 같은 책을 가진 서재도 같은 두께로
  rememberSampleSpineRatios();
  if (_qaSeedLib) return seedIfEmpty();
}
