package server

import (
	"strings"
	"testing"
)

// 긴 감상(V19): 동기화 종류에 있고 책 연결이 필수, 본문은 빈 글로 바꿔 받는다
func TestEssayKind(t *testing.T) {
	var essay *kind
	for i := range kinds {
		if kinds[i].name == "essays" {
			essay = &kinds[i]
		}
	}
	if essay == nil || essay.table != "essays" {
		t.Fatalf("essays kind missing: %+v", kinds)
	}
	if kinds[len(kinds)-1].name != "essays" {
		t.Fatalf("essays must come after books (foreign key order)")
	}
	byJSON := map[string]field{}
	for _, f := range fields(*essay) {
		byJSON[f.json] = f
	}
	if f := byJSON["myBookId"]; !f.required || f.col != "my_book_id" {
		t.Fatalf("myBookId must be required: %+v", f)
	}
	if f := byJSON["title"]; f.required {
		t.Fatalf("title must be optional")
	}
	if v, err := parseField(nil, byJSON["body"]); err != nil || v != "" {
		t.Fatalf("missing body = empty text, got %v %v", v, err)
	}
	if sql := upsertSQL["essays"]; !strings.HasPrefix(sql, "INSERT INTO essays (user_id,id,my_book_id,title,body,created_at,updated_at,rev,deleted_at)") {
		t.Fatalf("upsert %s", sql)
	}
}
