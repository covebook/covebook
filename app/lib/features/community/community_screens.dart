// 커뮤니티 화면(지금 앱 app/(tabs)/community.tsx·community/compose·share·post·profile·user): 서버의 공개 데이터 API만 쓴다(개인 서재 동기화와 따로).
// 공개되는 것은 사용자가 고른 필드뿐이고, 비어 있으면 비어 있다고 그대로 보여 준다(가짜 사용자·게시물로 채우지 않는다)
library;

import 'package:flutter/material.dart';

import '../../domain/community_draft.dart';
import '../../domain/library.dart' show formatDurationPrecise;
import '../../domain/reading.dart' show newId;
import '../../services/community.dart';
import '../../store/library_model.dart';
import '../../ui/alert.dart';
import '../../ui/draft_guard.dart';
import '../../ui/feedback.dart';
import '../../ui/kit.dart';
import '../../ui/theme.dart';
import '../book/add_book_screen.dart' show openAddBook;
import '../book/labels.dart' show dateShort;
import 'book_reviews.dart' show reviewStarSize;
import '../settings/backup_screen.dart' show openBackup;
import '../stats/session_edit_screen.dart' show openSessionEdit;
import 'community_widgets.dart';

Future<T?> _push<T>(BuildContext context, String name, Widget page) =>
    Navigator.of(context, rootNavigator: true).push<T>(MaterialPageRoute<T>(settings: RouteSettings(name: name), builder: (_) => page));

Future<void> openCommunityCompose(BuildContext context) => _push(context, '/community/compose', const ComposeScreen());
Future<void> openCommunityShare(BuildContext context, String sessionId) => _push(context, '/community/share', ShareDraftScreen(sessionId: sessionId));
Future<void> openCommunityPost(BuildContext context, int id) => _push(context, '/community/post', PostScreen(id: id));
Future<void> openCommunityProfile(BuildContext context) => _push(context, '/community/profile', const MyProfileScreen());
Future<void> openCommunityUser(BuildContext context, int id) => _push(context, '/community/user', UserScreen(id: id));

const _divider = AppDivider();

// ---------- 커뮤니티 탭: 발견(모든 공개 게시물)·팔로잉(팔로우한 사람) 피드 ----------

class CommunityTab extends StatefulWidget {
  const CommunityTab({super.key});

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  Availability? _avail;
  String _scope = 'discover';
  List<Post> _items = const [];
  int? _next;
  String _phase = 'loading'; // loading · ready · error
  String _error = '';
  String _more = 'idle'; // idle · loading · error
  int _req = 0; // 범위를 바꾸거나 새로 고치면 늦게 온 이전 응답은 버린다

  @override
  void initState() {
    super.initState();
    communityAvailability().then(_setAvail);
  }

  void _setAvail(Availability a) {
    if (!mounted) return;
    setState(() => _avail = a);
    if (a.ok) _load('first');
  }

  // first·refresh는 첫 쪽으로 바꾸고, focus(다른 화면에서 돌아옴)는 첫 쪽만 새것으로 바꾸고 이미 받은 더 오래된 글은 지킨다
  Future<void> _load(String mode) async {
    final id = ++_req;
    try {
      final f = await Community.feed(_scope);
      if (id != _req || !mounted) return;
      final fresh = {for (final p in f.items) p.id};
      final oldest = f.items.isEmpty ? 0 : f.items.last.id;
      final older = mode == 'focus' && f.nextBefore != null ? [for (final p in _items) if (!fresh.contains(p.id) && p.id < oldest) p] : <Post>[];
      setState(() {
        _items = [...f.items, ...older];
        if (older.isEmpty) _next = f.nextBefore;
        _more = 'idle';
        _phase = 'ready';
      });
    } catch (e) {
      if (id != _req || !mounted) return;
      if (mode == 'first') {
        setState(() {
          _error = communityError(e);
          _phase = 'error';
        });
      } else {
        explainWriteError(context, e, '새로 고치지 못했어요');
      }
    }
  }

  Future<void> _loadMore() async {
    if (_next == null || _more == 'loading' || _phase != 'ready') return;
    final id = _req;
    setState(() => _more = 'loading');
    try {
      final f = await Community.feed(_scope, _next);
      if (id != _req || !mounted) return;
      setState(() {
        _items = mergePosts(_items, f.items);
        _next = f.nextBefore;
        _more = 'idle';
      });
    } catch (_) {
      if (id == _req && mounted) setState(() => _more = 'error');
    }
  }

  Future<void> _toggleLike(Post p) async {
    Post flip(Post x) => x.id == p.id ? x.copyWith(liked: !p.liked, likes: x.likes + (p.liked ? -1 : 1)) : x;
    setState(() => _items = _items.map(flip).toList());
    try {
      final fresh = await Community.like(p.id, !p.liked);
      if (mounted) setState(() => _items = [for (final x in _items) x.id == p.id ? fresh : x]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _items = [for (final x in _items) x.id == p.id ? p : x]);
      explainWriteError(context, e, '좋아요를 반영하지 못했어요');
    }
  }

  void _setScope(String s) {
    if (s == _scope) return;
    setState(() {
      _items = const [];
      _next = null;
      _phase = 'loading';
      _scope = s;
    });
    _load('first');
  }

  // 다른 화면(글쓰기·상세)에서 돌아오면 첫 쪽을 조용히 다시 받는다
  Future<void> _go(Future<void> Function() open) async {
    await open();
    if (mounted && _avail?.ok == true) _load('focus');
  }

  @override
  Widget build(BuildContext context) {
    final a = _avail;
    // 머리줄 오른쪽: 기록 공유하기(글쓰기) · 내 공개 프로필. 머리줄 아이콘은 공용 HeadIcon, 나란히는 IconRow(가운데 사이 40, docs/design/DESIGN.md 6장)
    final right = IconRow(children: [
      IconBtn(label: '독서 기록 공유하기', onPress: () => _go(() => openCommunityCompose(context)), child: const HeadIcon('PenLine')),
      IconBtn(label: '내 공개 프로필', onPress: () => _go(() => openCommunityProfile(context)), child: const HeadIcon('UserRound')),
    ]);
    if (a == null) return const Screen(title: '커뮤니티', back: false, scroll: false, children: [Loading()]);
    if (!a.ok) {
      return Screen(title: '커뮤니티', back: false, scroll: false, children: [
        Unavailable(a: a, onRetry: () {
          setState(() => _avail = null);
          communityAvailability(force: true).then(_setAvail);
        }),
      ]);
    }
    final bottom = TabBarStyle.contentPad;
    Widget body;
    if (_phase == 'loading') {
      body = const Loading();
    } else if (_phase == 'error') {
      body = Empty(title: '피드를 불러오지 못했어요', body: _error, action: '다시 시도', actionKind: 'secondary', onAction: () {
        setState(() => _phase = 'loading');
        _load('first');
      });
    } else {
      body = Bleed(
          child: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => _load('refresh'),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < n.metrics.viewportDimension * 0.4) _loadMore();
            return false;
          },
          child: _items.isEmpty
              ? ListView(padding: EdgeInsets.only(bottom: bottom), children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.page),
                    child: _scope == 'following'
                        ? Empty(title: '팔로우한 사람의 기록이 없어요', action: '발견 보기', actionKind: 'secondary', onAction: () => _setScope('discover'))
                        : Empty(title: '아직 올라온 독서 기록이 없어요', action: '기록 공유하기', actionKind: 'secondary', onAction: () => _go(() => openCommunityCompose(context))),
                  ),
                ])
              : ListView.separated(
                  padding: EdgeInsets.only(bottom: bottom),
                  itemCount: _items.length + 1,
                  separatorBuilder: (_, i) => i < _items.length - 1 ? _divider : const SizedBox.shrink(),
                  itemBuilder: (_, i) {
                    // 목록 끝 더 받기: 작은 원, 실패는 구역 빈 줄 + '다시 시도'(docs/design/DESIGN.md 11장)
                    if (i == _items.length) {
                      if (_more == 'loading') return const Padding(padding: EdgeInsets.symmetric(vertical: Space.group), child: Center(child: Spinner(label: '더 불러오는 중')));
                      if (_more == 'error') {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.item),
                          child: EmptyLine('더 불러오지 못했어요', action: '다시 시도', onAction: _loadMore),
                        );
                      }
                      return const SizedBox.shrink();
                    }
                    final p = _items[i];
                    return PostCard(
                      post: p,
                      onOpen: () => _go(() => openCommunityPost(context, p.id)),
                      onAuthor: () => _go(() => openCommunityUser(context, p.userId)),
                      onLike: () => _toggleLike(p),
                    );
                  },
                ),
        ),
      ));
    }
    return Screen(title: '커뮤니티', back: false, scroll: false, right: right, children: [
      // 화면 끝까지 반반 나눈 탭, 글은 상자 없이 화면 폭 그대로 + 사이 얇은 선
      Bleed(child: Tabs<String>(fill: true, items: const [(id: 'discover', label: '발견'), (id: 'following', label: '팔로잉')], value: _scope, onChange: _setScope)),
      Expanded(child: body),
    ]);
  }
}

// ---------- 글쓰기: 내 독서 기록 가운데 공유할 것을 고른다 ----------

class ComposeScreen extends StatelessWidget {
  const ComposeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = LibraryModel.instance.lib;
    final rows = ([for (final s in lib.sessions.values) if (s.myBookId != null && lib.books.containsKey(s.myBookId)) s]..sort((a, b) => b.startedAt.compareTo(a.startedAt))).take(50).toList();

    return Screen(
      title: '기록 공유하기',
      subtitle: '공유할 독서 기록을 골라 주세요. 다음 화면에서 공개할 것만 고를 수 있어요.',
      children: [
        if (rows.isEmpty)
          const Empty(title: '공유할 독서 기록이 없어요', body: '책을 골라 읽고 기록을 저장하면 여기서 공유할 수 있어요.')
        else
          for (final (i, s) in rows.indexed) ...[
            if (i > 0) _divider,
            () {
              final ed = lib.editions[lib.books[s.myBookId]!.editionId];
              final pages = sessionPages(s.startPage, s.pagesRead);
              // 날짜는 앱 목록 날짜(dateShort), 사이는 옅은 세로줄 · 화면 읽기는 쉼표(2026-11-19 공통 규칙)
              final parts = [dateShort(s.startedAt), formatDurationPrecise(s.durationMs), if (pages != null) '$pages쪽'];
              final meta = parts.join(metaSep);
              return Semantics(
                button: true,
                label: '${ed?.title ?? '책'}, ${parts.join(', ')}',
                excludeSemantics: true,
                child: Pressable(
                  onPress: () => openCommunityShare(context, s.id),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(ed?.title ?? '제목 없음', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bookTitle),
                            Padding(padding: const EdgeInsets.only(top: 2), child: MetaText(meta, style: AppType.caption)),
                          ]),
                        ),
                        const Chevron(),
                      ]),
                    ),
                  ),
                ),
              );
            }(),
          ],
      ],
    );
  }
}

// ---------- 공유 초안: 저장한 독서 기록에서 공개할 것만 고른다 → 미리보기 → 게시 ----------

class ShareDraftScreen extends StatefulWidget {
  const ShareDraftScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<ShareDraftScreen> createState() => _ShareDraftScreenState();
}

class _ShareDraftScreenState extends State<ShareDraftScreen> {
  Availability? _avail;
  ShareChoice? _choice;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    communityAvailability().then((a) {
      if (mounted) setState(() => _avail = a);
    });
  }

  Future<void> _post(Map<String, Object?> payload) async {
    setState(() => _posting = true);
    final nav = Navigator.of(context);
    try {
      final p = await Community.createPost(payload);
      if (!mounted) return;
      nav.pushReplacement(MaterialPageRoute<void>(settings: const RouteSettings(name: '/community/post'), builder: (_) => PostScreen(id: p.id)));
      return;
    } catch (e) {
      if (mounted) explainWriteError(context, e, '게시하지 못했어요');
    }
    if (mounted) setState(() => _posting = false);
  }

  @override
  Widget build(BuildContext context) {
    const title = '커뮤니티에 공유';
    final a = _avail;
    if (a == null) return const Screen(title: title, children: [Loading()]);
    if (!a.ok) {
      return Screen(title: title, children: [
        Unavailable(a: a, onRetry: () {
          setState(() => _avail = null);
          communityAvailability(force: true).then((v) {
            if (mounted) setState(() => _avail = v);
          });
        }),
      ]);
    }
    final src = shareSourceOf(LibraryModel.instance.lib, widget.sessionId);
    if (src == null) {
      return Screen(title: title, children: [
        Empty(title: '기록을 찾을 수 없어요', action: '돌아가기', actionKind: 'secondary', onAction: () => Navigator.of(context).maybePop()),
      ]);
    }
    final choice = _choice ?? defaultChoice(src);
    final payload = sharePayload(src, choice);
    if (payload == null) {
      return Screen(title: title, children: [
        Empty(title: '책과 연결된 기록만 공유할 수 있어요', action: '기록 수정', actionKind: 'secondary', onAction: () => openSessionEdit(context, src.session.id)),
      ]);
    }
    void set({bool? duration, bool? pages, Object? quoteId = _keep, String? body}) => setState(() => _choice = (
          duration: duration ?? choice.duration,
          pages: pages ?? choice.pages,
          quoteId: identical(quoteId, _keep) ? choice.quoteId : quoteId as String?,
          body: body ?? choice.body,
        ));
    final preview = Post.of({
      'id': 0,
      'userId': 0,
      'nickname': '나',
      'likes': 0,
      'liked': false,
      'comments': 0,
      'mine': true,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      ...payload,
    });
    // 쓰던 글 · 고른 것이 있으면 나갈 때 묻는다(공용 DraftGuard, 2026-11-19 공통 규칙: 말없이 버려졌다). 게시하면 게시물 화면으로 바꿔 넣는다(묻지 않음)
    return DraftGuard(
      dirty: () => !_posting && _choice != null && _choice != defaultChoice(src),
      child: Screen(
        title: title,
        footer: Btn(
          label: '게시하기',
          size: 'xlarge',
          busy: _posting,
          onPress: () => appAlert(context, '이 내용으로 게시할까요?', '다른 독자가 볼 수 있어요. 게시물은 언제든 삭제할 수 있고, 삭제해도 내 책 기록은 그대로예요.', [
            const AlertButton('취소', style: AlertStyle.cancel),
            AlertButton('게시', onPress: () => _post(payload)),
          ]),
        ),
        children: [
          Padding(padding: const EdgeInsets.only(top: Space.tight), child: WordText('공개할 것만 골라 주세요. 메모와 날짜는 공유되지 않아요.', style: AppType.sub)),
          // 구역 제목은 공용 H2(화면 읽기 머리, 2026-11-19 공통 규칙: 머리가 아닌 글자였다)
          const H2('책'),
          Text(payload['bookTitle']! as String, style: AppType.bookTitle),
          if (payload['bookAuthor'] case final String author) Text(author, style: AppType.bookAuthor),
          Padding(
            padding: const EdgeInsets.only(top: Space.item),
            child: ListGroup(children: [
              ListItem(label: '읽은 시간', sub: formatDurationPrecise(src.durationMs), right: Toggle(label: '읽은 시간 공개', value: choice.duration, onChange: (v) => set(duration: v))),
              if (src.pagesRead != null) ListItem(label: '읽은 분량', sub: '${src.pagesRead}쪽', right: Toggle(label: '읽은 분량 공개', value: choice.pages, onChange: (v) => set(pages: v))),
            ]),
          ),
          if (src.quotes.isNotEmpty) ...[
            const H2('함께 올릴 갈피 문장 (선택)'),
            Choice(label: '문장 없이', selected: choice.quoteId == null, compact: true, onPress: () => set(quoteId: null)),
            for (final q in src.quotes.take(6))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Choice(
                  label: q.text.length > 80 ? '${q.text.substring(0, 80)}…' : q.text,
                  sub: [if (q.page != null) '${q.page}쪽', if (q.sessionId == src.session.id) '이번 독서에서 남긴 갈피'].join(metaSep).ifEmptyNull,
                  selected: choice.quoteId == q.id,
                  onPress: () => set(quoteId: q.id),
                ),
              ),
          ],
          Field(label: '한 줄 남기기 (선택)', value: choice.body, multiline: true, placeholder: '공개로 보이는 글이에요', onChange: (v) => set(body: v.length > 1000 ? v.substring(0, 1000) : v)),
          const H2('미리보기'),
          Bleed(child: PostCard(post: preview, full: true)),
        ],
      ),
    );
  }
}

const _keep = Object();

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}

// ---------- 게시물 상세: 게시물 · 좋아요 · 댓글 · 더보기(내 글: 삭제 / 남의 글: 신고·글쓴이 차단) ----------

class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.id});
  final int id;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  Post? _post;
  List<Comment> _comments = const [];
  String _phase = 'loading'; // loading · ready · error · gone
  String _error = '';
  final _text = TextEditingController();
  bool _sending = false;
  String _clientId = newId('cm'); // 같은 댓글을 두 번 보내도(재시도) 하나만

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([Community.post(widget.id), Community.comments(widget.id)]);
      if (!mounted) return;
      setState(() {
        _post = r[0] as Post;
        _comments = r[1] as List<Comment>;
        _phase = 'ready';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isNotFound(e)) {
          _phase = 'gone';
        } else {
          _error = communityError(e);
          _phase = 'error';
        }
      });
    }
  }

  Future<void> _like() async {
    final before = _post;
    if (before == null) return;
    setState(() => _post = before.copyWith(liked: !before.liked, likes: before.likes + (before.liked ? -1 : 1)));
    try {
      final p = await Community.like(before.id, !before.liked);
      if (mounted) setState(() => _post = p);
    } catch (e) {
      if (!mounted) return;
      setState(() => _post = before);
      explainWriteError(context, e, '좋아요를 반영하지 못했어요');
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final items = await Community.addComment(widget.id, body, _clientId);
      if (!mounted) return;
      setState(() {
        _comments = items;
        _text.clear();
        _clientId = newId('cm');
        _post = _post?.copyWith(comments: items.length);
      });
    } catch (e) {
      if (mounted) explainWriteError(context, e, '댓글을 남기지 못했어요');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // 댓글 메뉴: 내 댓글은 삭제 확인창, 남의 댓글은 게시물 더보기와 같은 메뉴 시트(2026-11-19 공통 규칙: 확인창을 메뉴로 썼다)
  void _commentMenu(Comment c) {
    if (c.mine) {
      appAlert(context, '댓글을 삭제할까요?', null, [
        const AlertButton('취소', style: AlertStyle.cancel),
        AlertButton('삭제', style: AlertStyle.destructive, onPress: () {
          Community.deleteComment(c.id).then((_) {
            if (!mounted) return;
            setState(() {
              _comments = [for (final x in _comments) if (x.id != c.id) x];
              final p = _post;
              if (p != null) _post = p.copyWith(comments: (p.comments - 1).clamp(0, 1 << 30));
            });
          }, onError: (Object e) {
            if (mounted) explainWriteError(context, e, '댓글을 삭제하지 못했어요');
          });
        }),
      ]);
    } else {
      showSheet<void>(
        context,
        builder: (ctx) => ListGroup(children: [
          ListItem(label: '댓글 신고', onPress: () {
            Navigator.pop(ctx);
            Future<void>.delayed(const Duration(milliseconds: 350), () {
              if (mounted) showReportSheet(context, kind: 'comment', id: c.id, label: '댓글');
            });
          }),
        ]),
      );
    }
  }

  void _menu() {
    final p = _post!;
    final nav = Navigator.of(context);
    showSheet<void>(
      context,
      builder: (ctx) => ListGroup(children: [
        // 보고 있던 게시물을 삭제 · 차단하면 화면을 닫고 토스트(docs/design/DESIGN.md 10장)
        if (p.mine)
          ListItem(
            label: '게시물 삭제',
            danger: true,
            onPress: () {
              Navigator.pop(ctx);
              appAlert(context, '게시물을 삭제할까요?', '커뮤니티에서만 삭제돼요. 내 책의 독서 기록은 그대로예요.', [
                const AlertButton('취소', style: AlertStyle.cancel),
                AlertButton('삭제', style: AlertStyle.destructive, onPress: () {
                  Community.deletePost(p.id).then((_) {
                    if (mounted) showToast(context, '게시물을 삭제했어요.');
                    nav.maybePop();
                  }, onError: (Object e) {
                    if (mounted) explainWriteError(context, e, '게시물을 삭제하지 못했어요');
                  });
                }),
              ]);
            },
          ),
        if (!p.mine) ...[
          ListItem(label: '게시물 신고', onPress: () {
            Navigator.pop(ctx);
            Future<void>.delayed(const Duration(milliseconds: 350), () {
              if (mounted) showReportSheet(context, kind: 'post', id: p.id, label: '게시물');
            });
          }),
          ListItem(
            label: '${p.nickname}님 차단',
            danger: true,
            onPress: () {
              Navigator.pop(ctx);
              appAlert(context, '${p.nickname}님을 차단할까요?', '서로의 게시물, 댓글, 후기가 보이지 않고 팔로우도 끊겨요. 내 공개 프로필의 차단 목록에서 풀 수 있어요.', [
                const AlertButton('취소', style: AlertStyle.cancel),
                AlertButton('차단', style: AlertStyle.destructive, onPress: () {
                  Community.block(p.userId, true).then((_) {
                    if (mounted) showToast(context, '${p.nickname}님을 차단했어요.');
                    nav.maybePop();
                  }, onError: (Object e) {
                    if (mounted) explainWriteError(context, e, '차단하지 못했어요');
                  });
                }),
              ]);
            },
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    const title = '독서 기록';
    if (_phase == 'loading') return const Screen(title: title, children: [Loading()]);
    if (_phase == 'gone') return const Screen(title: title, children: [Empty(title: '볼 수 없는 게시물이에요')]);
    final p = _post;
    if (_phase == 'error' || p == null) {
      return Screen(title: title, children: [
        Empty(title: '게시물을 불러오지 못했어요', body: _error, action: '다시 시도', actionKind: 'secondary', onAction: () {
          setState(() => _phase = 'loading');
          _load();
        }),
      ]);
    }
    return Screen(
      title: title,
      footer: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 40, maxHeight: 120),
            decoration: BoxDecoration(color: AppColors.input, borderRadius: BorderRadius.circular(10)),
            child: Semantics(
              label: '댓글',
              textField: true,
              child: TextField(
                controller: _text,
                maxLength: 500,
                maxLines: null,
                onChanged: (_) => setState(() {}),
                style: AppType.input,
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  hintText: '댓글 남기기',
                  hintStyle: AppType.input.copyWith(color: AppColors.inkFaint),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Btn(label: '올리기', size: 'medium', disabled: _text.text.trim().isEmpty, busy: _sending, onPress: _send),
      ]),
      children: [
        Bleed(child: PostCard(post: p, full: true, onAuthor: () => openCommunityUser(context, p.userId), onLike: _like, onMore: _menu)),
        // 다른 사람의 책을 내 서재에: 기존 새 책 추가(검색·같은 ISBN 확인)를 그대로 쓴다
        if (!p.mine)
          Transform.translate(
            offset: const Offset(0, -8),
            child: Padding(
              padding: const EdgeInsets.only(left: 56, bottom: Space.tight),
              child: TextLink(label: '이 책 내 책에 추가', start: true, onPress: () => openAddBook(context, q: p.isbn13 ?? p.bookTitle)),
            ),
          ),
        const Bleed(child: _divider),
        // 구역 머리는 공용 SectionHead(제목 옆 개수), 빈 구역은 EmptyLine(2026-11-19 공통 규칙)
        Padding(padding: const EdgeInsets.only(top: Space.group, bottom: Space.tight), child: SectionHead(title: '댓글', count: _comments.isEmpty ? null : '${_comments.length}개')),
        if (_comments.isEmpty)
          const Padding(padding: EdgeInsets.only(bottom: Space.item), child: EmptyLine('첫 댓글을 남겨 보세요'))
        else
          for (final c in _comments)
            GestureDetector(
              onLongPress: () => _commentMenu(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  GestureDetector(onTap: () => openCommunityUser(context, c.userId), child: Avatar(name: c.nickname, id: c.userId, size: 32)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // 이름·시간은 왼쪽(이름만 줄어든다), 더보기는 줄 끝. Flexible과 Spacer를 한 줄에 두면 남는 폭을 반씩 나눠 끝까지 못 간다
                      Row(children: [
                        const SizedBox(height: 22),
                        Expanded(
                          child: Row(children: [
                            Flexible(
                              child: GestureDetector(
                                onTap: () => openCommunityUser(context, c.userId),
                                child: Text(c.nickname, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.labelStrong),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(ago(c.createdAt), style: AppType.caption),
                          ]),
                        ),
                        MoreDots(label: '${c.nickname}님의 댓글 더보기', onPress: () => _commentMenu(c)),
                      ]),
                      Padding(padding: const EdgeInsets.only(top: 2), child: WordText(c.body, style: AppType.body)),
                    ]),
                  ),
                ]),
              ),
            ),
      ],
    );
  }
}

// ---------- 내 공개 프로필: 공개 닉네임·소개, 내 공개 페이지 보기, 차단 목록 ----------

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  Availability? _avail;
  MyProfile? _me;
  String _error = '';
  String _nick = '', _bio = '';
  bool _saving = false;
  List<({int userId, String nickname})>? _blocked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final a = await communityAvailability(force: force);
    if (!mounted) return;
    setState(() => _avail = a);
    if (!a.ok) return;
    try {
      final m = await Community.myProfile();
      final b = await Community.blocks();
      if (!mounted) return;
      setState(() {
        _me = m;
        _nick = m.profile?.nickname ?? '';
        _bio = m.profile?.bio ?? '';
        _blocked = b;
      });
    } catch (e) {
      if (mounted) setState(() => _error = communityError(e));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final m = await Community.saveProfile(_nick.trim(), _bio.trim().isEmpty ? null : _bio.trim());
      if (!mounted) return;
      setState(() {
        _me = m;
        _nick = m.profile?.nickname ?? '';
        _bio = m.profile?.bio ?? '';
      });
      // 성공은 토스트(docs/design/DESIGN.md 14장: 확인창이었다)
      showToast(context, '공개 프로필을 저장했어요.');
    } catch (e) {
      if (mounted) explainWriteError(context, e, '공개 프로필을 저장하지 못했어요');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _unblock(({int userId, String nickname}) b) => appAlert(context, '${b.nickname.isEmpty ? '이 사용자' : b.nickname}님 차단을 풀까요?', '서로의 공개 게시물, 댓글, 후기가 다시 보여요. 팔로우는 다시 해야 해요.', [
        const AlertButton('취소', style: AlertStyle.cancel),
        AlertButton('차단 풀기', onPress: () {
          Community.block(b.userId, false).then((_) {
            if (mounted) setState(() => _blocked = [for (final x in _blocked ?? const <({int userId, String nickname})>[]) if (x.userId != b.userId) x]);
          }, onError: (Object e) {
            if (mounted) explainWriteError(context, e, '차단을 풀지 못했어요');
          });
        }),
      ]);

  // 구역 제목 H2, 구역 안 불러오는 중은 작은 원, 없음은 EmptyLine, 줄 안 되돌리는 행동은 숨긴 책 '다시 보이기'와 같은 작은 보조 단추(2026-11-19 공통 규칙: 값 자리에 행동 이름이었다)
  List<Widget> _blockList() => [
        const H2('차단한 사용자'),
        if (_blocked == null)
          const Align(alignment: Alignment.centerLeft, child: Spinner(label: '불러오는 중'))
        else if (_blocked!.isEmpty)
          const EmptyLine('차단한 사용자가 없어요')
        else
          ListGroup(children: [
            for (final b in _blocked!)
              ListItem(label: b.nickname.isEmpty ? '닉네임 없는 사용자' : b.nickname, right: Btn(label: '차단 풀기', kind: 'secondary', size: 'medium', onPress: () => _unblock(b))),
          ]),
      ];

  @override
  Widget build(BuildContext context) {
    const title = '공개 프로필';
    final a = _avail;
    if (a == null) return const Screen(title: title, children: [Loading()]);
    if (!a.ok) {
      return Screen(title: title, children: [
        Unavailable(a: a, onRetry: () {
          setState(() => _avail = null);
          _load(force: true);
        }),
      ]);
    }
    if (_error.isNotEmpty) {
      return Screen(title: title, children: [
        Empty(title: '공개 프로필을 불러오지 못했어요', body: _error, action: '다시 시도', actionKind: 'secondary', onAction: () {
          setState(() {
            _error = '';
            _me = null;
          });
          _load();
        }),
      ]);
    }
    final me = _me;
    if (me == null) return const Screen(title: title, children: [Loading()]);
    if (!me.socialLinked) {
      return Screen(title: title, children: [
        Empty(
          title: '계정을 연결하면 공개 활동을 할 수 있어요',
          action: '계정 연결하러 가기',
          onAction: () => openBackup(context),
        ),
        if (_blocked?.isNotEmpty ?? false) ..._blockList(),
      ]);
    }
    final n = _nick.trim();
    final nickError = n.isNotEmpty && (n.length < 2 || n.length > 20) ? '닉네임은 2~20자로 정해 주세요' : null;
    final changed = _changed;
    // 고친 닉네임 · 소개가 있으면 나갈 때 묻는다(공용 DraftGuard: 처음 만들기는 새로 쓰기, 있으면 고치기. 2026-11-19 공통 규칙: 말없이 버려졌다)
    final screen = Screen(
      title: title,
      // 저장 단추 이름은 '○○ 저장'(docs/design/DESIGN.md 5장)
      footer: Btn(label: me.profile != null ? '공개 프로필 저장' : '공개 프로필 만들기', size: 'xlarge', disabled: !changed || n.isEmpty || nickError != null, busy: _saving, onPress: _save),
      children: [
        Padding(padding: const EdgeInsets.only(bottom: Space.group), child: WordText('공개 닉네임은 게시물, 후기, 댓글에 보여요. 로그인한 계정 이름이나 내 책 기록은 공개되지 않아요.', style: AppType.sub)),
        Field(label: '공개 닉네임', value: _nick, placeholder: '2~20자', error: nickError, onChange: (v) => setState(() => _nick = v.length > 20 ? v.substring(0, 20) : v)),
        Field(label: '소개 (선택)', value: _bio, multiline: true, placeholder: '어떤 책을 즐겨 읽는지 한두 줄로', onChange: (v) => setState(() => _bio = v.length > 200 ? v.substring(0, 200) : v)),
        if (me.profile case final pr?) ...[
          const H2('내 공개 활동'),
          ListGroup(children: [
            ListItem(label: '내 공개 페이지 보기', sub: ['게시물 ${pr.posts}', '팔로워 ${pr.followers}', '팔로잉 ${pr.following}'].join(metaSep), chevron: true, onPress: () => openCommunityUser(context, pr.userId)),
          ]),
        ],
        ..._blockList(),
      ],
    );
    return me.profile != null ? DraftGuard.edit(dirty: () => !_saving && _changed, child: screen) : DraftGuard(dirty: () => !_saving && _changed, child: screen);
  }

  /// 닉네임 · 소개를 저장된 값과 다르게 고쳤는지
  bool get _changed {
    final p = _me?.profile;
    return _me != null && (_nick.trim() != (p?.nickname ?? '') || _bio.trim() != (p?.bio ?? ''));
  }
}

// ---------- 다른 독자의 공개 프로필: 팔로우, 공개 게시물·평가. 더보기: 신고·차단 ----------

class UserScreen extends StatefulWidget {
  const UserScreen({super.key, required this.id});
  final int id;

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  UserPage? _page;
  String _phase = 'loading';
  String _error = '';
  bool _busy = false;
  String _tab = 'posts';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pg = await Community.user(widget.id);
      if (mounted) {
        setState(() {
          _page = pg;
          _phase = 'ready';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isNotFound(e)) {
          _phase = 'gone';
        } else {
          _error = communityError(e);
          _phase = 'error';
        }
      });
    }
  }

  Future<void> _follow() async {
    final pg = _page;
    if (pg == null) return;
    setState(() => _busy = true);
    try {
      await Community.follow(widget.id, !pg.followed);
      await _load(); // 팔로워 수까지 서버 값으로
    } catch (e) {
      if (mounted) explainWriteError(context, e, '팔로우를 바꾸지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _menu(PublicProfile p) {
    final nav = Navigator.of(context);
    showSheet<void>(
      context,
      builder: (ctx) => ListGroup(children: [
        ListItem(label: '사용자 신고', onPress: () {
          Navigator.pop(ctx);
          Future<void>.delayed(const Duration(milliseconds: 350), () {
            if (mounted) showReportSheet(context, kind: 'user', id: widget.id, label: '사용자');
          });
        }),
        ListItem(
          label: '${p.nickname}님 차단',
          danger: true,
          onPress: () {
            Navigator.pop(ctx);
            appAlert(context, '${p.nickname}님을 차단할까요?', '서로의 게시물, 댓글, 후기가 보이지 않고 팔로우도 끊겨요. 내 공개 프로필의 차단 목록에서 풀 수 있어요.', [
              const AlertButton('취소', style: AlertStyle.cancel),
              AlertButton('차단', style: AlertStyle.destructive, onPress: () {
                Community.block(widget.id, true).then((_) {
                  if (mounted) showToast(context, '${p.nickname}님을 차단했어요.');
                  nav.maybePop();
                }, onError: (Object e) {
                  if (mounted) explainWriteError(context, e, '차단하지 못했어요');
                });
              }),
            ]);
          },
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == 'loading') return const Screen(title: '독자', children: [Loading()]);
    if (_phase == 'gone') return const Screen(title: '독자', children: [Empty(title: '볼 수 없는 프로필이에요')]);
    final pg = _page;
    if (_phase == 'error' || pg == null) {
      return Screen(title: '독자', children: [
        Empty(title: '프로필을 불러오지 못했어요', body: _error, action: '다시 시도', actionKind: 'secondary', onAction: () {
          setState(() => _phase = 'loading');
          _load();
        }),
      ]);
    }
    final p = pg.profile;
    // 위 줄 제목은 늘 '독자'(다 받으면 빈칸으로 바뀌었다), 머리줄 아이콘은 공용 HeadIcon(2026-11-19 공통 규칙)
    return Screen(
      title: '독자',
      right: pg.me ? null : IconBtn(label: '더 보기', onPress: () => _menu(p), child: const HeadIcon('MoreHorizontal')),
      children: [
        // 스레드처럼: 이름 크게 + 오른쪽 프로필 동그라미, 소개, '팔로워 N · 팔로잉 N' 한 줄, 팔로우 단추, '독서 기록 | 평가' 탭
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // 사람 이름은 profileName 역할(탭 첫 화면 제목 title을 빌려 썼다), 정보 사이는 옅은 세로줄 MetaText
                Semantics(header: true, child: Text(p.nickname, maxLines: 2, style: AppType.profileName)),
                if (p.bio != null && p.bio!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: Space.tight), child: WordText(p.bio!, style: AppType.body)),
                Padding(padding: const EdgeInsets.only(top: Space.s), child: MetaText(['팔로워 ${p.followers}', '팔로잉 ${p.following}', '기록 ${p.posts}'].join(metaSep), style: AppType.sub)),
              ]),
            ),
            const SizedBox(width: 16),
            Avatar(name: p.nickname, id: p.userId, size: 64),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.group),
          child: pg.me
              ? Btn(label: '내 공개 프로필 수정', kind: 'secondary', onPress: () => openCommunityProfile(context))
              : Btn(label: pg.followed ? '팔로잉' : '팔로우', kind: pg.followed ? 'secondary' : 'primary', busy: _busy, onPress: _follow),
        ),
        Bleed(
          child: Padding(
            padding: const EdgeInsets.only(top: Space.group),
            child: Tabs<String>(fill: true, items: const [(id: 'posts', label: '독서 기록'), (id: 'reviews', label: '평가')], value: _tab, onChange: (v) => setState(() => _tab = v)),
          ),
        ),
        if (_tab == 'posts')
          if (pg.posts.isEmpty)
            const Padding(padding: EdgeInsets.only(top: Space.s), child: EmptyLine('아직 공유한 독서 기록이 없어요'))
          else
            Bleed(
              child: Column(children: [
                for (final (i, post) in pg.posts.indexed) ...[
                  if (i > 0) _divider,
                  PostCard(post: post, onOpen: () => openCommunityPost(context, post.id)),
                ],
              ]),
            )
        else if (pg.reviews.isEmpty)
          const Padding(padding: EdgeInsets.only(top: Space.s), child: EmptyLine('아직 남긴 공개 평가가 없어요'))
        else
          for (final r in pg.reviews)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(r.bookTitle ?? 'ISBN ${r.isbn13}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowStrong)),
                  const SizedBox(width: 8),
                  // 후기 한 줄 별은 책 정보 독자 후기와 같은 크기(14였다)
                  Stars(value: r.rating, size: reviewStarSize),
                ]),
                if (r.body != null && r.body!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: WordText(r.body!, style: AppType.body)),
              ]),
            ),
      ],
    );
  }
}

// 커뮤니티를 열지 정하는 서버 스위치(지금 앱 useCommunityOpen): 답을 받기 전이나 연결이 안 되면 닫힌 것으로 본다.
// 켤 때 한 번 묻고, 닫혀 있으면 앱으로 돌아올 때 다시 묻는다(서버가 COMMUNITY_ENABLED로 열면 앱을 다시 켜지 않아도 탭이 생긴다)
final communityOpen = ValueNotifier<bool>(false);
AppLifecycleListener? _openWatch;

void watchCommunityOpen() {
  if (_openWatch != null) return;
  Future<void> check(bool force) async => communityOpen.value = (await communityAvailability(force: force)).ok;
  check(false);
  _openWatch = AppLifecycleListener(onResume: () {
    if (!communityOpen.value) check(true);
  });
}
