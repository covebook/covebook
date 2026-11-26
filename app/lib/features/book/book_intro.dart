// 책 정보 › 책 정보 칸 맨 위 '책 소개'(2026-11-26 사용자 '책 정보에 yes24에서 책 내용 요약 있잖아 그거 넣어서 해줘').
// YES24 상품의 책 소개를 서버로 받아(services/book_search bookIntro) 원문 그대로 보인다: 고치거나 줄이지 않는다(YES24 약관: AI 변환 불가).
// 글은 기기에 저장하지 않는다(앱이 켜져 있는 동안만 기억). 다섯 줄이 넘으면 접어 두고 '더 보기'로 편다.
// 출처: 글 바로 아래 줄 오른쪽 'YES24 제공'(왼쪽은 '더 보기'). 상품 링크는 같은 칸 맨 아래 'YES24에서 보기' 줄이고, 그 줄이 없는 책(YES24 링크 없이 넣은 책)은 출처 자리가
// 'YES24에서 보기' 글자 단추(ISBN으로 찾은 YES24 검색 결과)다. 소개가 없으면(ISBN 없음 · YES24에 없음 · 소개 없음) 구역을 두지 않고,
// 받지 못하면 구역만 실패 한 줄 + '다시 시도'(DESIGN 11장)
library;

import 'package:flutter/material.dart';

import '../../services/book_search.dart' show bookIntro;
import '../../ui/keep_all.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';

/// 접었을 때 보이는 줄 수
const introLines = 5;

class BookIntro extends StatefulWidget {
  const BookIntro({super.key, required this.isbn13, required this.linked, required this.onOpen, this.load = bookIntro});
  final String isbn13;

  /// 같은 칸 아래에 YES24 상품 링크 줄이 있다(출처는 글자만)
  final bool linked;

  /// 'YES24에서 보기'(링크 줄이 없을 때): ISBN으로 YES24 검색 결과를 연다
  final void Function(String url) onOpen;

  /// 시험이 바꿔 끼운다
  final Future<String?> Function(String isbn13) load;

  @override
  State<BookIntro> createState() => _BookIntroState();
}

class _BookIntroState extends State<BookIntro> {
  String? _text;
  bool _done = false, _failed = false, _open = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(BookIntro old) {
    super.didUpdateWidget(old);
    if (old.isbn13 != widget.isbn13) {
      _open = false;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _done = false;
      _failed = false;
    });
    final isbn = widget.isbn13;
    try {
      final t = await widget.load(isbn);
      if (!mounted || isbn != widget.isbn13) return;
      setState(() {
        _text = t;
        _done = true;
      });
    } catch (e) {
      debugPrint('[책 소개] $e');
      if (!mounted || isbn != widget.isbn13) return;
      setState(() {
        _failed = true;
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 받는 동안은 자리를 두지 않는다(아래 책 정보 줄은 바로 보인다)
    if (!_done) return const SizedBox.shrink();
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.block),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHead(title: '책 소개'),
          EmptyLine('책 소개를 불러오지 못했어요', action: '다시 시도', onAction: _fetch),
        ]),
      );
    }
    final text = _text;
    if (text == null) return const SizedBox.shrink();
    final style = AppType.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.block),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionHead(title: '책 소개'),
        const SizedBox(height: Space.s),
        LayoutBuilder(builder: (context, c) {
          // 다섯 줄이 넘는지는 보이는 글자 그대로(낱말 단위 줄바꿈 keepAll) 재 본다
          final tp = TextPainter(
            text: TextSpan(text: keepAll(text), style: style),
            maxLines: introLines,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: c.maxWidth);
          final long = tp.didExceedMaxLines;
          tp.dispose();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            WordText(text, style: style, maxLines: _open || !long ? null : introLines, overflow: _open || !long ? null : TextOverflow.ellipsis),
            // 글 바로 아래 한 줄: 왼쪽 '더 보기 · 접기', 오른쪽 출처(따로 두 줄이면 사이가 휑했다, 2026-11-26 에뮬 확인).
            // YES24 약관: 출처와 상품 링크를 함께 보인다
            Row(children: [
              if (long) TextLink(label: _open ? '접기' : '더 보기', soft: true, start: true, onPress: () => setState(() => _open = !_open)),
              const Spacer(),
              if (widget.linked)
                Padding(padding: const EdgeInsets.symmetric(vertical: Space.s), child: Text('YES24 제공', style: AppType.caption))
              else
                TextLink(label: 'YES24에서 보기', soft: true, end: true, onPress: () => widget.onOpen('https://www.yes24.com/Product/Search?query=${Uri.encodeQueryComponent(widget.isbn13)}')),
            ]),
          ]);
        }),
      ]),
    );
  }
}
