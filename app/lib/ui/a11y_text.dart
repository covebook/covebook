// 화면 읽기(접근성) 이름: 보이지 않는 글자를 뺀다. 줄바꿈 맞춤에 넣는 단어 이음표(U+2060, ui/keep_all)·폭 없는 공백·줄 나눔 힌트가
// 이름에 섞이면 화면 읽기가 글자를 하나씩 끊어 읽을 수 있다(2026-11-15 QA: 갈피 문장 라벨에 U+2060이 22개)
library;

final _invisible = RegExp('[⁠​‌‍­﻿]');

/// 접근성 이름으로 쓸 글(보이지 않는 글자를 뺀다)
String a11yLabel(String s) => s.replaceAll(_invisible, '');
