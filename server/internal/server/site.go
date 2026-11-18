package server

import (
	"embed"
	"net/http"
)

// 앱 소개 홈페이지와 개인정보 처리방침(https://covebook.kodeploy.com/, /privacy).
// Google 브랜딩 인증은 홈페이지·처리방침이 우리 소유 도메인에 있어야 로그인 창에 '책장 한켠'을 띄운다(2026-11-18).
// 처리방침을 고치면 site/privacy.html을 고치고 '최종 수정' 줄을 바꾼다
//
//go:embed site/index.html site/privacy.html site/icon.png
var site embed.FS

func page(name, contentType string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		b, err := site.ReadFile("site/" + name)
		if err != nil {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", contentType)
		w.Header().Set("Cache-Control", "public, max-age=600")
		_, _ = w.Write(b)
	}
}
