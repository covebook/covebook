-- 긴 감상(앱 기록 > 감상, 2026-11-16): 책 한 권에 여러 편. 별점·한 줄 감상(my_books.rating·note)과 따로 둔다.
-- 다른 서재 표처럼 사용자별 id, 삭제 표시(deleted_at), 동기화 차례(rev). 책 연결은 같은 사용자의 내 책.
CREATE TABLE essays (
    user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id          TEXT   NOT NULL,
    my_book_id  TEXT   NOT NULL,
    title       TEXT,
    body        TEXT   NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL,
    deleted_at  TIMESTAMPTZ,
    rev         BIGINT NOT NULL,
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, my_book_id) REFERENCES my_books (user_id, id)
);
CREATE INDEX essays_rev_idx ON essays (user_id, rev);
CREATE INDEX essays_book_idx ON essays (user_id, my_book_id, created_at DESC);
