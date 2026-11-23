// 7단계(2026-11-24 사용자, 토스 앱 실측): 글자 · 간격 · 표지 크기. 값은 지시 그대로이고, 그대로 두는 값도 함께 지킨다
import 'package:chaekjang/ui/kit.dart';
import 'package:chaekjang/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  (double, double) sz(TypeSpec t) => (t.size, t.line);

  test('바뀐 글자: 화면 제목 20/29, 구역 제목 17/25.5, 설명 13/19.5, 저자 13/19.5 inkSub', () {
    for (final t in [TypeSpecs.title, TypeSpecs.pageTitle, TypeSpecs.bookHeadTitle, TypeSpecs.essayTitle, TypeSpecs.introTitle, TypeSpecs.profileName]) {
      expect(sz(t), (20, 29));
      expect(t.color, AppColors.title, reason: '색 그대로');
      expect(t.family, AppFonts.uiTitle, reason: '굵기 그대로');
    }
    expect(sz(TypeSpecs.section), (17, 25.5));
    expect(TypeSpecs.section.family, AppFonts.uiTitle);
    expect(sz(TypeSpecs.sub), (13, 19.5));
    expect(sz(TypeSpecs.bookAuthor), (13, 19.5));
    expect(TypeSpecs.bookAuthor.color, AppColors.inkSub);
  });

  test('따로 둔 역할: 누르는 회색 글자 단추 15, 책 화면 머리 저자 15/22.5 inkSoft', () {
    expect(sz(TypeSpecs.subLink), (15, 22.5));
    expect(TypeSpecs.subLink.color, AppColors.inkSoft);
    expect(sz(TypeSpecs.bookHeadAuthor), (15, 22.5));
    expect(TypeSpecs.bookHeadAuthor.color, AppColors.inkSoft);
  });

  test('그대로 두는 글자', () {
    for (final t in [TypeSpecs.row, TypeSpecs.rowStrong, TypeSpecs.body, TypeSpecs.button, TypeSpecs.link, TypeSpecs.bookTitle]) {
      expect(t.size, 17);
    }
    expect(TypeSpecs.secondary.size, 15);
    for (final t in [TypeSpecs.heading, TypeSpecs.bookFeatureTitle, TypeSpecs.bookSavedTitle]) {
      expect(t.size, 20);
    }
    for (final t in [TypeSpecs.dialogBody, TypeSpecs.count, TypeSpecs.bodySmall]) {
      expect(t.size, 15);
    }
    for (final t in [TypeSpecs.caption, TypeSpecs.micro]) {
      expect(t.size, 13);
    }
    expect([TypeSpecs.display.size, TypeSpecs.displayUnit.size, TypeSpecs.timer.size, TypeSpecs.clock.size, TypeSpecs.score.size, TypeSpecs.figure.size], [48, 22, 64, 36, 36, 24]);
  });

  test('간격 · 표지: 구역 사이 32, 줄 · 좌우 여백 · 단추 높이 그대로, 내 책 목록 표지 64, 책 화면 머리 표지 120', () {
    expect(Space.section, 32);
    expect(Space.block, 32);
    expect(Space.page, 24);
    expect(CoverSize.list, 64);
    expect(CoverSize.head, 120);
  });
}
