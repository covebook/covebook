package server

import (
	"context"
	"embed"
	"fmt"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yuntyu01/chaekjang-hankyeon/server/iapkit"
	"sort"
	"strconv"
	"strings"
)

// Existing Flyway-managed migrations (V1~V7) are never replayed. Later files are Go-owned:
// they are applied to both Flyway and Go databases and recorded in go_schema_history.
//
//go:embed migrations/*.sql
var migrations embed.FS

// flywayBase is the last version the retired Java server applied with Flyway.
const flywayBase = 7

type migration struct {
	version int
	name    string
}

// Versions come from the V<n>__ prefix, not the file order (V10 sorts before V8 as text).
func migrationFiles() ([]migration, error) {
	entries, err := migrations.ReadDir("migrations")
	if err != nil {
		return nil, err
	}
	out := make([]migration, 0, len(entries))
	for _, entry := range entries {
		name := entry.Name()
		head, _, ok := strings.Cut(strings.TrimPrefix(name, "V"), "__")
		version, e := strconv.Atoi(head)
		if !ok || !strings.HasPrefix(name, "V") || e != nil || version < 1 {
			return nil, fmt.Errorf("migration %s: name must be V<version>__<description>.sql", name)
		}
		out = append(out, migration{version, name})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].version < out[j].version })
	for i, m := range out {
		if m.version != i+1 {
			return nil, fmt.Errorf("migration %s: versions must be 1..n without gaps or duplicates", m.name)
		}
	}
	return out, nil
}

func Migrate(ctx context.Context, db *pgxpool.Pool) error {
	files, err := migrationFiles()
	if err != nil {
		return err
	}
	tx, err := db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, "SELECT pg_advisory_xact_lock(987614002)"); err != nil {
		return err
	}
	var flyway, own, existing bool
	if err = tx.QueryRow(ctx, "SELECT to_regclass('public.flyway_schema_history') IS NOT NULL, to_regclass('public.go_schema_history') IS NOT NULL, to_regclass('public.users') IS NOT NULL").Scan(&flyway, &own, &existing); err != nil {
		return err
	}
	from := 1
	if flyway {
		var n int
		if err = tx.QueryRow(ctx, "SELECT count(DISTINCT version) FROM flyway_schema_history WHERE success AND version IN ('1','2','3','4','5','6','7')").Scan(&n); err != nil {
			return err
		}
		if n != flywayBase {
			return fmt.Errorf("Flyway schema is incomplete; apply migrations with Flyway before starting the server")
		}
		var unsafe bool
		if err = tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM flyway_schema_history WHERE NOT success OR (version ~ '^[0-9]+$' AND version::numeric > 7))").Scan(&unsafe); err != nil {
			return err
		}
		if unsafe {
			return fmt.Errorf("Flyway history contains failed or newer migrations; review before starting Go server")
		}
		from = flywayBase + 1
	} else if existing && !own {
		return fmt.Errorf("existing schema has no recognized migration history")
	}
	if _, err = tx.Exec(ctx, "CREATE TABLE IF NOT EXISTS go_schema_history (version integer PRIMARY KEY, installed_at timestamptz NOT NULL DEFAULT now())"); err != nil {
		return err
	}
	if err = dropLegacyIAP(ctx, tx); err != nil {
		return err
	}
	var newer bool
	if err = tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM go_schema_history WHERE version>$1)", len(files)).Scan(&newer); err != nil {
		return err
	}
	if newer {
		return fmt.Errorf("Go schema has newer migrations; review before starting this server")
	}
	for _, m := range files {
		if m.version < from {
			continue
		}
		var done bool
		if err = tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM go_schema_history WHERE version=$1)", m.version).Scan(&done); err != nil {
			return err
		}
		if done {
			continue
		}
		data, e := migrations.ReadFile("migrations/" + m.name)
		if e != nil {
			return e
		}
		if _, err = tx.Exec(ctx, string(data)); err != nil {
			return fmt.Errorf("migration %s: %w", m.name, err)
		}
		if _, err = tx.Exec(ctx, "INSERT INTO go_schema_history(version) VALUES ($1)", m.version); err != nil {
			return err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return err
	}
	// 결제 키트의 테이블(iap_*)은 키트가 따로 관리한다(iapkit_schema_history). users 테이블을 가리켜서 앱 마이그레이션 뒤에 돈다
	return iapkit.Migrate(ctx, db)
}

// legacyIAPTables는 main에 2026-11-23부터 있던 결제 V21이 만든 테이블이다(지우는 순서: FK를 받는 쪽부터)
var legacyIAPTables = []string{"iap_notifications", "iap_subscriptions", "iap_purchases", "iap_products", "iap_shelf_reservations", "iap_account_tokens"}

// dropLegacyIAP는 옛 결제 V21을 걷어 낸다. 결제 테이블은 이제 결제 키트가 따로 만든다(iapkit_schema_history).
//   - 옛 V21이 적용된 DB(운영은 2026-11-26 자동 배포로 적용됨)는 이력에 21이 있어 "newer migrations"로 멈추고,
//     키트의 001이 같은 이름의 테이블과 부딪힌다. 또 나중에 앱이 V21을 새로 만들면 "이미 했음"으로 건너뛴다
//   - 그래서 옛 테이블이 모두 비어 있으면(결제를 켠 적이 없음) 테이블과 21번 기록을 지우고, 키트가 새로 만들게 한다
//   - 한 줄이라도 있으면 지우지 않고 멈춘다. 사람이 키트 테이블로 옮긴 뒤 띄운다
//
// 옛 V21에만 있는 iap_shelf_reservations(키트는 iap_reservations)와 21번 기록이 함께 있을 때만 옛 V21로 본다.
func dropLegacyIAP(ctx context.Context, tx pgx.Tx) error {
	var legacy bool
	if err := tx.QueryRow(ctx, "SELECT to_regclass('public.iap_shelf_reservations') IS NOT NULL AND EXISTS(SELECT 1 FROM go_schema_history WHERE version=21)").Scan(&legacy); err != nil {
		return err
	}
	if !legacy {
		return nil
	}
	for _, t := range legacyIAPTables {
		var rows bool
		if err := tx.QueryRow(ctx, "SELECT to_regclass('public."+t+"') IS NOT NULL").Scan(&rows); err != nil {
			return err
		}
		if !rows {
			continue
		}
		if err := tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM public."+t+")").Scan(&rows); err != nil {
			return err
		}
		if rows {
			return fmt.Errorf("old payment table %s (migration V21) has rows; move them to the iapkit tables before starting this server", t)
		}
	}
	for _, t := range legacyIAPTables {
		if _, err := tx.Exec(ctx, "DROP TABLE IF EXISTS public."+t); err != nil {
			return err
		}
	}
	_, err := tx.Exec(ctx, "DELETE FROM go_schema_history WHERE version=21")
	return err
}
