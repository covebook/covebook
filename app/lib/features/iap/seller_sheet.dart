// 사업자 정보(내 정보 > 사업자 정보, ADR-0003 L14). 전자상거래법이 요구하는 표시 항목을 한 화면에 보여 준다.
// 값은 서버 설정에서 온다(공개 저장소라 앱 코드에 적지 않는다). 서버가 주지 않은 항목은 줄을 내지 않는다.
library;

import 'package:flutter/material.dart';

import '../../store/entitlement_store.dart';
import '../../ui/kit.dart';

/// 표시 순서와 이름(전자상거래법 제10조·제13조, 시행령 제11조의4의 표시 항목)
const sellerFields = [
  ('name', '상호'),
  ('owner', '대표자'),
  ('address', '주소'),
  ('phone', '전화번호'),
  ('email', '전자우편'),
  ('bizNo', '사업자등록번호'),
  ('saleNo', '통신판매업 신고번호'),
  ('host', '호스팅서비스 제공자'), // 전자상거래법 시행령 제11조의4
];

bool get hasSellerInfo => EntitlementStore.instance.seller.isNotEmpty;

Future<void> showSellerSheet(BuildContext context) {
  final seller = EntitlementStore.instance.seller;
  return showSheet<void>(
    context,
    title: '사업자 정보',
    scroll: true,
    builder: (ctx) => ListGroup(children: [
      for (final (key, label) in sellerFields)
        if (seller[key] != null) ListItem(label: label, sub: seller[key]),
    ]),
  );
}
