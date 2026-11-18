// 갈피 남기기(지금 앱 app/bookmark/new.tsx, 2026-11-05 사용자 '찍고 나야지 문장을 쓰는 것 아닌가'): 책 → 사진 버튼 → 문장 → 쪽수 → 메모 순서.
// - 문장은 바로 적어도 되고, 사진을 찍거나 골라 간직할 부분을 자르면 기기 안 문장 인식이 바로 돌아 문장 칸을 채운다(사진은 밖으로 보내지 않는다).
//   읽은 글자는 사진과 비교해 고칠 수 있고, 인식하지 못한 부분을 지어내지 않는다.
// - 사진을 고른 뒤 '사진만 저장'을 켜면 글자 없이 종이·테이프 갈피 모양의 사진으로 저장한다. 끄면 원본 사진을 함께 보관할지 고른다.
// 저장에 실패하면 글·사진을 그대로 두고 다시 시도할 수 있다. 적은 것이 있으면 나가기 전에 묻는다(form_parts DraftGuard)
// 2026-11-16 QA 은서: 사진만 저장이면 숨은 인식 글을 저장하지 않는다(F2). 처음 방식은 사진 줄 모양으로 고르고(시면 줄바꿈 그대로, F6),
// 줄 끝 낱말 잇기를 고를 수 있다(F5). 사진의 쪽번호는 쪽수 칸이 비면 채운다. 고친 글은 방식을 바꿔도 지키고 다시 나누는 길을 알린다(F8).
// 비교하기 쉽게 사진은 잘라 내지 않고 다 보인다(F9). 저장할 때 첫 줄 들여쓰기를 지킨다(F10). 자르기 취소·빈 결과·책 없음은 이유를 보인다(F14·F15)
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/qa_probe.dart';
import '../../domain/ocr_text.dart';
import '../../services/photos.dart' show PhotoFail, PhotoOk, deniedMessage;
import '../../services/text_recognition.dart';
import '../../store/files.dart' show keepImage;
import '../../store/library_model.dart';
import '../../ui/alert.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import 'book_picker.dart' show pickBook;
import 'bookmark_detail_screen.dart' show BookmarkDetailScreen;
import 'form_parts.dart';
import 'mark_text.dart';
import 'page_photo.dart';
import 'photo_plate.dart';

/// 갈피 남기기 열기. book: 고른 책, session: 독서를 끝내고 저장한 기록에서 왔을 때 그 기록(갈피에 연결), photoOnly: '사진 갈피'로
Future<void> openNewBookmark(BuildContext context, {String? book, String? session, String? text, String? page, bool photoOnly = false, num? boardX, num? boardY}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/bookmark/new'),
      builder: (_) => NewBookmarkScreen(book: book, session: session, text: text, page: page, photoOnly: photoOnly, boardX: boardX, boardY: boardY),
    ));

class NewBookmarkScreen extends StatefulWidget {
  const NewBookmarkScreen({super.key, this.book, this.session, this.text, this.page, this.photoOnly = false, this.boardX, this.boardY});
  final String? book, session, text, page;
  final bool photoOnly;
  final num? boardX, boardY;

  @override
  State<NewBookmarkScreen> createState() => _NewBookmarkScreenState();
}

typedef _Photo = ({String uri, double? ratio});

class _NewBookmarkScreenState extends State<NewBookmarkScreen> {
  final _model = LibraryModel.instance;
  late String? _bookId = widget.book != null && _model.lib.books[widget.book] != null ? widget.book : null;
  late String _text = widget.text ?? '';
  late String _page = widget.page ?? '';
  String _memo = '';
  _Photo? _photo;
  late bool _photoOnly = widget.photoOnly;
  bool _keepPhoto = true; // 글자로 저장할 때 원본 사진도 함께 보관
  LineMode _lineMode = LineMode.join;
  WordJoin _words = WordJoin.auto;
  bool _modeChosen = false; // 사용자가 방식을 고르면 다음 사진도 그 방식으로(안 고르면 사진 줄 모양으로 짐작)

  /// 인식: 사진 주소와 상태(running · done · failed). empty: 글자를 못 찾음
  ({String uri, String state, OcrResult? result, bool empty})? _recog;

  /// 마지막으로 인식 결과로 채운 글. 칸 글이 이것과 다르면 사용자가 고친 것(방식을 바꿔도 덮어쓰지 않는다)
  String? _generated;
  bool _modeNote = false; // 고친 글이 있는데 방식을 바꿨다: '그대로 둬요·다시 나누기' 안내
  int? _photoPage; // 사진에서 찾아 쪽수 칸에 넣은 쪽번호
  String? _msg, _saveError;
  bool _saving = false;

  /// 문장 칸(인식 결과로 채울 때 바꾼다)
  int _textVersion = 0;

  bool get _asPhoto => _photo != null && _photoOnly;
  bool get _canSave => _bookId != null && !_saving && (_asPhoto || _text.trim().isNotEmpty);
  bool get _dirty => _text.trim().isNotEmpty || _memo.trim().isNotEmpty || _photo != null;
  bool get _edited => _generated == null ? _text.trim().isNotEmpty : _text != _generated;

  void _setText(String t) => setState(() {
        _text = t;
        _textVersion++;
      });

  Future<void> _runOcr(_Photo p) async {
    if (!textRecognitionAvailable) return;
    final started = DateTime.now();
    setState(() => _recog = (uri: p.uri, state: 'running', result: null, empty: false));
    try {
      final r = await recognizeText(p.uri.startsWith('file://') ? Uri.parse(p.uri).toFilePath() : p.uri);
      // '다시 읽기'가 눌린 게 보이게 읽는 중 표시를 잠깐은 둔다(QA F15: 같은 결과가 바로 떠 눌렸는지 몰랐다)
      final wait = const Duration(milliseconds: 700) - DateTime.now().difference(started);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (!mounted || _recog?.uri != p.uri) return;
      if (!_modeChosen) _lineMode = guessLineMode(r);
      final read = readOcr(r, _lineMode, words: _words);
      // 비어 있던 문장이나 고치지 않은 앞 인식 글만 채운다(직접 적거나 고친 글을 덮지 않는다)
      final fill = !_edited;
      setState(() {
        _recog = (uri: p.uri, state: 'done', result: r, empty: ocrText(r, LineMode.keep).isEmpty);
        _modeNote = false;
        // 쪽수 칸이 비었거나 앞 사진에서 넣은 그대로면 이 사진의 쪽번호로
        if (read.page != null && (_page.trim().isEmpty || _page.trim() == '$_photoPage')) {
          _page = '${read.page}';
          _photoPage = read.page;
        }
      });
      if (fill) _fill(read.text);
    } catch (e) {
      debugPrint('[ocr] 실패 $e');
      if (mounted && _recog?.uri == p.uri) setState(() => _recog = (uri: p.uri, state: 'failed', result: null, empty: false));
    }
  }

  void _fill(String t) {
    _generated = t;
    _setText(t);
  }

  Future<void> _fromPhoto(String from) async {
    // 간직할 부분 자르기·돌리기는 사진 고르기 단계의 자르기 화면에서
    final r = await pickPagePhoto(from);
    if (!mounted) return;
    switch (r) {
      case PhotoFail(:final reason, :final message):
        if (reason == 'denied') setState(() => _msg = deniedMessage(from));
        if (reason == 'error') setState(() => _msg = '사진을 가져오지 못했어요. ${message ?? ''}');
        if (reason == 'crop') setState(() => _msg = cropCanceledMessage);
      case PhotoOk(:final uri, :final width, :final height):
        final p = (uri: uri, ratio: width != null && height != null && height > 0 ? width / height : null);
        setState(() {
          _photo = p;
          _msg = null;
          _recog = null;
        });
        if (!_photoOnly) _runOcr(p);
    }
  }

  void _choosePhotoOnly(bool on) {
    setState(() => _photoOnly = on);
    // 글자로 저장으로 돌아오면 아직 읽지 않은 사진을 읽는다(같은 사진은 한 번만)
    final p = _photo;
    if (!on && p != null && _recog?.uri != p.uri) _runOcr(p);
  }

  void _changeLineMode(LineMode m) {
    setState(() {
      _lineMode = m;
      _modeChosen = true;
    });
    _reflow();
  }

  void _changeWords(WordJoin w) {
    setState(() => _words = w);
    _reflow();
  }

  // 방식이 바뀌면 고치지 않은 인식 글만 다시 나눈다. 고친 글은 그대로 두고 안내한다(QA F8)
  void _reflow() {
    final r = _recog;
    if (r?.state != 'done') return;
    if (_edited) {
      setState(() => _modeNote = true);
    } else {
      _fill(ocrText(r!.result!, _lineMode, words: _words));
    }
  }

  Future<void> _redo() => appAlert(context, '고친 글을 버리고 다시 나눌까요?', '사진에서 읽은 글을 고른 방식으로 다시 채워요. 고친 곳은 사라져요.', [
        const AlertButton('그대로 두기', style: AlertStyle.cancel),
        AlertButton('다시 나누기', style: AlertStyle.destructive, onPress: () {
          final r = _recog?.result;
          if (r == null) return;
          setState(() => _modeNote = false);
          _fill(ocrText(r, _lineMode, words: _words));
        }),
      ]);

  Future<void> _save() async {
    final bookId = _bookId;
    if (!_canSave || bookId == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final n = num.tryParse(_page.trim());
      final p = _photo;
      final photoUri = p != null && (_asPhoto || _keepPhoto) ? await keepImage(p.uri, 'page') : null;
      final s = widget.session;
      final session = s != null && _model.lib.sessions[s]?.myBookId == bookId ? s : null;
      final id = await _model.addBookmark(
        myBookId: bookId,
        // 사진만 저장이면 숨은 인식 글은 저장하지 않는다(QA F2). 글은 앞 빈 줄·끝 공백만 정리(F10)
        text: _asPhoto ? '' : tidyMarkText(_text),
        page: n != null && n > 0 ? n.round() : null,
        memo: _memo.trim().isEmpty ? null : _memo.trim(),
        photoUri: photoUri,
        photoRatio: photoUri != null ? p?.ratio : null,
        sessionId: session,
        // 갈피 보드의 '+ 갈피'에서 왔으면 그때 보던 곳의 빈 자리에 붙인다. 그 밖에는 자리를 비워 두면 보드가 자동으로 놓는다
        boardX: widget.boardX,
        boardY: widget.boardY,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(settings: const RouteSettings(name: '/bookmark'), builder: (_) => BookmarkDetailScreen(id: id)));
    } catch (e) {
      // 적은 글·사진은 이 화면에 그대로 있다
      if (mounted) {
        setState(() {
          _saveError = '저장하지 못했어요. 적은 내용과 사진은 그대로 있어요. 다시 시도해 주세요. ($e)';
          _saving = false;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) => qaProbe('newmark', _qaBuild(context));

  Widget _qaBuild(BuildContext context) {
    final lib = _model.lib;
    final b = _bookId == null ? null : lib.books[_bookId];
    final e = b == null ? null : lib.editions[b.editionId];
    final photo = _photo;
    // 공통 규칙: 쓰던 글 지킴은 갈피 수정·감상과 같은 부품(2026-11-19)
    return DraftGuard(
      dirty: () => _dirty,
      child: Screen(
        title: '갈피 남기기',
        // 책을 안 골라 저장이 꺼졌으면 이유를 보인다(QA F15)
        footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_bookId == null) Padding(padding: const EdgeInsets.only(bottom: Space.s), child: Text('책을 골라야 저장할 수 있어요', textAlign: TextAlign.center, style: AppType.sub)),
          Btn(label: '갈피 저장', size: 'l', onPress: _save, busy: _saving, disabled: !_canSave),
        ]),
        children: [
          const SizedBox(height: Space.m),
          SelectField(
            label: '책',
            value: e?.title,
            sub: e != null && e.authors.isNotEmpty ? e.authors.join(', ') : null,
            placeholder: '책을 골라 주세요',
            onPress: () async {
              final r = await pickBook(context, lib, addNew: true);
              if (r.picked && r.id != null && mounted) setState(() => _bookId = r.id);
            },
          ),
          if (photo == null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(padding: const EdgeInsets.only(bottom: Space.s), child: Text('사진을 찍으면 글자를 바로 읽어 아래에 채워요', style: AppType.sub)),
                Row(children: [
                  Expanded(child: Btn(label: '페이지 찍기', kind: 'secondary', size: 's', onPress: () => _fromPhoto('camera'))),
                  const SizedBox(width: Space.s),
                  Expanded(child: Btn(label: '사진 고르기', kind: 'secondary', size: 's', onPress: () => _fromPhoto('library'))),
                ]),
                if (_msg != null) NoticeText(_msg!, error: true),
              ]),
            )
          else
            _photoSection(context, photo),
          if (!_asPhoto)
            Field(
              key: ValueKey(('text', _textVersion)),
              label: '문장',
              value: _text,
              onChange: (t) {
                _text = t;
                setState(() {});
              },
              placeholder: '마음에 남은 문장을 옮겨 적어 주세요',
              multiline: true,
              minHeight: 160,
            ),
          if (photo != null && !_photoOnly) ListItem(label: '원본 사진도 보관', right: Toggle(label: '원본 사진도 보관', value: _keepPhoto, onChange: (v) => setState(() => _keepPhoto = v))),
          Field(
            label: '쪽수 (선택)',
            unit: '쪽',
            value: _page,
            onChange: (t) => setState(() => _page = t),
            number: true,
            hint: _photoPage != null && _page.trim() == '$_photoPage' ? '사진의 쪽번호를 넣었어요' : null,
          ),
          Field(label: '한 줄 메모 (선택)', value: _memo, onChange: (t) => setState(() => _memo = t), placeholder: '나만 보는 메모예요. 공유 이미지에는 넣지 않아요', multiline: true, minHeight: 80),
          if (_saveError != null) NoticeText(_saveError!, error: true),
        ],
      ),
    );
  }

  /// 사진을 넣은 뒤: 사진 · 칩 줄 · 사진만 저장 · 글자 읽기 결과(build가 길어 나눴다, 2026-11-19)
  Widget _photoSection(BuildContext context, _Photo photo) {
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // 자른 사진(눌러서 크게 보기). 사진만 저장이면 이 모양 그대로 저장된다. 글로 남길 때는 읽은 글과 견주게 잘라 내지 않고 다 보인다(QA F9)
        Center(child: PhotoPlate(uri: photo.uri, ratio: photo.ratio, width: math.min(_photoOnly ? 300 : 220, width - Space.page * 2), seed: 'new', whole: !_photoOnly)),
        PhotoChips(
          onCamera: () => _fromPhoto('camera'),
          onLibrary: () => _fromPhoto('library'),
          onRemove: () => setState(() {
            _photo = null;
            _recog = null;
            _modeNote = false;
          }),
        ),
        if (_msg != null) NoticeText(_msg!, error: true, center: true),
        ListItem(label: '사진만 저장', sub: '글자 없이 사진 그대로 남겨요', right: Toggle(label: '사진만 저장', value: _photoOnly, onChange: _choosePhotoOnly)),
        if (!_photoOnly) ..._recogParts(photo),
      ]),
    );
  }

  /// 글자 읽기: 읽는 중 · 실패(다시 읽기) · 빈 결과(사진만 저장) · 읽은 결과와 줄 나누기 방식
  List<Widget> _recogParts(_Photo photo) {
    final recog = _recog;
    final empty = recog?.state == 'done' && recog!.empty;
    final unsure = recog?.state == 'done' ? lowConfidenceLines(recog!.result!) : 0;
    return [
      if (!textRecognitionAvailable) const NoticeText(textRecognitionReason),
      if (recog?.state == 'running') const Loading(label: '사진 속 글자를 읽는 중이에요'),
      if (recog?.state == 'failed')
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const NoticeText('글자를 읽지 못했어요. 다시 읽거나, 직접 적거나, 사진만 저장할 수 있어요.', error: true),
            const SizedBox(height: Space.s),
            Btn(label: '다시 읽기', kind: 'secondary', size: 's', onPress: () => _runOcr(photo)),
          ]),
        ),
      // 빈 결과는 같은 사진을 다시 읽어도 같다: 다시 읽기 대신 사진만 저장(다시 찍기·다른 사진은 사진 아래 칩, QA F15)
      if (empty)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const NoticeText('사진에서 글자를 찾지 못했어요. 글자가 크고 반듯하게 보이도록 다시 찍거나, 아래에 직접 적거나, 사진만 저장할 수 있어요.', error: true),
            const SizedBox(height: Space.s),
            Btn(label: '사진만 저장하기', kind: 'secondary', size: 's', onPress: () => _choosePhotoOnly(true)),
          ]),
        ),
      if (recog?.state == 'done' && !empty)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('읽은 글자를 사진과 비교해 고쳐 주세요. 사진을 누르면 크게 볼 수 있어요.${unsure > 0 ? ' 흐릿하게 읽힌 줄이 $unsure개 있어요.' : ''}', style: AppType.sub),
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                AppChip(label: '줄 끝 이어 쓰기', on: _lineMode == LineMode.join, onPress: () => _changeLineMode(LineMode.join)),
                AppChip(label: '줄바꿈 그대로(시)', on: _lineMode == LineMode.keep, onPress: () => _changeLineMode(LineMode.keep)),
              ]),
            ),
            // 한글 줄 끝: 낱말 가운데서 끊긴 곳만 붙이기(알아서)·늘 붙이기·늘 띄우기(QA F5)
            if (_lineMode == LineMode.join)
              Padding(
                padding: const EdgeInsets.only(top: Space.s),
                child: Wrap(spacing: Space.s, runSpacing: Space.s, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('줄이 바뀐 곳', style: AppType.caption),
                  AppChip(label: '알아서 잇기', on: _words == WordJoin.auto, onPress: () => _changeWords(WordJoin.auto)),
                  AppChip(label: '붙여 잇기', on: _words == WordJoin.attach, onPress: () => _changeWords(WordJoin.attach)),
                  AppChip(label: '띄어 잇기', on: _words == WordJoin.space, onPress: () => _changeWords(WordJoin.space)),
                ]),
              ),
            if (_modeNote && _edited) ...[
              const NoticeText('고친 글은 그대로 둬요. 고른 방식으로 다시 나누려면 아래 \'다시 나누기\'를 눌러 주세요. 고친 곳은 사라져요.'),
              TextLink(label: '다시 나누기', onPress: _redo, start: true),
            ],
          ]),
        ),
    ];
  }
}
