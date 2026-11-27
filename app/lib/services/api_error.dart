/// 서버가 돌려준 오류(상태 · 코드 · 한국어 메시지). 화면에 보일 문장은 error_text.dart errorText
class ApiError implements Exception {
  ApiError(this.status, this.code, this.message);
  final int status;
  final String code, message;

  @override
  String toString() => message;
}
