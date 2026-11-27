package iapkit

import (
	"testing"
)

// 다른 앱의 규칙으로도 결제가 돈다(결제 키트). 대상이 없는 상품(계정 전체에 붙음)을 판다.
//   - 상한이 없으면: 예약 없이 값만 주고, 살 때마다 수량이 쌓인다
//   - 상한이 있으면: 대상이 없어도 계정 하나의 상한으로 예약·넘김 환불이 똑같이 돈다
func TestIAPRulesWithoutTarget(t *testing.T) {
	e := newIAPEnv(t)
	e.srv.IAPRules = Rules{} // 대상 없음, 상한 없음, 기본 문구
	token, _ := e.user()

	// 대상을 보내면 받지 않는다(이 앱에는 대상이 없다)
	if code, _ := e.call("POST", "/iap/target-token", token, map[string]any{"target": "2026"}); code != 400 {
		t.Fatalf("대상 없는 앱에 대상: %d", code)
	}
	code, body := e.call("POST", "/iap/target-token", token, map[string]any{})
	if code != 200 || body["token"] == nil || body["target"] != "" || body["reservation"] != nil {
		t.Fatalf("상한 없는 값 받기: %d %v", code, body)
	}
	acct := body["token"].(string)
	buy := func(target string) (int, map[string]any) {
		t.Helper()
		id := iapTestID(t, "tok")
		e.google.Purchases[id] = e.shelfPurchase(id, acct)
		return e.call("POST", "/iap/purchases", token, map[string]any{"route": "google", "productId": e.shelf, "proof": id, "target": target})
	}
	for i, want := range []float64{2, 4, 6} {
		code, body = buy("")
		units, _ := body["unitsByTarget"].(map[string]any)
		if code != 200 || body["target"] != "" || units[""] != want || body["overCap"] != nil || body["capPerTarget"] != float64(0) {
			t.Fatalf("%d번째 구매: %d %v", i+1, code, body)
		}
	}
	if code, _ = buy("2026"); code != 400 {
		t.Fatalf("제출에 대상: %d", code)
	}
	// 구독용 값(대상 없음)으로 산 거래도 대상 없는 상품으로 받는다(대상을 모르는 거래가 생기지 않는다)
	id := iapTestID(t, "plain")
	e.google.Purchases[id] = e.shelfPurchase(id, e.accountToken(token))
	if code, body = e.submit(token, "google", e.shelf, id, false); code != 200 || body["target"] != "" {
		t.Fatalf("구독용 값으로 산 거래: %d %v", code, body)
	}

	// 상한 3: 2 + 2는 넘는다. 계정 하나가 대상 하나('')다
	e.srv.IAPRules = Rules{Cap: 3, Hold: covebookIAPRules.Hold}
	other, _ := e.user()
	code, body = e.call("POST", "/iap/target-token", other, map[string]any{"units": 2})
	if code != 200 || body["reservation"] == nil {
		t.Fatalf("상한 있는 값 받기: %d %v", code, body)
	}
	acct = body["token"].(string)
	e.release(other, body)
	token = other
	if code, body = buy(""); code != 200 || body["overCap"] != nil {
		t.Fatalf("상한 안: %d %v", code, body)
	}
	if code, body = e.call("POST", "/iap/target-token", other, map[string]any{"units": 2}); code != 409 || errCode(body) != "iap_cap_full" ||
		body["error"].(map[string]any)["message"] != DefaultMessages["iap_cap_too_many"] {
		t.Fatalf("남은 수량보다 많음(기본 문구): %d %v", code, body)
	}
	if code, body = buy(""); code != 200 || body["overCap"] != true {
		t.Fatalf("예약을 지나쳐 넘게 산 거래: %d %v", code, body)
	}
	if units, _ := body["unitsByTarget"].(map[string]any); units[""] != float64(2) {
		t.Fatalf("넘은 거래는 세지 않음: %v", body)
	}
}
