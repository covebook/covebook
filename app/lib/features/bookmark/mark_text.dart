// 갈피 글 정리와 한 줄 표시(2026-11-16 QA 은서): 저장할 때 첫 줄 들여쓰기를 지키고(F10), 사진 갈피와 문장 갈피를 같은 규칙으로 나누고(F11),
// 삭제 확인창에 어느 갈피인지 보인다(F1)
library;

final _leadBlank = RegExp(r'^(?:[ \t　]*\r?\n)+');
final _ws = RegExp(r'\s+');

/// 저장할 글: 앞의 빈 줄과 끝 공백만 정리한다. 첫 줄 앞 공백(시 들여쓰기)과 줄 안의 공백은 그대로(전에는 trim으로 첫 줄 들여쓰기가 지워졌다)
String tidyMarkText(String t) => t.replaceFirst(_leadBlank, '').trimRight();

/// 사진 갈피 = 사진만 남긴 갈피(글 없음). 글이 있으면 사진은 원본으로 곁들인 문장 갈피다
bool isPhotoMark(String text, String? photoUri) => (photoUri ?? '').isNotEmpty && text.trim().isEmpty;

/// 쪽 표기(카드·공유 모두 같은 모양)
String pageLabel(num page) => 'p. $page';

/// 어느 갈피인지 한 줄: 문장 앞부분(없으면 '사진 갈피')과 쪽
String markLabel(String text, num? page, {int max = 24}) {
  final t = text.trim().replaceAll(_ws, ' ');
  final chars = t.runes.toList();
  final head = t.isEmpty ? '사진 갈피' : '“${chars.length > max ? '${String.fromCharCodes(chars.take(max)).trimRight()}…' : t}”';
  return page != null && page != 0 ? '$head · ${pageLabel(page)}' : head;
}
