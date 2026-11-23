// 책장에서 책을 짧게 누르면 아래에서 올라오는 책 정보 시트(지금 앱 features/home/BookSheet.tsx, 2026-10-31 책장 시안).
// 왼쪽 작은 표지(실제 표지 사진, 없거나 못 읽으면 이 책의 장정 정면 + '꾸민 표지'), 오른쪽 제목·읽기 상태·한 줄 감상·최근 메모,
// 아래 '책 정보 보기'(주요 큰 단추)와 보조 둘 '갈피 남기기 | 읽기 시작(이어서 읽기)'(글자만, 옛 시안 그대로. 책 정보 아래 두 단추와 같은 순서).
// '책장에서 빼기'는 표지 · 제목 줄 오른쪽 아래, '책 정보 보기' 바로 위 회색 휴지통 아이콘 단추(화면 읽기 이름 '책장에서 빼기').
// 2026-11-23 손잡이 줄 오른쪽 글자 단추로 옮겼다가 줄이 48로 높아져 시트가 올라와 보여 2026-11-24 사용자 '버튼 우측 바로 위에 쓰레기 아이콘으로'. 손잡이 줄은 옛 높이로.
// 선반은 그대로 보이게 바탕을 어둡게 덮지 않는다.
// 배치 조작은 꾹 눌러 꾸미기에서
library;

import 'package:flutter/material.dart';

import '../../domain/cover_url.dart';
import '../../domain/library.dart';
import '../../domain/reference_home.dart' show referenceBooks;
import '../../domain/types.dart' show Book;
import '../../ui/standalone_book.dart' show StandaloneBook;
import '../book/add_book_screen.dart' show openAddBook;
import '../../store/library_model.dart';
import '../../store/placement_store.dart';
import '../../ui/alert.dart';
import '../../ui/book_visual.dart';
import '../../ui/feedback.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../book/book_screen.dart' show openBook;
import '../bookmark/book_picker.dart' show statusLabel;
import '../reading/start_book.dart' show startReadingBook;
import '../stats/stats_widgets.dart' show CoverImage;
import '../bookmark/new_bookmark_screen.dart';

/// 빼기 아이콘(누르는 자리 48, 그림 22)이 표지 · 제목 줄 아래 틈으로 내려가는 만큼: 그림 아래 끝이 줄 아래 끝(표지 아래)과 맞는다
const _trashDrop = (Space.hit - IconSize.base) / 2;

/// 표지 폭: 내 책 목록 표지와 같은 80(시안 실측 104였는데 시트가 아래로 너무 길었다, 2026-11-20 사용자 '여기도 밑으로 너무 기네')
const _coverW = CoverSize.list;

/// 가장 최근 메모(독서 기록·갈피, 적어 둔 것만)
String? latestMemo(Library lib, String bookId) {
  ({String text, String at})? best;
  for (final s in lib.sessions.values) {
    final t = s.memo?.trim() ?? '';
    if (s.myBookId != bookId || t.isEmpty) continue;
    final at = sessionDay(s);
    if (best == null || at.compareTo(best.at) > 0) best = (text: t, at: at);
  }
  for (final m in lib.bookmarks.values) {
    final t = m.memo?.trim() ?? '';
    if (m.myBookId != bookId || t.isEmpty) continue;
    if (best == null || m.createdAt.compareTo(best.at) > 0) best = (text: t, at: m.createdAt);
  }
  return best?.text;
}

/// view·status·readOnly: 지난 연도 책장(보기 전용)에서 그해 기록(그해 서재·'2025년 | 완독', metaSep으로 이은 것)으로 연다. 읽기·갈피 단추가 없고,
/// 지금 서재에 보이지 않는 책(숨긴 책)은 '책 정보 보기'도 없다(지금 앱 BookSheet readOnly)
Future<void> showBookSheet(BuildContext context, String bookId, {Library? view, String? status, bool readOnly = false}) async {
  final model = LibraryModel.instance;
  await model.load();
  if (!context.mounted) return;
  final lib = view ?? model.lib;
  final canOpen = model.lib.books.containsKey(bookId) && model.lib.books[bookId]!.hiddenAt == null;
  final b = lib.books[bookId];
  final e = b == null ? null : lib.editions[b.editionId];
  final canRemove = canOpen && !readOnly;
  // 새 서재 예시 책(표시 전용, 서재에 없음): 읽기·갈피 대신 '이 책을 내 책에 추가'(지금 앱 BookSheet sample)
  if (b == null && view == null && referenceBooks[bookId] != null) return _sampleSheet(context, referenceBooks[bookId]!);
  if (b == null || e == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent, // 바탕은 덮지 않는다(시안): 선반을 누르면 닫힌다
    barrierLabel: '닫기', // 화면 읽기에서 영어 'Scrim'으로 읽혔다(2026-11-16 QA 영숙 F10)
    builder: (ctx) {
      final insets = MediaQuery.paddingOf(ctx);
      final ratio = (e.heightMm ?? 0) > 0 && (e.widthMm ?? 0) > 0 ? e.heightMm! / e.widthMm! : 188 / 128;
      final memo = latestMemo(lib, bookId);
      return Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Shape.sheet)),
          boxShadow: [BoxShadow(color: Color(0x1A6F5843), blurRadius: 16, offset: Offset(0, -2))],
        ),
        padding: EdgeInsets.fromLTRB(Space.page + 4, 0, Space.page + 4, insets.bottom + 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 표지 · 제목 줄. 빼기 아이콘이 있으면 오른쪽 아래(책 정보 보기 바로 위)에 두고, 누르는 자리 48이 줄 아래 틈까지 걸치게
                    // 줄 아래 틈 일부(_trashDrop)를 이 칸 안에 넣는다(칸 밖으로 나간 자리는 눌리지 않는다). 글은 아이콘 자리를 비운다
                    Padding(
                      padding: const EdgeInsets.only(top: Space.l),
                      child: Stack(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(bottom: canRemove ? _trashDrop : 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: _coverW + 6,
                                  child: e.coverUri != null
                                      ? Center(
                                          child: CoverImage(
                                            uris: [coverAtSize(e.coverUri, 'L'), e.coverUri],
                                            color: AppColors.input,
                                            width: _coverW,
                                            height: (_coverW * ratio).roundToDouble(),
                                            radius: Shape.cover,
                                          ),
                                        )
                                      : Column(
                                          children: [
                                            BookVisual(lib: lib, id: bookId, width: _coverW + 6),
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text('꾸민 표지', textAlign: TextAlign.center, style: AppType.caption),
                                            ),
                                          ],
                                        ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(right: canRemove ? Space.hit : 0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 시트 머리 책 제목은 bookTitle(DESIGN 3-1)
                                        Semantics(header: true, child: Text(e.title, style: AppType.bookTitle)),
                                        // 지난 책장은 '2025년 | 완독': 세로줄은 옅게, 화면 읽기는 쉼표로(MetaText)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: MetaText(status ?? statusLabel[b.status]!, style: AppType.caption),
                                        ),
                                        if ((b.note ?? '').isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: Space.s),
                                            child: Text(
                                              b.note!,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppType.sub.copyWith(color: AppColors.ink),
                                            ),
                                          ),
                                        if (memo != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: Space.s),
                                            child: Semantics(
                                              label: '최근 메모, $memo',
                                              excludeSemantics: true,
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Padding(
                                                    padding: EdgeInsets.only(top: 3),
                                                    child: LucideIcon('StickyNote', size: 14, color: AppColors.icon),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(memo, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.caption),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 책장에서 빼기 바로가기(2026-11-15 QA: 책 정보 › 더 보기 안쪽에만 있어 세 단계였다). 책은 내 책에 남고, 바로 되돌릴 수 있다.
                          // 2026-11-24 사용자 '왤케 올라와있지 … 버튼 우측 바로 위에 쓰레기 아이콘으로': 손잡이 줄 글자 단추(줄이 48로 높아졌다)에서 옮김
                          if (canRemove)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: IconBtn(
                                label: '책장에서 빼기',
                                onPress: () async {
                                  Navigator.pop(ctx);
                                  final place = PlacementStore.instance;
                                  Object? err;
                                  var ok = false;
                                  try {
                                    await place.ensure();
                                    ok = await place.toDrawer(bookId);
                                  } catch (e) {
                                    err = e;
                                  }
                                  if (!context.mounted) return;
                                  // 실패는 늘 알린다(DESIGN 11장): 책은 책장에 그대로 있다
                                  if (!ok) {
                                    appAlert(context, '책장에서 빼지 못했어요', '책은 책장에 그대로 있어요. ${err == null ? '잠시 뒤 다시 시도해 주세요.' : errorText(err)}');
                                    return;
                                  }
                                  // 책장에서 사라지는 일이라 토스트 + 되돌리기(DESIGN 14장)
                                  showToast(context, '책장에서 뺐어요. 내 책에 그대로 있어요.', action: '되돌리기', onAction: () => place.undo());
                                },
                                child: const LucideIcon('Trash2', color: AppColors.icon),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (canOpen)
                      Padding(
                        padding: EdgeInsets.only(top: canRemove ? Space.l - _trashDrop : Space.l),
                        child: Btn(
                          label: '책 정보 보기',
                          size: 'xlarge',
                          onPress: () {
                            Navigator.pop(ctx);
                            openBook(context, bookId);
                          },
                        ),
                      ),
                    if (!readOnly)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        // 보조 행동(지금 앱 TextActions, 옛 시안 그대로 둔 의도된 예외, TextLink로 맞출지는 사용자 결정 대기): 본문색 보통 글씨, 사이 얇은 세로선, 누르는 칸 48.
                        // 순서는 책 정보 아래 두 단추와 같다(갈피 남기기 · 읽기)
                        child: Row(
                          children: [
                            _textAction('갈피 남기기', () {
                              Navigator.pop(ctx);
                              openNewBookmark(context, book: bookId);
                            }),
                            Container(width: 1, height: 18, color: AppColors.line),
                            // 누르면 그 책으로 바로 독서를 시작하고 읽기 화면을 연다(2026-11-16 QA 영숙 F2: 장면만 열리고 시계가 가지 않았다)
                            _textAction(b.status == ReadStatus.reading || b.status == ReadStatus.paused ? '이어서 읽기' : '읽기 시작', () {
                              Navigator.pop(ctx);
                              startReadingBook(context, bookId);
                            }),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// 예시 책 시트: 책장과 같은 그림의 앞모습, 제목, '예시 책이에요 / 내 책에는 없어요', 같은 제목으로 책 추가
Future<void> _sampleSheet(BuildContext context, Book sample) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.transparent,
  barrierLabel: '닫기',
  builder: (ctx) {
    final insets = MediaQuery.paddingOf(ctx);
    final dims = sample.dims;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Shape.sheet)),
        boxShadow: [BoxShadow(color: Color(0x1A6F5843), blurRadius: 16, offset: Offset(0, -2))],
      ),
      padding: EdgeInsets.fromLTRB(Space.page + 4, 0, Space.page + 4, insets.bottom + 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: _coverW + 6,
                  child: Center(
                    child: StandaloneBook(book: sample, scale: _coverW / (dims?.coverWidth ?? 118)),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(header: true, child: Text(sample.title, style: AppType.bookTitle)),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('예시 책이에요\n내 책에는 없어요', style: AppType.caption),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Btn(
              label: '이 책을 내 책에 추가',
              size: 'xlarge',
              onPress: () {
                Navigator.pop(ctx);
                openAddBook(context, q: sample.title);
              },
            ),
          ),
        ],
      ),
    );
  },
);

Widget _textAction(String label, VoidCallback onPress) => Expanded(
  child: Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onPress,
    child: Pressable(
      onPress: onPress,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: WordText(
              label,
              textAlign: TextAlign.center,
              style: AppType.sub.copyWith(color: AppColors.ink),
            ),
          ),
        ),
      ),
    ),
  ),
);
