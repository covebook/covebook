package server

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/iap"
)

// 갱신 예정 고지(T4): 연 구독이고, 이용 중이고, 자동 갱신이 켜져 있고, 갱신일이 N일 안일 때만 한 번 쓴다.
// 월 구독, 주기를 모르는 요금제, 해지 예약, 결제 실패 유예, 주인 없는 줄, 아직 먼 갱신은 쓰지 않는다.
func TestIAPRenewalNotice(t *testing.T) {
	ctx, db := iapTestDB(t)
	now := time.Now().UTC().Truncate(time.Second)
	appleYear, appleMonth, google := iapTestID(t, "year"), iapTestID(t, "month"), iapTestID(t, "plus")
	for _, sql := range []string{
		"INSERT INTO iap_products(route,product_id,kind,entitlement) VALUES('apple','" + appleYear + "','subscription','plus'),('apple','" + appleMonth + "','subscription','plus'),('google','" + google + "','subscription','plus')",
		"INSERT INTO iap_plans(route,product_id,plan_id,period) VALUES('apple','" + appleYear + "','','year'),('apple','" + appleMonth + "','','month'),('google','" + google + "','yearly','year'),('google','" + google + "','monthly','month')",
	} {
		if _, err := db.Exec(ctx, sql); err != nil {
			t.Fatal(err)
		}
	}
	type sub struct {
		name, product, plan string
		route               iap.Route
		owner, autoRenew    bool
		in                  time.Duration // 지금부터 만료까지
		grace               bool
		want                bool
	}
	day := 24 * time.Hour
	cases := []sub{
		{"애플 연, 10일 뒤", appleYear, "", iap.RouteApple, true, true, 10 * day, false, true},
		{"구글 연 요금제, 5일 뒤", google, "yearly", iap.RouteGoogle, true, true, 5 * day, false, true},
		{"월 구독", appleMonth, "", iap.RouteApple, true, true, 10 * day, false, false},
		{"구글 월 요금제", google, "monthly", iap.RouteGoogle, true, true, 10 * day, false, false},
		{"주기를 모르는 요금제", google, "unknown", iap.RouteGoogle, true, true, 10 * day, false, false},
		{"아직 먼 갱신", appleYear, "", iap.RouteApple, true, true, 20 * day, false, false},
		{"해지 예약", appleYear, "", iap.RouteApple, true, false, 10 * day, false, false},
		{"결제 실패 유예", appleYear, "", iap.RouteApple, true, true, 10 * day, true, false},
		{"주인 없음", appleYear, "", iap.RouteApple, false, true, 10 * day, false, false},
		{"이미 지난 만료", appleYear, "", iap.RouteApple, true, true, -day, false, false},
	}
	users := make([]int64, len(cases))
	origs := make([]string, len(cases))
	for i, c := range cases {
		users[i] = iapTestUser(t, ctx, db)
		origs[i] = iapTestID(t, "orig")
		var grace any
		if c.grace {
			grace = now.Add(3 * day)
		}
		var owner any
		if c.owner {
			owner = users[i]
		}
		if _, err := db.Exec(ctx, `INSERT INTO iap_subscriptions(route,original_id,user_id,product_id,plan_id,env,state,expires_at,grace_until,auto_renew)
			VALUES($1,$2,$3,$4,$5,'production','paid',$6,$7,$8)`, string(c.route), origs[i], owner, c.product, c.plan, now.Add(c.in), grace, c.autoRenew); err != nil {
			t.Fatal(c.name, err)
		}
	}
	count := func(user int64) int {
		var n int
		if err := db.QueryRow(ctx, "SELECT count(*)::int FROM iap_notices WHERE user_id=$1 AND kind=$2", user, noticeRenewalUpcoming).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	for range 3 { // 여러 번 돌아도 같은 갱신은 한 줄이다
		if _, err := iapNoteRenewals(ctx, db, now, 14); err != nil {
			t.Fatal(err)
		}
	}
	for i, c := range cases {
		want := 0
		if c.want {
			want = 1
		}
		if got := count(users[i]); got != want {
			t.Fatalf("%s: 갱신 예정 고지 %d줄, 기대 %d", c.name, got, want)
		}
	}

	// 값: 문구 T4에 넣을 것만. 금액은 넣지 않는다
	var template, dedupe string
	var raw []byte
	if err := db.QueryRow(ctx, "SELECT template, params, dedupe_key FROM iap_notices WHERE user_id=$1 AND kind=$2", users[0], noticeRenewalUpcoming).Scan(&template, &raw, &dedupe); err != nil {
		t.Fatal(err)
	}
	var params map[string]any
	if err := json.Unmarshal(raw, &params); err != nil {
		t.Fatal(err)
	}
	expires := iapStamp(now.Add(10 * day))
	if template != "T4" || len(params) != 4 || params["route"] != "apple" || params["productId"] != appleYear || params["period"] != "year" || params["expiresAt"] != expires {
		t.Fatalf("고지 값: %s %v", template, params)
	}
	if dedupe != noticeRenewalUpcoming+":apple:"+origs[0]+":"+expires {
		t.Fatalf("유일 키: %s", dedupe)
	}

	// 갱신되면(만료일이 1년 뒤로) 다음 갱신 14일 전에 다시 한 번 쓴다
	if _, err := db.Exec(ctx, "UPDATE iap_subscriptions SET expires_at=expires_at + interval '365 days' WHERE original_id=$1", origs[0]); err != nil {
		t.Fatal(err)
	}
	if _, err := iapNoteRenewals(ctx, db, now, 14); err != nil {
		t.Fatal(err)
	}
	if got := count(users[0]); got != 1 {
		t.Fatalf("갱신 직후에는 새로 쓰지 않는다: %d", got)
	}
	if _, err := iapNoteRenewals(ctx, db, now.Add(365*day), 14); err != nil {
		t.Fatal(err)
	}
	if got := count(users[0]); got != 2 {
		t.Fatalf("다음 갱신 전: %d줄", got)
	}

	// 며칠 전부터 알릴지는 바꿀 수 있다: 20일로 늘리면 "아직 먼 갱신"도 들어온다
	if _, err := iapNoteRenewals(ctx, db, now, 21); err != nil {
		t.Fatal(err)
	}
	if got := count(users[5]); got != 1 {
		t.Fatalf("21일 기준: %d줄", got)
	}

	// /iap/me의 구독에는 주기가 실린다. 주기를 모르는 요금제는 period가 없다
	for i, want := range map[int]string{0: "year", 2: "month", 4: ""} {
		got, err := iapCurrentSubscription(ctx, db, users[i], false)
		if err != nil {
			t.Fatal(err)
		}
		if p, ok := got["period"]; (want == "" && ok) || (want != "" && p != want) {
			t.Fatalf("%s: period %v, 기대 %q", cases[i].name, got["period"], want)
		}
	}
}

func TestIAPRenewalSchedule(t *testing.T) {
	t.Setenv("IAP_RENEWAL_NOTICE_DAYS", "")
	if iapRenewalNoticeDays() != 14 {
		t.Fatal("기본값은 14일")
	}
	for v, want := range map[string]int{"7": 7, "0": 14, "-3": 14, "100": 14, "x": 14} {
		t.Setenv("IAP_RENEWAL_NOTICE_DAYS", v)
		if got := iapRenewalNoticeDays(); got != want {
			t.Fatalf("%q → %d, 기대 %d", v, got, want)
		}
	}
	s := &Server{}
	now := time.Now()
	if !s.iapRenewalDue(now) || s.iapRenewalDue(now.Add(time.Hour)) || !s.iapRenewalDue(now.Add(iapRenewalEvery)) {
		t.Fatal("서버를 켜면 바로 한 번, 그 뒤로는 6시간에 한 번")
	}
}
