// 책 정보의 독자 후기(지금 앱 features/community/BookReviews.tsx): 같은 판본(ISBN-13)에 공개로 남긴 후기의 평균·수, 후기 목록, 내 공개 후기(남기기·고치기·지우기).
// 내 별점(개인 기록)과 공개 후기는 따로다: 개인 별점은 자동 공개되지 않고, 공개 후기를 남길 때 처음 값으로만 채워 준다.
// 평가하지 않은 사람은 0점으로 세지 않는다(서버 집계). ISBN이 없거나 커뮤니티를 쓸 수 없는 빌드·서버면 그리지 않는다(available false)
library;

import 'package:flutter/material.dart';

import '../../services/community.dart';
import '../../ui/alert.dart';
import '../../ui/draft_guard.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'community_widgets.dart' show explainWriteError;

/// 한 책의 공개 후기 상태. 책 화면이 들고 있고 머리(독자 평점)와 평가 칸이 함께 본다
class BookReviewsState extends ChangeNotifier {
  BookReviewsState(String? isbn13) : isbn13 = isbn13 != null && RegExp(r'^\d{13}$').hasMatch(isbn13) ? isbn13 : null {
    if (this.isbn13 == null) return;
    communityAvailability().then((a) {
      if (_disposed || !a.ok) return;
      _on = true;
      load();
    });
  }

  final String? isbn13;
  bool _on = false, _disposed = false;
  BookReviews? data;
  String error = '';

  bool get available => isbn13 != null && _on;

  Future<void> load() async {
    final i = isbn13;
    if (i == null) return;
    error = '';
    notifyListeners();
    try {
      data = await Community.reviews(i);
    } catch (e) {
      error = communityError(e);
    }
    if (!_disposed) notifyListeners();
  }

  void set(BookReviews d) {
    data = d;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _avg(num a) => a.toStringAsFixed(1);

/// 저자 아래 한 줄: '독자 평점 ★ 3.5 · 2명'(후기가 있을 때만). 평균은 숫자로(3.5를 별 4개처럼 반올림해 보이지 않게)
class ReaderRating extends StatelessWidget {
  const ReaderRating({super.key, required this.data});
  final BookReviews? data;

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null || d.count == 0 || d.average == null) return const SizedBox.shrink();
    final label = AppType.caption;
    return Semantics(
      label: '독자 평점 ${_avg(d.average!)}점, ${d.count}명',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Space.m),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('독자 평점', style: label),
          const SizedBox(width: 4),
          const LucideIcon('Star', size: 15, color: AppColors.star, fill: AppColors.star, stroke: 1.4),
          const SizedBox(width: 4),
          Text(_avg(d.average!), style: AppType.labelStrong),
          const MetaBar(),
          Text('${d.count}명', style: label),
        ]),
      ),
    );
  }
}

class ReviewsPane extends StatefulWidget {
  const ReviewsPane({super.key, required this.title, this.myRating, required this.state});
  final String title;
  final num? myRating;
  final BookReviewsState state;

  @override
  State<ReviewsPane> createState() => _ReviewsPaneState();
}

class _ReviewsPaneState extends State<ReviewsPane> {
  bool _all = false;

  BookReviewsState get _s => widget.state;

  void _open() {
    final d = _s.data;
    showSheet<void>(
      context,
      title: '공개 후기',
      description: '‘${widget.title}’에 남기는 후기예요. 공개 닉네임과 함께 다른 독자에게 보여요.',
      builder: (_) => _ReviewForm(
        isbn13: _s.isbn13!,
        title: widget.title,
        rating: d?.mine?.rating.round() ?? widget.myRating?.round(),
        body: d?.mine?.body ?? '',
        editing: d?.mine != null,
        onSaved: _s.set,
      ),
    );
  }

  // 지우는 일은 '삭제'(docs/design/DESIGN.md 9장)
  void _remove() => appAlert(context, '내 공개 후기를 삭제할까요?', '내 별점(개인 기록)은 그대로예요.', [
        const AlertButton('취소', style: AlertStyle.cancel),
        AlertButton('삭제', style: AlertStyle.destructive, onPress: () {
          Community.deleteReview(_s.isbn13!).then(_s.set, onError: (Object e) {
            if (mounted) explainWriteError(context, e, '후기를 삭제하지 못했어요');
          });
        }),
      ]);

  Widget _item(String name, num rating, String? body, [List<Widget> actions = const []]) => Padding(
        padding: const EdgeInsets.only(top: Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowStrong)),
            const SizedBox(width: Space.s),
            Stars(value: rating, size: reviewStarSize),
          ]),
          if (body != null && body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Space.s), child: WordText(body, style: AppType.body)),
          if (actions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Wrap(spacing: Space.l, children: actions)),
        ]),
      );

  // 구역 머리는 공용 SectionHead '독자 후기', 불러오는 중은 작은 원, 실패 · 없음은 구역 빈 줄(docs/design/DESIGN.md 11장.
  // 2026-11-19 공통 규칙: '불러오는 중…' 글자, 실패 글에 오류 원문, 없음은 구역 제목 글자로 따로 그렸다)
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _s,
        builder: (context, _) {
          final d = _s.data;
          const head = SectionHead(title: '독자 후기');
          if (_s.error.isNotEmpty) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              head,
              EmptyLine('후기를 불러오지 못했어요. ${_s.error}', action: '다시 시도', onAction: _s.load),
            ]);
          }
          if (d == null) {
            return const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              head,
              Padding(padding: EdgeInsets.only(top: Space.s), child: Align(alignment: Alignment.centerLeft, child: Spinner(label: '후기 불러오는 중'))),
            ]);
          }
          final others = d.items;
          final shown = _all ? others : others.take(5);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            head,
            // 요약은 상자 없이 큰 숫자 + 별 하나 + 'N명 평가'
            if (d.count > 0 && d.average != null)
              Semantics(
                label: '평균 ${_avg(d.average!)}점, ${d.count}명 평가',
                excludeSemantics: true,
                child: Padding(padding: const EdgeInsets.only(top: Space.s), child: Row(children: [
                  Text(_avg(d.average!), style: AppType.score),
                  const SizedBox(width: Space.s),
                  const LucideIcon('Star', size: 26, color: AppColors.star, fill: AppColors.star, stroke: 1.4),
                  const SizedBox(width: Space.s + Space.xs),
                  Text('${d.count}명 평가', style: AppType.sub),
                ])),
              )
            else
              const EmptyLine('아직 독자 후기가 없어요'),
            // 고치기 · 지우기는 '수정' · '삭제'(docs/design/DESIGN.md 9장)
            if (d.mine case final m?)
              _item('내 후기', m.rating, m.body, [
                TextLink(label: '수정', soft: true, start: true, onPress: _open),
                TextLink(label: '삭제', soft: true, start: true, onPress: _remove),
              ]),
            for (final r in shown) _item(r.nickname ?? '', r.rating, r.body),
            if (others.length > 5 && !_all)
              Padding(
                padding: const EdgeInsets.only(top: Space.m),
                child: TextLink(label: '후기 ${others.length}개 모두 보기', soft: true, start: true, onPress: () => setState(() => _all = true)),
              ),
            if (d.mine == null)
              Padding(
                padding: const EdgeInsets.only(top: Space.xxl),
                // 같은 화면 아래 '읽기 시작'이 주요 단추라 보조 단추(한 화면 primary 하나, docs/design/DESIGN.md 5장)
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Btn(label: '공개 후기 남기기', kind: 'secondary', onPress: _open),
                  Padding(padding: const EdgeInsets.only(top: Space.s), child: WordText('게시한 후기는 다른 독자에게 보여요.', textAlign: TextAlign.center, style: AppType.caption)),
                ]),
              ),
          ]);
        },
      );
}

/// 후기 한 줄 별 크기(책 정보 독자 후기 · 독자 프로필 평가가 같은 크기, 2026-11-19 공통 규칙: 16 · 14였다)
const reviewStarSize = 16.0;

class _ReviewForm extends StatefulWidget {
  const _ReviewForm({required this.isbn13, required this.title, required this.rating, required this.body, required this.onSaved, this.editing = false});
  final String isbn13, title, body;
  final int? rating;
  final ValueChanged<BookReviews> onSaved;

  /// 이미 남긴 후기를 고치는 중(나갈 때 묻는 말이 '고친 내용')
  final bool editing;

  @override
  State<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<_ReviewForm> {
  late int? _rating = widget.rating;
  late String _body = widget.body;
  bool _busy = false;

  bool _dirty() => !_busy && (_rating != widget.rating || _body.trim() != widget.body.trim());

  Future<void> _save() async {
    final r = _rating;
    if (r == null || r == 0) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      final b = _body.trim();
      widget.onSaved(await Community.saveReview(widget.isbn13, r, b.isEmpty ? null : b, widget.title));
      nav.pop();
      return;
    } catch (e) {
      if (mounted) explainWriteError(context, e, '후기를 저장하지 못했어요');
    }
    if (mounted) setState(() => _busy = false);
  }

  // 쓰던 후기가 있으면 시트를 닫을 때 묻는다(공용 DraftGuard: 새로 쓰기 · 고치기, 2026-11-19 공통 규칙: 말없이 버려졌다).
  // 별이 없으면 저장할 수 없어 단추 위에 까닭(docs/design/DESIGN.md 9장). 시트 안 확정 단추는 l
  @override
  Widget build(BuildContext context) {
    final noStar = _rating == null || _rating == 0;
    final body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xl),
        child: Center(child: Stars(value: _rating, size: 34, onChange: (v) => setState(() => _rating = v))),
      ),
      Field(label: '후기 (선택)', value: _body, multiline: true, onChange: (v) => setState(() => _body = v.length > 500 ? v.substring(0, 500) : v)),
      if (noStar) const NoticeText('별점을 골라야 저장할 수 있어요.'),
      Padding(
        padding: const EdgeInsets.only(top: Space.item),
        child: Btn(label: '후기 저장', size: 'l', disabled: noStar, busy: _busy, onPress: _save),
      ),
    ]);
    return widget.editing ? DraftGuard.edit(dirty: _dirty, child: body) : DraftGuard(dirty: _dirty, child: body);
  }
}
