/// 앱 안 결제의 앱 쪽(스토어 결제 창 ↔ 서버 검증). 서버 키트(server/iapkit)와 짝이다.
/// 붙이는 법: README.md. 앱은 IapKit.configure로 서버 호출·저장소·문구를 넣고, 화면은 앱이 만든다.
library;

export 'src/entitlements.dart';
export 'src/kit.dart';
export 'src/notices.dart';
export 'src/plan.dart';
export 'src/service.dart';
