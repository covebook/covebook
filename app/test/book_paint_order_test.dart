import 'package:chaekjang/domain/book3.dart';
import 'package:chaekjang/domain/vec3.dart';
import 'package:chaekjang/ui/scene.dart' show bookPaintOrder;
import 'package:flutter_test/flutter_test.dart';

Book3 _at(String id, double x, [double y = 0]) => Book3(id: id, dims: const Dims(30, 200, 140), t: Vec3(x, y, 0));

void main() {
  test('눈에서 옆으로 먼 책부터 그린다(가까운 책이 나중에 덮는다)', () {
    final books = [_at('a', 0), _at('b', 30), _at('c', 60), _at('d', 90), _at('e', 120)];
    // 눈은 c 가운데(75): 양 끝 a·e → b·d → c. 거리가 같으면 줄 차례
    expect(bookPaintOrder(books, 75), [0, 4, 1, 3, 2]);
    // 눈이 왼쪽 끝이면 오른쪽 책부터(왼쪽 책이 오른쪽 책의 왼쪽 옆면을 덮는다)
    expect(bookPaintOrder(books, 0), [4, 3, 2, 1, 0]);
  });

  test('쌓은 책은 한 덩이로 줄 차례(아래 책부터)를 지킨다', () {
    final books = [_at('a', 0), _at('low', 100), _at('high', 100, 50)];
    expect(bookPaintOrder(books, 0), [1, 2, 0]);
    expect(bookPaintOrder(books, 200), [0, 1, 2]);
  });

  test('기댄 책은 기댄 이웃보다 먼저 그린다(이웃 책등이 기댄 책 아래쪽을 덮는다)', () {
    // 오른쪽 책이 왼쪽으로 10° 기대 머리 모서리가 이웃 오른쪽 끝에 닿는다(roll: 앞에서 본 기울기)
    final upright = _at('n', 100);
    final lean = Book3(id: 'l', dims: const Dims(30, 200, 140), t: const Vec3(134, 0, 0), roll: 10);
    expect(bookPaintOrder([upright, lean], 0), [1, 0]);
  });
}
