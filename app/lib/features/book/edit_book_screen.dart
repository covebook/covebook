// 책 정보 수정(지금 앱 app/book/[id]/edit.tsx, 판본 정보): 잘못 인식·입력한 값을 고친다. 비운 값은 '미입력'이 된다.
// 크기를 바꾸면 책장에서 책 크기도 바뀐다(자리가 모자라면 그 선반 끝 책이 책장에서 빠진다). 고친 칸이 있으면 나가기 전에 묻는다(공용 DraftGuard.edit)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../store/files.dart' show keepImage;
import '../../domain/library.dart' show authorLine;
import '../../store/library_model.dart';
import '../../store/placement_store.dart';
import '../../ui/draft_guard.dart';
import '../../ui/feedback.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'book_widgets.dart';

Future<void> openEditBook(BuildContext context, String id) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/book/edit'), builder: (_) => EditBookScreen(id: id)));

class EditBookScreen extends StatefulWidget {
  const EditBookScreen({super.key, required this.id});
  final String id;

  @override
  State<EditBookScreen> createState() => _EditBookScreenState();
}

class _EditBookScreenState extends State<EditBookScreen> {
  final _model = LibraryModel.instance;
  late final Map<String, String?> _f0 = () {
    final b = _model.lib.books[widget.id];
    final e = b == null ? null : _model.lib.editions[b.editionId];
    return <String, String?>{
      'title': e?.title ?? '',
      'authors': e == null ? '' : authorLine(e.authors),
      'publisher': e?.publisher ?? '',
      'publishedAt': e?.publishedAt ?? '',
      'isbn': e?.isbn13 ?? '',
      'pages': e?.pageCount != null ? '${e!.pageCount}' : '',
      'width': e?.widthMm != null && e?.heightMm != null ? '${e!.widthMm}' : '',
      'height': e?.widthMm != null && e?.heightMm != null ? '${e!.heightMm}' : '',
      'coverUri': e?.coverUri,
      'coverSource': e?.coverSource,
    };
  }();
  late final Map<String, String?> _f = {..._f0};
  /// 표지 아래 한 줄: 권한 안내(sub) 또는 오류(빨강)
  ({String text, bool error})? _msg;

  /// 저장하지 못했을 때 저장 단추 바로 위 오류 글(고친 칸은 그대로 남는다)
  String? _saveError;

  /// 저장을 한 번 눌렀는지(칸 오류는 그 뒤에 보인다: docs/design/DESIGN.md 12장)
  bool _tried = false;
  bool _saving = false;

  bool get _dirty => _f.entries.any((e) => _f0[e.key] != e.value);

  /// 판형은 가로 · 세로를 함께 적어야 한다(하나만 적으면 말없이 둘 다 버려졌다). 빈 칸 쪽에 오류
  String? _sizeError(String k) {
    final w = numOf(_f['width']!), h = numOf(_f['height']!);
    if ((w == null) == (h == null)) return null;
    if (k == 'width' && w == null) return '가로도 적어 주세요';
    if (k == 'height' && h == null) return '세로도 적어 주세요';
    return null;
  }

  void _set(String k, String? v) => setState(() => _f[k] = v);

  Future<void> _save() async {
    final b = _model.lib.books[widget.id];
    final e = b == null ? null : _model.lib.editions[b.editionId];
    if (_saving || e == null) return;
    if (_sizeError('width') != null || _sizeError('height') != null) {
      setState(() => _tried = true);
      return;
    }
    var coverUri = _f['coverUri'];
    setState(() {
      _saving = true;
      _saveError = null;
    });
    if (coverUri != e.coverUri && _f['coverSource'] == 'photo' && coverUri != null) {
      // 사진을 앱 안으로 옮기는 동안 두 번 눌리지 않게, 실패하면 알린다
      try {
        coverUri = await keepImage(coverUri, 'cover');
      } catch (_) {
        if (mounted) {
          setState(() {
            _saving = false;
            _msg = (text: '표지 사진을 저장하지 못했어요. 다시 골라 주세요.', error: true);
          });
        }
        return;
      }
    }
    final w = numOf(_f['width']!), h = numOf(_f['height']!);
    final isbn = cleanIsbn(_f['isbn']);
    String? opt(String k) => _f[k]!.trim().isEmpty ? null : _f[k]!.trim();
    final int moved;
    try {
      await _model.updateEdition(
        e.id,
        title: _f['title']!.trim().isEmpty ? e.title : _f['title']!.trim(),
        authors: [for (final a in _f['authors']!.split(',')) if (a.trim().isNotEmpty) a.trim()],
        publisher: opt('publisher'),
        publishedAt: opt('publishedAt'),
        isbn13: isbn.isEmpty ? null : isbn,
        pageCount: numOf(_f['pages']!),
        widthMm: w != null && h != null ? math.min(w, h) : null,
        heightMm: w != null && h != null ? math.max(w, h) : null,
        coverUri: coverUri,
        coverSource: coverUri != null ? _f['coverSource'] : null,
      );
      // 크기가 바뀌었으면 책장에서도 맞춘다(안 들어가면 끝 책이 빠진다)
      moved = await PlacementStore.instance.reload();
    } catch (err) {
      // 쓰던 칸이 있는 화면의 저장 실패는 화면 안 글로(고친 내용은 그대로, docs/design/DESIGN.md 11장)
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = '저장하지 못했어요. 고친 내용은 그대로 있어요. ${errorText(err)}';
        });
      }
      return;
    }
    if (!mounted) return;
    // 책 크기가 바뀌어 책장에서 빠진 책이 있으면 토스트로(2026-11-19 공통 규칙: 두 문장이 확인창 제목이었다)
    if (moved > 0) showToast(context, '책 크기가 바뀌어 $moved권을 책장에서 뺐어요. 내 책에서 다시 진열할 수 있어요.');
    // 저장했으니 나가기 확인(DraftGuard)을 거치지 않고 닫는다(Navigator.pop은 묻지 않는다)
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final b = _model.lib.books[widget.id];
    if (b == null || _model.lib.editions[b.editionId] == null) {
      return Screen(title: '책 정보 수정', children: [
        Empty(title: '책을 찾을 수 없어요', action: '돌아가기', actionKind: 'secondary', onAction: () => Navigator.of(context).maybePop()),
      ]);
    }
    // 나가기 확인은 공용 DraftGuard.edit('고친 내용을 버릴까요?' · '계속 수정', 2026-11-19 공통 규칙: 직접 만든 PopScope에 '계속 쓰기'였다)
    return DraftGuard.edit(
      dirty: () => _dirty && !_saving,
      child: Screen(
        title: '책 정보 수정',
        // 화면 아래 주요 단추 l, 이름 '○○ 저장'(docs/design/DESIGN.md 5장). 제목이 비면 할 일이 없어 꺼 두고 까닭은 단추 위에
        footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (_saveError case final m?)
            Padding(padding: const EdgeInsets.only(bottom: Space.s), child: NoticeText(m, error: true))
          else if (_f['title']!.trim().isEmpty)
            const Padding(padding: EdgeInsets.only(bottom: Space.s), child: NoticeText('제목을 적어야 저장할 수 있어요.')),
          Btn(label: '책 정보 저장', size: 'l', onPress: _save, busy: _saving, disabled: _f['title']!.trim().isEmpty),
        ]),
        children: [
          // 표지 96 · 사이 16 · 표지 단추(책 확인과 같은 이름 · 모양) · 글자만 '표지 삭제'(2026-11-19 공통 규칙)
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RealCover(uri: _f['coverUri'], title: _f['title']!, width: CoverSize.edit),
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CoverPhotoButton(
                    hasCover: _f['coverUri'] != null,
                    onPicked: (uri) => setState(() {
                      _f['coverUri'] = uri;
                      _f['coverSource'] = 'photo';
                    }),
                    onDenied: (m) => setState(() => _msg = (text: m, error: false)),
                    onError: (m) => setState(() => _msg = (text: m, error: true)),
                  ),
                  if (_f['coverUri'] != null)
                    TextLink(
                      label: '표지 삭제',
                      soft: true,
                      start: true,
                      onPress: () => setState(() {
                        _f['coverUri'] = null;
                        _f['coverSource'] = null;
                      }),
                    ),
                  if (_msg case final m?) NoticeText(m.text, error: m.error),
                ]),
              ),
            ]),
          ),
          // 기본 정보(제목 필수) / 추가 서지정보(모두 선택)를 구역 이름과 간격으로 나눈다
          const H2('기본 정보'),
          Field(label: '제목 (필수)', value: _f['title']!, onChange: (t) => _set('title', t)),
          // 여러 저자는 쉼표로 나눠 저장한다(책 추가와 같은 안내)
          Field(label: '저자 (선택)', value: _f['authors']!, onChange: (t) => _set('authors', t), placeholder: '여러 명은 쉼표로'),
          const H2('추가 서지정보 (선택)'),
          Field(label: '출판사', value: _f['publisher']!, onChange: (t) => _set('publisher', t)),
          Field(label: '출간', value: _f['publishedAt']!, onChange: (t) => _set('publishedAt', t), placeholder: 'YYYY 또는 YYYY-MM'),
          Field(label: 'ISBN', value: _f['isbn']!, onChange: (t) => _set('isbn', t), number: true),
          Field(label: '쪽수', value: _f['pages']!, onChange: (t) => _set('pages', t), number: true, hint: '비우면 ‘미입력’으로 표시돼요.'),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Field(label: '판형 가로(mm)', value: _f['width']!, onChange: (t) => _set('width', t), number: true, error: _tried ? _sizeError('width') : null)),
            const SizedBox(width: Space.m),
            Expanded(child: Field(label: '판형 세로(mm)', value: _f['height']!, onChange: (t) => _set('height', t), number: true, error: _tried ? _sizeError('height') : null)),
          ]),
          WordText('크기를 바꾸면 책장에서 책 크기도 바뀌어요. 자리가 모자라면 그 선반 끝 책이 책장에서 빠질 수 있어요(내 책에는 그대로 있어요).', style: AppType.sub),
        ],
      ),
    );
  }
}
