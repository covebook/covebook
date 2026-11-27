package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yuntyu01/chaekjang-hankyeon/server/internal/server"
)

func normalizeDatabaseURL(url string) string {
	url = strings.TrimPrefix(url, "jdbc:")
	if strings.HasPrefix(url, "postgresql+psycopg2://") {
		return "postgresql://" + strings.TrimPrefix(url, "postgresql+psycopg2://")
	}
	return url
}

// defaultMaxConns는 DATABASE_URL에 pool_max_conns가 없을 때의 연결 풀 크기다.
const defaultMaxConns = 10

func main() {
	ctx := context.Background()
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		log.Fatal("DATABASE_URL is required")
	}
	url = normalizeDatabaseURL(url)
	cfg, err := pgxpool.ParseConfig(url)
	if err != nil {
		// pgx parse errors may contain the original URL, including its password.
		log.Fatal("DATABASE_URL is invalid; check its format")
	}
	// 연결 풀 크기를 정해 둔다. 기본값은 max(4, CPU 수)라 작은 컨테이너에서는 4개다.
	// 결제 트랜잭션이 잠금을 기다리는 동안(최대 5초) 다른 요청이 쓸 연결이 모자라지 않게 늘린다.
	// DB의 max_connections(PostgreSQL 기본 100)를 넘지 않는 선에서, 주소에 pool_max_conns가 있으면 그것을 따른다
	if !strings.Contains(url, "pool_max_conns") {
		cfg.MaxConns = defaultMaxConns
	}
	db, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		log.Fatal("database pool could not be created")
	}
	defer db.Close()
	if err = db.Ping(ctx); err != nil {
		log.Fatal(err)
	}
	if err = server.Migrate(ctx, db); err != nil {
		log.Fatal(err)
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	app := server.New(db)
	if app.ConfigError != nil {
		log.Fatal(app.ConfigError)
	}
	// 복원된 DB에 과거 삭제 요청을 다시 적용한 뒤에만 요청을 받는다.
	if err = app.InitializeDeletion(ctx); err != nil {
		log.Fatal("account deletion journal initialization failed")
	}
	app.StartDeletionWorker(ctx)
	app.StartIAPWorker(ctx) // 결제가 꺼져 있으면 아무 일도 하지 않는다
	srv := &http.Server{Addr: ":" + port, Handler: app.Handler(), ReadHeaderTimeout: 10 * time.Second}
	log.Printf("listening on :%s", port)
	log.Fatal(srv.ListenAndServe())
}
