// 책·기록 글자(지금 앱 features/book/labels.ts)
library;

import '../../domain/library.dart' show ReadStatus;
import '../../ui/kit.dart' show clockText;

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

/// 날짜 사이: '11월 5일 ~ 11월 14일'(같은 날이면 하나). 시간 사이는 [timeRange]의 짧은 '-'(2026-11-18 시안)와 다르게 띄운 '~'
String dateRange(String? a, String? b) {
  final x = dateShort(a), y = dateShort(b);
  return b == null || x == y ? x : '$x ~ $y';
}

/// 가까운 날을 말로: '오늘' · '어제' · '3일 전'(6일 전까지), 그 밖은 [dateShort]. 지난 일을 알릴 때(멈춰 둔 독서 · 마지막 동기화)
String relativeDay(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now(), l = t.toLocal();
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(l.year, l.month, l.day)).inDays;
  if (days <= 0) return '오늘';
  if (days == 1) return '어제';
  if (days < 7) return '$days일 전';
  return dateShort(l.toIso8601String(), now: n);
}

/// 날과 시각: '오늘 오후 9:05' · '어제 오후 9:05' · '11월 15일 오후 9:05'(며칠 전이어도 시각만 보이지 않게)
String dateTimeLabel(DateTime t, {DateTime? now}) {
  final l = t.toLocal(), n = now ?? DateTime.now();
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(l.year, l.month, l.day)).inDays;
  final day = days <= 0 ? '오늘' : days == 1 ? '어제' : dateShort(l.toIso8601String(), now: n);
  return '$day ${clockText(l.hour, l.minute)}';
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

/// 읽기 상태 이름과 고르는 차례(책 추가 · 내 책 · 책 정보 · 책장 시트가 같이 쓴다. 2026-11-19: 같은 목록이 세 벌, 이름은 갈피 책 고르기 파일에 있었다)
const statusLabel = {ReadStatus.want: '읽기 전', ReadStatus.reading: '읽는 중', ReadStatus.read: '완독', ReadStatus.paused: '보류'};
const bookStatuses = [ReadStatus.want, ReadStatus.reading, ReadStatus.read, ReadStatus.paused];
