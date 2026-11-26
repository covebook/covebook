import 'package:flutter_test/flutter_test.dart';
import 'package:chaekjang/ui/josa.dart';

void main() {
  test('을/를: 한글 받침', () {
    expect(eulReul('처리방침'), '처리방침을');
    expect(eulReul('페이지'), '페이지를');
    expect(eulReul('책'), '책을');
  });

  test('을/를: 파일 이름 · 따옴표 · 숫자 · 라틴 글자', () {
    expect(eulReul('‘책장한켠 예시.csv’'), '‘책장한켠 예시.csv’를');
    expect(eulReul('책장한켠 예시 (4).csv'), '책장한켠 예시 (4).csv를');
    expect(eulReul('1984'), '1984를');
    expect(eulReul('YES24'), 'YES24를');
    expect(eulReul('2026'), '2026을');
    expect(eulReul('html'), 'html을');
  });

  test('이/가 · 은/는 · 으로/로', () {
    expect(iGa('책장'), '책장이');
    expect(iGa('갈피'), '갈피가');
    expect(eunNeun('감상'), '감상은');
    expect(eunNeun('메모'), '메모는');
    expect(euroRo('서울'), '서울로');
    expect(euroRo('책장'), '책장으로');
    expect(euroRo('다운로드'), '다운로드로');
  });
}
