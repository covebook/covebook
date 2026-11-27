package server

import (
	"bytes"
	"fmt"
	"html/template"
	"net/http"
	"os"
	"strings"
)

// 이용약관 웹 페이지(https://covebook.kodeploy.com/terms).
// 애플 심사 지침 3.1.2: 자동 갱신 구독 앱은 스토어 설명에도 이용약관 링크가 있어야 한다. 앱 안 전문과 같은 글을 웹에 둔다.
// 글은 앱 app/lib/features/settings/terms.dart, 초안 docs/legal/terms-draft-2026-11-18.md와 같다(세 곳을 같이 고친다).
// TestTermsMatchApp이 앱 파일과 문단이 같은지 본다.

type termsArticle struct {
	Title string
	Paras []string
}

// 결제와 상관없는 조(번호 없이). 번호는 termsArticles가 매긴다
var termsBase = []termsArticle{
	{"(목적)", []string{`이 약관은 책장 한켠(이하 "서비스")을 이용할 때 서비스와 회원 사이의 권리, 의무, 책임과 이용 조건을 정합니다.`}},
	{"(정의)", []string{
		`"회원"은 카카오, Google, Apple 계정으로 로그인해 서비스를 이용하는 사람입니다.`,
		`"기록"은 회원이 서비스에 남긴 책 목록과 읽기 상태, 책장 배치와 꾸미기, 독서 시간과 회차, 갈피, 별점, 한줄평, 감상, 회원이 찍거나 고른 사진을 말합니다.`,
		`"외부 제공 정보"는 도서 검색 결과, 표지 그림, 쪽수, 판형 같은 서지 정보처럼 YES24 등 외부 제공처에서 받아 보여 주는 정보를 말합니다.`,
	}},
	{"(약관의 게시와 변경)", []string{
		`이 약관은 앱의 '내 정보 › 이용약관'에 게시합니다.`,
		`약관을 바꿀 때는 시행일 7일 전부터 앱에 알립니다. 회원에게 불리한 변경은 30일 전부터 알립니다. 바뀐 약관에 동의하지 않으면 탈퇴해 이용을 그만둘 수 있습니다.`,
	}},
	{"(계정)", []string{
		`회원은 카카오, Google, Apple 로그인으로 계정을 만들고, 같은 계정으로 다른 기기에서도 기록을 이어 봅니다.`,
		`로그아웃하면 그 기기에 있는 기록을 지웁니다. 서버에 올라간 기록은 남아 다시 로그인하면 받아 옵니다.`,
		`회원은 '내 정보 › 계정 및 동기화 › 회원탈퇴'에서 언제든 탈퇴를 요청할 수 있습니다. 탈퇴를 요청하면 연결된 로그인과 서버의 기록, 사진을 삭제합니다.`,
	}},
	{"(기록의 보관)", []string{
		`서비스는 회원의 기록을 기기와 책장 한켠 서버의 회원 계정에 보관합니다. 기록은 외부 제공 정보와 따로 보관하므로 외부 제공처에 장애가 생기거나 제공이 중단되어도 책장 배치와 기록은 남습니다.`,
		`회원이 직접 찍거나 고른 사진은 기록과 함께 보관합니다.`,
	}},
	{"(외부 제공 정보)", []string{
		`도서 표지 등 외부 제공 정보는 제공처의 정책 변경 또는 서비스 중단에 따라 변경되거나 표시되지 않을 수 있습니다. 이 경우 제목이 적힌 기본 표지로 대체될 수 있으며, 회원이 작성한 독서 기록과 책장 배치는 별도로 보관됩니다.`,
		`서비스는 외부 제공처의 이용 조건에 따라 표지 그림을 기기에 일시적으로만 저장하고, 오래된 그림은 지웁니다. 지난 연도 책장의 표지도 같은 방식으로 불러옵니다.`,
		`외부 제공 정보의 정확성과 계속 제공은 제공처의 정책을 따릅니다. 서비스는 출처를 함께 표시합니다.`,
	}},
	{"(서비스의 변경과 중단)", []string{
		`서비스는 기능을 바꾸거나 일부를 중단할 수 있습니다. 회원에게 영향이 큰 변경이나 중단은 미리 앱에 알립니다.`,
		`서비스를 끝내야 할 때는 30일 전부터 알리고, 그동안 회원이 기록을 확인할 수 있게 합니다.`,
	}},
	{"(회원의 의무)", []string{
		`회원은 다른 사람의 계정을 쓰거나, 서비스의 정상적인 운영을 방해하거나, 다른 사람의 권리를 침해하는 내용을 공개해서는 안 됩니다.`,
		`책의 문장을 갈피로 남길 때는 개인적인 기록 범위에서 이용하고, 공개할 때는 저작권을 지킵니다.`,
	}},
	{"(책임의 제한)", []string{
		`서비스는 천재지변, 통신 장애, 외부 제공처의 사정처럼 서비스가 막을 수 없는 이유로 생긴 손해에 책임을 지지 않습니다. 다만 서비스의 고의나 과실로 생긴 손해는 그렇지 않습니다.`,
	}},
	{"(문의)", []string{`서비스 이용 문의는 앱의 '내 정보 › 문의하기'로 보내 주세요.`}},
}

// 결제를 켠 서버에서 (계정) 조의 탈퇴 문단 끝에 붙는 문장(ADR-0003 L13: 결제 기록 5년 분리 보관)
const termsPaidAccountNote = ` 다만 유료 서비스의 결제 기록은 관계 법령에 따라 정한 기간 동안 계정과 분리해 보관합니다.`

// 유료 서비스 조(ADR-0003 L14). 결제를 켠 서버에서만 (서비스의 변경과 중단) 앞에 들어간다
var termsPaid = []termsArticle{
	{"(유료 서비스)", []string{
		`서비스는 기본 기능을 무료로 제공하고, 다음 유료 서비스를 제공합니다. 가격과 이용 기간은 구매 화면과 앱 마켓에 표시합니다.`,
		`"책장 한켠 플러스"는 매월 또는 매년 자동으로 갱신되는 구독입니다. 구독하는 동안 유료 벽지와 선반 색 등 구독 화면에 적힌 꾸미기를 쓸 수 있습니다.`,
		`"추가 선반"은 연도별 책장에 선반 칸을 여는 상품입니다. 책장마다 3칸까지는 무료이고, 나머지 3칸은 1칸씩 또는 3칸을 한 번에 결제해 엽니다. 결제한 칸은 그 연도의 책장에서만 열리고, 그 책장에서 계속 쓸 수 있습니다.`,
		`결제는 Apple App Store 또는 Google Play(이하 "앱 마켓")의 결제 수단으로 이루어지며, 결제 처리와 결제 수단 관리는 앱 마켓의 정책을 따릅니다. 서비스는 카드 번호 등 결제 수단 정보를 받지 않습니다.`,
		`유료 서비스는 로그인한 회원 계정에 기록되어 같은 계정으로 로그인한 기기에서 함께 쓸 수 있습니다. 구독은 같은 앱 마켓 계정으로 '구매 복원'을 하면 다른 회원 계정으로 옮길 수 있으며, 한 번에 한 회원 계정에서만 쓸 수 있습니다. 추가 선반은 결제한 회원 계정의 책장에 남고 다른 회원 계정으로 옮기지 않습니다.`,
	}},
	{"(구독의 자동 갱신과 해지)", []string{
		`구독은 해지하지 않으면 이용 기간이 끝날 때마다 같은 주기와 같은 가격으로 자동 결제됩니다. 서비스는 처음 결제할 때 구매 화면에 가격, 결제 주기, 자동 갱신 조건과 해지 방법을 알리고 동의를 받으며, 이 동의를 이후 갱신에 대한 동의로 봅니다.`,
		`연 구독은 갱신일 전에 앱 안 알림함으로 결제 예정 금액, 결제일, 결제 방법과 해지 방법을 알립니다. 월 구독은 매달 결제 전에 따로 알리지 않습니다. 월 구독의 다음 결제일과 결제 금액은 '내 정보 › 구독 관리'에서 언제든 볼 수 있고, 결제 내역은 앱 마켓에서 확인할 수 있습니다.`,
		`구독 해지는 앱 마켓의 구독 관리에서 언제든 할 수 있으며, 앱의 '내 정보 › 구독 관리'에서 바로 이동할 수 있습니다. 다음 결제를 막으려면 갱신일 24시간 전까지 해지해야 합니다.`,
		`해지해도 이미 결제한 이용 기간이 끝날 때까지는 계속 이용할 수 있습니다. 회원탈퇴만으로는 구독이 해지되지 않으므로, 탈퇴 전에 구독을 해지해야 합니다.`,
		`구독 가격을 올릴 때는 미리 알리고 앱 안에서 동의를 받습니다. 동의하지 않으면 지금 이용 기간이 끝날 때 구독이 끝나고 더 결제되지 않습니다.`,
	}},
	{"(유료 서비스에 관한 알림)", []string{
		`서비스는 결제 완료, 갱신 예정, 결제 실패, 환불, 구독 종료처럼 유료 서비스에 관한 일을 앱 안 알림함으로 회원에게 알립니다. 결제 실패, 환불, 구독 종료처럼 중요한 알림은 앱을 열 때 창으로도 보여 줍니다.`,
		`알림함의 알림은 회원 계정에 남아 다른 기기에서도 다시 볼 수 있습니다. 서비스는 이 알림을 전자우편이나 문자메시지로 보내지 않습니다.`,
		`유료 서비스에 관한 약관을 회원에게 불리하게 바꿀 때는 시행일 30일 전에 알림함으로 따로 알리고, 바뀌기 전과 후를 나란히 보여 줍니다.`,
	}},
	{"(청약철회와 환불)", []string{
		`회원은 결제한 날부터 7일 안에 청약을 철회할 수 있습니다. 다만 이미 이용을 시작한 유료 서비스는 「전자상거래 등에서의 소비자보호에 관한 법률」에 따라 청약철회가 제한될 수 있습니다.`,
		`앱 마켓을 통한 결제의 환불은 앱 마켓이 처리합니다. 회원은 '내 정보 › 구독 관리'의 환불 안내를 따라 앱 마켓에 환불을 요청할 수 있으며, 환불 여부와 금액, 시기는 앱 마켓의 정책을 따릅니다.`,
		`미성년자가 법정대리인의 동의 없이 결제한 경우 미성년자 본인이나 법정대리인이 결제를 취소할 수 있습니다.`,
		`환불이 이루어지면 해당 유료 서비스를 더 이용할 수 없습니다. 구독은 종료되고, 추가 선반은 그 연도 책장의 칸이 잠기며 그 선반에 꽂아 둔 책은 '내 책'으로 옮겨 보관합니다. 회원의 기록은 지우지 않습니다.`,
	}},
	{"(유료 서비스 문의와 불만 처리)", []string{
		`결제, 해지, 환불에 관한 문의와 불만은 앱의 '내 정보 › 문의하기'나 '내 정보 › 사업자 정보'에 적힌 전화번호, 전자우편으로 받습니다.`,
		`서비스는 문의를 받은 날부터 3영업일 안에 답하고, 더 걸리면 그 이유와 처리 일정을 알립니다.`,
		`청약철회, 해지, 환불을 요청하는 문의를 받으면 받은 사실을 지체 없이 회신합니다.`,
	}},
}

// termsArticles는 보일 조에 번호를 붙인다. paid면 유료 조가 (서비스의 변경과 중단) 앞에 들어간다(앱 termsArticles와 같은 순서)
func termsArticles(paid bool) []termsArticle {
	list := make([]termsArticle, 0, len(termsBase)+len(termsPaid))
	for _, a := range termsBase {
		if paid && a.Title == "(서비스의 변경과 중단)" {
			list = append(list, termsPaid...)
		}
		if paid && a.Title == "(계정)" {
			paras := append([]string(nil), a.Paras...)
			paras[len(paras)-1] += termsPaidAccountNote
			a = termsArticle{a.Title, paras}
		}
		list = append(list, a)
	}
	for i := range list {
		list[i].Title = fmt.Sprintf("제%d조 %s", i+1, list[i].Title)
	}
	return list
}

// termsShowPaid: 유료 조를 보일지. 결제 스위치(IAP_ENABLED)와 같은 값을 읽는다(앱의 iapOn과 같은 구실).
// 결제 API가 main에 들어오면 스위치를 읽는 함수 하나로 합친다
func termsShowPaid() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("IAP_ENABLED"))) {
	case "1", "true", "on", "yes":
		return true
	}
	return false
}

// 모양은 site/privacy.html과 같다
var termsPage = template.Must(template.New("terms").Parse(`<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>이용약관 · 책장 한켠</title>
<link rel="icon" href="/icon.png">
<style>
:root{--bg:#fff;--ink:#191f28;--sub:#646f7e;--line:#e5e8eb;--accent:#6c534a}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.75 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Pretendard","Noto Sans KR","Malgun Gothic",sans-serif;word-break:keep-all}
main{max-width:720px;margin:0 auto;padding:40px 20px 56px}
h1{font-size:28px;line-height:1.35;margin:0 0 16px}
h2{font-size:19px;margin:36px 0 10px}
p{margin:0 0 12px}
.meta{color:var(--sub);font-size:15px;border-bottom:1px solid var(--line);padding-bottom:16px;margin-bottom:8px}
.meta p{margin:0 0 4px}
a{color:var(--accent)}
nav{margin-bottom:24px;font-size:15px}
</style>
</head>
<body>
<main>
<nav><a href="/">← 책장 한켠</a></nav>
<h1>책장 한켠 · Covebook 이용약관</h1>
<div class="meta">
  <p>시행일은 정식 출시 때 정합니다.</p>
  <p>적용 앱: 책장 한켠 / Covebook (Android·iOS, 앱 ID app.covebook)</p>
  <p>앱 안에서는 '내 정보 › 이용약관'에서 같은 글을 볼 수 있습니다. 개인정보 처리는 <a href="/privacy">개인정보 처리방침</a>을 따릅니다.</p>
</div>
{{range .}}
<h2>{{.Title}}</h2>
{{range .Paras}}<p>{{.}}</p>
{{end}}{{end}}
</main>
</body>
</html>
`))

func renderTerms(paid bool) []byte {
	var b bytes.Buffer
	if err := termsPage.Execute(&b, termsArticles(paid)); err != nil {
		panic(err) // 글과 틀이 코드에 고정되어 있어 시험에서 잡힌다
	}
	return b.Bytes()
}

// terms는 요청마다 스위치를 읽는다(그리는 데 드는 일이 작고, 시험이 t.Setenv로 두 모양을 다 볼 수 있다)
func terms(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=600")
	_, _ = w.Write(renderTerms(termsShowPaid()))
}
