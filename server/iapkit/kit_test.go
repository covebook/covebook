package iapkit

import (
	"context"
	"crypto/subtle"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// 키트 시험은 PostgreSQL 스키마 하나를 따로 만들어 그 안에서 돈다. 앱(호스트) 시험과 같은 DB(TEST_DATABASE_URL)를 함께 써도
// users 테이블과 키트 테이블이 부딪히지 않는다. 스키마 안에는 키트가 요구하는 가장 작은 users 테이블만 둔다(README "붙이는 법").
var iapTestDSN string

func TestMain(m *testing.M) {
	os.Exit(runWithSchema(m))
}

func runWithSchema(m *testing.M) int {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		return m.Run() // DB 시험은 각자 건너뛴다
	}
	ctx := context.Background()
	admin, err := pgxpool.New(ctx, dsn)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	defer admin.Close()
	schema := fmt.Sprintf("iapkit_test_%d_%d", os.Getpid(), time.Now().UnixNano()%1_000_000)
	if _, err = admin.Exec(ctx, "CREATE SCHEMA "+schema); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	defer admin.Exec(ctx, "DROP SCHEMA "+schema+" CASCADE")
	u, err := url.Parse(dsn)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	q := u.Query()
	q.Set("search_path", schema)
	u.RawQuery = q.Encode()
	iapTestDSN = u.String()
	db, err := pgxpool.New(ctx, iapTestDSN)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	_, err = db.Exec(ctx, "CREATE TABLE users (id BIGSERIAL PRIMARY KEY, created_at TIMESTAMPTZ NOT NULL DEFAULT now())")
	db.Close()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	return m.Run()
}

// covebookIAPRules는 시험용 규칙이다. 책장 한켠의 규칙(server/internal/server/iap.go)과 같은 값을 쓴다:
// 대상은 연도 책장("2026"), 대상마다 3칸까지. 키트가 앱 말(선반·연도)을 모르고도 그 규칙대로 도는지 본다.
var covebookIAPRules = Rules{
	TargetRequired: true,
	ValidTarget: func(s string) bool {
		y, err := strconv.Atoi(s)
		return err == nil && y >= 2000 && y <= 9999 && strconv.Itoa(y) == s
	},
	Cap:  3,
	Hold: 5 * time.Minute,
}

// iapTestKit은 시험용 호스트를 붙인 키트다. 로그인 토큰은 "u<유저 번호>", 운영자는 ADMIN_TOKEN과 같은 X-Admin-Token이다.
func iapTestKit(db *pgxpool.Pool) *Kit {
	k := New(db, nil, covebookIAPRules, false)
	k.Auth = func(w http.ResponseWriter, r *http.Request) (int64, bool) {
		raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer u")
		user, err := strconv.ParseInt(raw, 10, 64)
		if !ok || err != nil {
			fail(w, unauthorized)
			return 0, false
		}
		return user, true
	}
	k.Admin = func(r *http.Request) bool {
		want, got := os.Getenv("ADMIN_TOKEN"), r.Header.Get("X-Admin-Token")
		return want != "" && subtle.ConstantTimeCompare([]byte(got), []byte(want)) == 1
	}
	return k
}

// Handler는 시험에서 키트 경로만 붙인 핸들러다.
func (s *Kit) Handler() http.Handler {
	m := http.NewServeMux()
	s.Routes(m)
	return m
}
