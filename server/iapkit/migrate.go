package iapkit

import (
	"context"
	"embed"
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// 키트의 테이블(iap_*)은 키트가 만든다. 앱의 마이그레이션과 번호를 나눠 쓰지 않는다(키트를 다른 앱에 붙여도 번호가 부딪히지 않게).
// 적용한 파일은 iapkit_schema_history에 남는다. 앱은 자기 마이그레이션(users 테이블을 만드는 것) 뒤에 Migrate를 부른다.
//
//go:embed migrations/*.sql
var migrations embed.FS

// migrationFiles는 migrations/<번호>_<설명>.sql 파일을 번호 순으로 준다. 번호는 1부터 빈틈없이 이어져야 한다.
func migrationFiles() ([]string, error) {
	entries, err := migrations.ReadDir("migrations")
	if err != nil {
		return nil, err
	}
	type file struct {
		version int
		name    string
	}
	var files []file
	for _, e := range entries {
		head, _, ok := strings.Cut(e.Name(), "_")
		v, err := strconv.Atoi(head)
		if !ok || err != nil || !strings.HasSuffix(e.Name(), ".sql") {
			return nil, fmt.Errorf("iapkit migration %s: name must be <version>_<description>.sql", e.Name())
		}
		files = append(files, file{v, e.Name()})
	}
	sort.Slice(files, func(i, j int) bool { return files[i].version < files[j].version })
	out := make([]string, len(files))
	for i, f := range files {
		if f.version != i+1 {
			return nil, fmt.Errorf("iapkit migration %s: versions must be 1..n without gaps", f.name)
		}
		out[i] = f.name
	}
	return out, nil
}

// Migrate는 키트의 테이블을 만들거나 고친다. 여러 서버가 동시에 불러도 한 번만 적용한다(트랜잭션 잠금).
// 앱 DB에 users(id BIGINT PRIMARY KEY) 테이블이 먼저 있어야 한다(키트 테이블이 유저를 가리킨다).
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
	if _, err = tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtextextended('iapkit.migrate', 0))"); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, "CREATE TABLE IF NOT EXISTS iapkit_schema_history (version integer PRIMARY KEY, name text NOT NULL, installed_at timestamptz NOT NULL DEFAULT now())"); err != nil {
		return err
	}
	var newer bool
	if err = tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM iapkit_schema_history WHERE version>$1)", len(files)).Scan(&newer); err != nil {
		return err
	}
	if newer {
		return fmt.Errorf("iapkit schema has newer migrations; review before starting this server")
	}
	for i, name := range files {
		var done bool
		if err = tx.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM iapkit_schema_history WHERE version=$1)", i+1).Scan(&done); err != nil {
			return err
		}
		if done {
			continue
		}
		data, err := migrations.ReadFile("migrations/" + name)
		if err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, string(data)); err != nil {
			return fmt.Errorf("iapkit migration %s: %w", name, err)
		}
		if _, err = tx.Exec(ctx, "INSERT INTO iapkit_schema_history(version, name) VALUES ($1,$2)", i+1, name); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
