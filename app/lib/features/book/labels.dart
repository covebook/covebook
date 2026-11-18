// 책·기록 글자(지금 앱 features/book/labels.ts)
library;

/// 날짜 쓰는 법은 두 가지(2026-11-17 사용자 '그렇게 통일해'): 목록·카드는 [dateShort] '11월 15일'(올해가 아니면 '2025년 11월 15일'),
/// 상세·날짜 칸은 [dateLong] '2026년 11월 15일'. 시각이 든 값(UTC ISO)은 기기 현지 날짜로 읽는다
DateTime? _day(String? d) {
  if (d == null || d.isEmpty) return null;
  if (d.length > 10) return DateTime.tryParse(d)?.toLocal();
  final p = d.split(RegExp('[-.]')).map(int.tryParse).toList();
  return p.length == 3 && !p.contains(null) ? DateTime(p[0]!, p[1]!, p[2]!) : null;
}

/// 목록·카드 날짜: '11월 15일', 올해가 아니면 '2025년 11월 15일'
String dateShort(String? d, {DateTime? now}) {
  final t = _day(d);
  if (t == null) return d ?? '';
  return t.year == (now ?? DateTime.now()).year ? '${t.month}월 ${t.day}일' : dateLong(d);
}

/// 상세·날짜 칸 날짜: '2026년 11월 15일'
String dateLong(String? d) {
  final t = _day(d);
  return t == null ? (d ?? '') : '${t.year}년 ${t.month}월 ${t.day}일';
}

/// 기록 열쇠·시험용 숫자 날짜(화면 글자는 [dateShort]·[dateLong]). '2026-11-05T…' → '2026.11.05'. 시각이 든 값(UTC ISO)은 기기 현지 날짜로: 앞 10자만 자르면 한국 0~9시에 남긴 갈피가 전날로 보였다
/// (지금 앱 labels.ymd도 같은 버그 — Flutter에서만 고친다). 날짜만 있는 값('2026-11-05')은 그대로
String ymd(String? d) {
  if (d == null || d.isEmpty) return '';
  final t = d.length > 10 ? DateTime.tryParse(d) : null;
  if (t == null) return (d.length > 10 ? d.substring(0, 10) : d).replaceAll('-', '.');
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}.${two(l.month)}.${two(l.day)}';
}
