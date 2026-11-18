// 여러 권 한꺼번에 추가(2026-11-15 사용자 '다 넣어', 페르소나 QA 장서가 F2): 검색 결과 여러 권 고르기·바코드 연속 스캔·목록 파일 가져오기가 같이 쓴다.
// 한 권씩 고른 판본의 상세를 읽고 추천 장정(책 추가와 같은 계산)으로 서재에 더한 뒤, 다 더하고 나서 한 번에 책장에 놓는다
// (자리가 모자라면 한 번만 묻는다, place_books). 진열 규칙은 한 권 추가와 같다
library;

import '../../app/app_nav.dart' show AppNav;
import 'package:flutter/material.dart';

import '../../domain/library.dart';
import '../../domain/rebinding.dart';
import '../../services/book_search.dart';
import '../../services/cover_colors.dart' show coverDominantColor, coverPalette, measureCover;
import '../../store/library_model.dart';
import '../../store/placement_store.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'all_books_screen.dart' show openAllBooks;
import 'place_books.dart';

/// 추천 장정 계산(책 추가 확인 단계와 같은 식): 표지는 색 추출에만 쓰고(화면에 그리지 않는다) 결과 장정만 저장한다.
/// 표지 색을 못 읽었으면 판 번호를 낮춰 다음 시작 때 다시 맞춘다(표지 색 맞추기)
Future<BookArtParams> recommendedArt({
  required String title,
  String? isbn,
  String? publisher,
  String? publishedAt,
  int? pageCount,
  SizeMm? size,
  String? category,
  String? seriesTitle,
  String? coverUri,
  bool apiCover = false,
}) async {
  final api = apiCover && coverUri != null;
  final palette = api ? await coverPalette(coverUri) : null;
  if (api) await measureCover(coverUri);
  final coverColor = api ? await coverDominantColor(coverUri) : null;
  final year = int.tryParse((publishedAt ?? '').length >= 4 ? publishedAt!.substring(0, 4) : '') ?? 0;
  final code = (isbn ?? '').replaceAll(RegExp(r'[^\dXx]'), '');
  final built = buildBookArt(
    RebindInput(
      title: title.trim(),
      isbn: code.isEmpty ? null : code,
      authors: const [],
      publisher: publisher ?? '',
      publishedYear: year > 0 ? year : null,
      pageCount: pageCount,
      heightMm: size?.heightMm,
      widthMm: size?.widthMm,
      category: category,
      seriesTitle: seriesTitle,
      palette: palette,
      coverColor: coverColor,
    ),
    DateTime.now().toUtc().toIso8601String(),
  );
  return BookArtParams(built.baseColor, built.inkColor, built.accentColor, built.motifId, built.layoutVariant, built.heightClass, built.thicknessClass, built.generatedAt,
      api && coverColor == null ? 1 : built.version);
}

/// 고른 판본 하나를 추천 장정으로 서재에 더한다(책장에는 아직 놓지 않는다). 새 책 id
Future<String> addCandidateBook(BookCandidate picked, {ReadStatus status = ReadStatus.want}) async {
  final c = await candidateDetails(picked);
  final art = await recommendedArt(
    title: c.title,
    isbn: c.isbn13,
    publisher: c.publisher,
    publishedAt: c.publishedAt,
    pageCount: c.pageCount,
    size: c.size,
    category: c.category,
    seriesTitle: c.seriesTitle,
    coverUri: c.coverUrl,
    apiCover: c.coverUrl != null,
  );
  final isbn = (c.isbn13 ?? '').replaceAll(RegExp(r'[^\dXx]'), '');
  return LibraryModel.instance.addBook(
    title: c.title.trim(),
    authors: [for (final a in c.authors) if (a.trim().isNotEmpty) a.trim()],
    publisher: c.publisher,
    publishedAt: c.publishedAt,
    isbn13: isbn.isEmpty ? null : isbn,
    pageCount: c.pageCount,
    widthMm: c.size?.widthMm,
    heightMm: c.size?.heightMm,
    category: c.category,
    seriesTitle: c.seriesTitle,
    art: art,
    coverUri: c.coverUrl,
    coverSource: c.coverUrl != null ? 'api' : null,
    source: 'search',
    sourceName: c.sourceName,
    link: c.link,
    productId: c.productId,
    status: status,
  );
}

/// 한 권 추가할 것
typedef BulkPick = ({BookCandidate book, ReadStatus status});

/// 여러 권 추가 결과: 새 책 id, 책장에 놓은 수, 전체 책에만 보관한 수, 실패한 책 제목
typedef BulkResult = ({List<String> ids, int placed, int kept, bool full, List<String> failed});

/// 여러 권을 차례로 더하고(진행 창) 다 더한 뒤 한 번에 책장에 놓는다. 한 권이 실패해도 나머지는 더한다.
/// 진행 창의 '그만하기'를 누르면 지금 책까지만 더하고 멈춘다(더한 책은 그대로 놓는다)
Future<BulkResult> addBooks(BuildContext context, List<BulkPick> picks) async {
  final done = ValueNotifier<int>(0);
  final stop = ValueNotifier<bool>(false);
  final ids = <String>[], failed = <String>[];
  final nav = Navigator.of(context, rootNavigator: true);
  var open = true;
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: AppColors.scrim,
    useRootNavigator: true,
    pageBuilder: (ctx, _, _) => PopScope(canPop: false, child: _Progress(done: done, stop: stop, total: picks.length)),
  ).whenComplete(() => open = false);
  try {
    for (final p in picks) {
      if (stop.value) break;
      try {
        ids.add(await addCandidateBook(p.book, status: p.status));
      } catch (_) {
        failed.add(p.book.title);
      }
      done.value++;
    }
    await PlacementStore.instance.reload();
  } finally {
    if (open) nav.pop();
  }
  if (ids.isEmpty || !context.mounted) return (ids: ids, placed: 0, kept: ids.length, full: false, failed: failed);
  final r = await placeWithChoice(context, ids);
  return (ids: ids, placed: r.placed, kept: ids.length - r.placed, full: r.full, failed: failed);
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.stop, required this.total});
  final ValueNotifier<int> done;
  final ValueNotifier<bool> stop;
  final int total;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.page),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Material(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(Shape.dialog),
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: ValueListenableBuilder<int>(
                  valueListenable: done,
                  builder: (_, n, _) => Semantics(
                    liveRegion: true,
                    label: '$total권 중 $n권 추가했어요',
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('책을 추가하는 중이에요', style: AppType.section),
                      const SizedBox(height: Space.s),
                      Text('$total권 중 $n권', style: AppType.sub.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                      const SizedBox(height: Space.l),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: total == 0 ? null : n / total, minHeight: 6, color: AppColors.accent, backgroundColor: AppColors.surface),
                      ),
                      if (total > 3)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.m),
                          child: ValueListenableBuilder<bool>(
                            valueListenable: stop,
                            builder: (_, stopped, _) => Center(
                              child: TextLink(label: stopped ? '이 책까지만 추가해요' : '그만하기', soft: true, disabled: stopped, onPress: () => stop.value = true),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// 여러 권 추가 뒤 결과 시트. 'shelf' 책장에서 보기 · 'books' 전체 책 보기 · null 계속
Future<String?> showBulkDone(BuildContext context, BulkResult r) {
  String? next;
  final added = r.ids.length;
  final lines = [
    if (r.placed > 0) '책장에 ${r.placed}권 진열했어요.',
    // 꽉 차서 보관했으면 사실대로(2026-11-15 QA 정우 F1)
    if (r.kept > 0) r.full ? '${r.kept}권은 책장이 꽉 차서 내 책에 보관했어요.' : '${r.kept}권은 내 책에만 보관했어요.',
    if (r.failed.isNotEmpty) '${r.failed.length}권은 추가하지 못했어요: ${r.failed.take(3).join(', ')}${r.failed.length > 3 ? ' 외' : ''}',
  ];
  return showSheet<void>(
    context,
    title: added > 0 ? '$added권을 추가했어요' : '추가하지 못했어요',
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: Space.xs), child: Text(l, style: AppType.body)),
      const SizedBox(height: Space.l),
      if (r.placed > 0)
        Btn(label: '책장에서 보기', onPress: () {
          next = 'shelf';
          Navigator.pop(ctx);
        })
      else if (added > 0)
        Btn(label: '내 책 보기', onPress: () {
          next = 'books';
          Navigator.pop(ctx);
        }),
      SubAction(label: '계속 추가', onPress: () => Navigator.pop(ctx)),
    ]),
  ).then((_) => next);
}

/// 결과 시트에서 고른 곳으로 간다(책장 = 첫 화면까지 닫기, 전체 책 = 책장에 없는 책)
void goAfterBulk(BuildContext context, String? next) {
  if (next == null || !context.mounted) return;
  final nav = Navigator.of(context, rootNavigator: true);
  nav.popUntil((r) => r.isFirst);
  // 다른 탭에서 넣었어도 책장 탭으로
  if (next == 'shelf') AppNav.instance.goTab(0);
  if (next == 'books' && nav.context.mounted) openAllBooks(nav.context, offShelf: true);
}
