// 로그인 단추(카카오·Apple·Google): 로그인 화면이 쓴다(2026-11-16 시안, DESIGN 16장 예외)
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'kit.dart';
import 'theme.dart';

/// 로그인 단추: 세 회사 모두 같은 틀(높이 48(Btn m과 같다), 모서리 Shape.button, 가운데 로고+글자)에 각 회사 규칙의 색만 다르다.
/// 카카오: 노랑 #FEE500·검은 말풍선·글자 85% 검정. Apple: 검정 바탕·흰 로고(HIG 사용자 정의 단추). Google: 옅은 회색 바탕 #F2F2F2·선 없음·네 색 G(브랜딩 지침의 Neutral 모양, 2026-11-17 사용자 시안)
/// 연결된 계정 줄의 회사 표시(계정 및 동기화 시안, 2026-11-17): Google은 G, 카카오는 노란 원 안 말풍선, Apple은 검은 사과
Widget brandLogo(String provider, {double size = 36}) => switch (provider) {
      'google' => SvgPicture.string(BrandButton._googleSvg, width: size * 0.8, height: size * 0.8),
      'kakao' => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: Color(0xFFFEE500), shape: BoxShape.circle),
          child: Center(child: SvgPicture.string(BrandButton._kakaoSvg, width: size * 0.55, height: size * 0.55)),
        ),
      _ => Icon(Icons.apple, size: size * 0.9, color: const Color(0xFF000000)),
    };

class BrandButton extends StatefulWidget {
  const BrandButton({super.key, required this.label, required this.bg, required this.fg, required this.logo, required this.onPress, required this.border});

  BrandButton.kakao({Key? key, required VoidCallback? onPress})
      : this(key: key, label: '카카오로 계속하기', bg: const Color(0xFFFEE500), fg: const Color(0xD9000000), logo: SvgPicture.string(_kakaoSvg, width: 20, height: 20), border: null, onPress: onPress);

  const BrandButton.apple({Key? key, required VoidCallback? onPress})
      : this(key: key, label: 'Apple로 계속하기', bg: const Color(0xFF000000), fg: const Color(0xFFFFFFFF), logo: const Icon(Icons.apple, size: 22, color: Color(0xFFFFFFFF)), border: null, onPress: onPress);

  BrandButton.google({Key? key, required VoidCallback? onPress})
      // 흰 단추(2026-11-18 사용자: 로그인 아래쪽은 회색 기운 바탕, Google은 흰색 유지, 테두리는 없앤다)
      : this(key: key, label: 'Google로 계속하기', bg: const Color(0xFFFFFFFF), fg: const Color(0xFF1F1F1F), border: null, logo: SvgPicture.string(_googleSvg, width: 20, height: 20), onPress: onPress);

  final String label;
  final Color bg, fg;
  final Color? border;
  final Widget logo;
  final VoidCallback? onPress;

  static const _kakaoSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 3.2C6.7 3.2 2.4 6.6 2.4 10.8c0 2.7 1.8 5.1 4.5 6.4l-.9 3.4c-.1.3.3.5.5.4l4-2.7c.5.1 1 .1 1.5.1 5.3 0 9.6-3.4 9.6-7.6S17.3 3.2 12 3.2z"/></svg>';
  static const _googleSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>';

  @override
  State<BrandButton> createState() => _BrandButtonState();
}

class _BrandButtonState extends State<BrandButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final off = widget.onPress == null;
    // 눌림: 바탕 위에 옅은 검정을 얹는다(회사 색은 그대로 두고 어둡게만)
    final bg = _down && !off ? Color.alphaBlend(const Color(0x14000000), widget.bg) : widget.bg;
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      enabled: !off,
      onTap: widget.onPress,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: off ? null : (_) => setState(() => _down = true),
        onTapCancel: off ? null : () => setState(() => _down = false),
        onTapUp: off ? null : (_) => setState(() => _down = false),
        onTap: widget.onPress,
        child: Opacity(
          opacity: off ? 0.45 : 1,
          child: Container(
            constraints: BoxConstraints(minHeight: Btn.heightOf('m')),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Shape.button),
              border: widget.border == null ? null : Border.all(color: widget.border!),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 22, height: 22, child: Center(child: widget.logo)),
              const SizedBox(width: 10),
              Flexible(child: WordText(widget.label, textAlign: TextAlign.center, style: AppType.buttonSmall.copyWith(color: widget.fg))),
            ]),
          ),
        ),
      ),
    );
  }
}
