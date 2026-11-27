package server

import (
	"context"
	"fmt"
	"github.com/jackc/pgx/v5/pgxpool"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"
)

func TestFlywayV5RequiresUpgrade(t *testing.T) {
	dsn := os.Getenv("TEST_FLYWAY_V5_URL")
	if dsn == "" {
		t.Skip("set TEST_FLYWAY_V5_URL to a disposable Flyway V5 database")
	}
	db, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if err = Migrate(context.Background(), db); err == nil || !strings.Contains(err.Error(), "incomplete") {
		t.Fatalf("expected incomplete schema error, got %v", err)
	}
}
func TestFlywayV7CanStart(t *testing.T) {
	dsn := os.Getenv("TEST_FLYWAY_V7_URL")
	if dsn == "" {
		t.Skip("set TEST_FLYWAY_V7_URL to a disposable Flyway V7 database")
	}
	db, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if err = Migrate(context.Background(), db); err != nil {
		t.Fatal(err)
	}
}

// 운영 DB처럼 옛 결제 V21(main 2026-11-23~)이 적용된 DB에서도 서버가 뜨고, 결제 테이블은 키트가 새로 만든다.
// 옛 테이블에 줄이 있으면 지우지 않고 멈춘다
func TestMigrateDropsLegacyIAP(t *testing.T) {
	ctx := context.Background()
	for _, filled := range []bool{false, true} {
		db := scratchDB(t)
		if err := Migrate(ctx, db); err != nil {
			t.Fatal(err)
		}
		legacy, err := os.ReadFile("testdata/legacy_v21_iap.sql")
		if err != nil {
			t.Fatal(err)
		}
		// 키트가 만든 것을 걷고, 옛 V21을 그대로 깔아 운영 상태를 만든다
		mustExec(t, db, `DROP TABLE iapkit_schema_history, iap_notices, iap_plans, iap_reservations, iap_notifications, iap_subscriptions, iap_purchases, iap_products, iap_account_tokens CASCADE`)
		mustExec(t, db, string(legacy))
		mustExec(t, db, `INSERT INTO go_schema_history(version) VALUES (21)`)
		if filled {
			mustExec(t, db, `WITH u AS (INSERT INTO users DEFAULT VALUES RETURNING id) INSERT INTO iap_account_tokens(token, user_id, year) SELECT md5(random()::text)::uuid, id, 2026 FROM u`)
			if err = Migrate(ctx, db); err == nil || !strings.Contains(err.Error(), "iap_account_tokens") {
				t.Fatalf("옛 테이블에 줄이 있으면 멈춰야 함: %v", err)
			}
			var kept bool
			if err = db.QueryRow(ctx, `SELECT to_regclass('public.iap_shelf_reservations') IS NOT NULL`).Scan(&kept); err != nil || !kept {
				t.Fatalf("줄이 있으면 옛 테이블을 지우지 않음: %v %v", kept, err)
			}
			continue
		}
		if err = Migrate(ctx, db); err != nil {
			t.Fatal(err)
		}
		var old, kit, v21 bool
		if err = db.QueryRow(ctx, `SELECT to_regclass('public.iap_shelf_reservations') IS NOT NULL, to_regclass('public.iap_reservations') IS NOT NULL, EXISTS(SELECT 1 FROM go_schema_history WHERE version=21)`).Scan(&old, &kit, &v21); err != nil {
			t.Fatal(err)
		}
		if old || !kit || v21 {
			t.Fatalf("옛 테이블 남음=%v 키트 테이블=%v 21번 기록=%v", old, kit, v21)
		}
		// 두 번째 기동은 아무것도 하지 않는다
		if err = Migrate(ctx, db); err != nil {
			t.Fatal(err)
		}
	}
}

// scratchDB는 TEST_DATABASE_URL 서버에 빈 DB를 하나 만들어 준다(시험이 끝나면 지운다)
func scratchDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set TEST_DATABASE_URL to a disposable PostgreSQL database")
	}
	ctx := context.Background()
	admin, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(admin.Close)
	name := fmt.Sprintf("scratch_%d_%d", os.Getpid(), time.Now().UnixNano())
	if _, err = admin.Exec(ctx, "CREATE DATABASE "+name); err != nil {
		t.Skipf("빈 DB를 만들 수 없음(CREATEDB 권한): %v", err)
	}
	u, err := url.Parse(dsn)
	if err != nil {
		t.Fatal(err)
	}
	u.Path = "/" + name
	db, err := pgxpool.New(ctx, u.String())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		db.Close()
		_, _ = admin.Exec(context.Background(), "DROP DATABASE IF EXISTS "+name+" WITH (FORCE)")
	})
	return db
}

func mustExec(t *testing.T, db *pgxpool.Pool, sql string) {
	t.Helper()
	if _, err := db.Exec(context.Background(), sql); err != nil {
		t.Fatalf("%v\n%s", err, sql)
	}
}
