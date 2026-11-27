package server

import (
	"encoding/json"
	"net/http/httptest"
	"testing"
)

// 책장 한켠의 결제 규칙: 대상은 연도 책장, 책장 테이블(bookcases)과 같은 범위, 같은 해가 둘로 나뉘는 모양은 받지 않는다.
func TestCovebookIAPRules(t *testing.T) {
	for y, ok := range map[string]bool{"2026": true, "2000": true, "9999": true, "1999": false, "10000": false, "02026": false, "": false, "abc": false, "+2026": false} {
		if covebookShelfYear(y) != ok {
			t.Errorf("covebookShelfYear(%q) 기대 %v", y, ok)
		}
	}
	if r := covebookIAPRules; !r.TargetRequired || r.Cap != 3 || r.Hold <= 0 || r.ValidTarget == nil {
		t.Fatalf("규칙: %+v", r)
	}
	// 앱이 문구를 주는 오류는 선반·책장 말로 쓴다(키트 기본 문구가 아니라)
	for _, code := range []string{"iap_cap_full", "iap_cap_too_many", "iap_target_busy", "iap_target_missing", "iap_granted_owner", "iap_owner_refunded", "iap_owner_later", "iap_owner_apple"} {
		if covebookIAPRules.Messages[code] == "" {
			t.Errorf("문구 없음: %s", code)
		}
	}
}

// 결제 스위치가 꺼진 서버: 결제 경로가 없고 healthz가 iap=false를 알린다(앱은 이것으로 결제 화면을 숨긴다)
func TestIAPOffByDefault(t *testing.T) {
	t.Setenv("IAP_ENABLED", "")
	h := New(nil).Handler()
	for _, path := range []string{"/iap/me", "/iap/purchases"} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest("GET", path, nil))
		if rec.Code != 404 && rec.Code != 405 {
			t.Fatalf("%s: 꺼져 있는데 %d", path, rec.Code)
		}
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/healthz", nil))
	var health map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &health)
	if health["iap"] != false {
		t.Fatalf("healthz iap=%v", health["iap"])
	}
}
