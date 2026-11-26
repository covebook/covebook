package server

import (
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

// 웹 약관과 앱 안 약관(app/lib/features/settings/terms.dart)은 같은 글이어야 한다.
// 앱 파일에 웹의 문단이 그대로 있는지 본다(Dart 글은 작은따옴표를 \'로 쓴다). 유료 조는 앱에 유료 조가 있을 때만 본다
func TestTermsMatchApp(t *testing.T) {
	b, err := os.ReadFile("../../../app/lib/features/settings/terms.dart")
	if err != nil {
		t.Skip("앱 파일이 없다(서버만 받은 경우)")
	}
	app := string(b)
	check := func(s string) {
		t.Helper()
		if !strings.Contains(app, strings.ReplaceAll(s, "'", `\'`)) {
			t.Errorf("앱 약관에 없는 문단: %s", s)
		}
	}
	for _, a := range termsBase {
		if !strings.Contains(app, a.Title) {
			t.Errorf("앱 약관에 없는 조: %s", a.Title)
		}
		for _, p := range a.Paras {
			check(p)
		}
	}
	if !strings.Contains(app, "paidArticles") {
		return
	}
	check(termsPaidAccountNote)
	for _, a := range termsPaid {
		if !strings.Contains(app, a.Title) {
			t.Errorf("앱 약관에 없는 조: %s", a.Title)
		}
		for _, p := range a.Paras {
			check(p)
		}
	}
}

// 결제를 끈 서버는 10조, 켠 서버는 유료 조 4개가 (서비스의 변경과 중단) 앞에 들어가 14조
func TestTermsPage(t *testing.T) {
	h := New(nil).Handler()
	get := func() string {
		t.Helper()
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", "/terms", nil))
		if w.Code != 200 || !strings.HasPrefix(w.Header().Get("Content-Type"), "text/html") {
			t.Fatalf("/terms %d %s", w.Code, w.Header().Get("Content-Type"))
		}
		return w.Body.String()
	}

	t.Setenv("IAP_ENABLED", "")
	free := get()
	for _, want := range []string{"제1조 (목적)", "제7조 (서비스의 변경과 중단)", "제10조 (문의)", "&#34;회원&#34;은", "&#39;내 정보 › 이용약관&#39;"} {
		if !strings.Contains(free, want) {
			t.Errorf("결제 끈 약관에 %q 없음", want)
		}
	}
	for _, not := range []string{"유료 서비스", "제11조"} {
		if strings.Contains(free, not) {
			t.Errorf("결제 끈 약관에 %q 있음", not)
		}
	}

	t.Setenv("IAP_ENABLED", "1")
	paid := get()
	for _, want := range []string{"제7조 (유료 서비스)", "제8조 (구독의 자동 갱신과 해지)", "제11조 (서비스의 변경과 중단)", "제14조 (문의)", "계정과 분리해 보관합니다"} {
		if !strings.Contains(paid, want) {
			t.Errorf("결제 켠 약관에 %q 없음", want)
		}
	}
	// 앞 호출이 공용 글을 바꾸지 않았다(탈퇴 문단에 결제 문장이 두 번 붙지 않는다)
	if strings.Count(paid, "계정과 분리해 보관합니다") != 1 || strings.Contains(termsBase[3].Paras[2], "분리") {
		t.Error("탈퇴 문단의 결제 문장이 두 번 붙거나 원본이 바뀜")
	}
}
