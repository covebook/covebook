#!/bin/bash
# 빛 셰이더를 만든다: 옛 앱(React Native)의 생성기에서 SkSL을 뽑아 → GLSL로 바꿔 shaders/*.frag 에 쓴다.
# 옛 앱 코드는 2026-11-18에 저장소에서 지웠다(그때까지 app/ 자리, 지금 app/은 Flutter 앱). 생성기는 아직 그 코드에 있어서, 지우기 전 마지막 커밋(APP_REF)에서 꺼내 쓴다.
# 같은 jest 실행에서 tool/dump_*.test.ts가 Flutter 시험의 견줌 자료(test/fixtures/*.json, assets/bake_case.json, lib/gen/)도 다시 뽑는다.
# flutter build가 셰이더를 impellerc로 미리 컴파일한다(기기에서 처음 그릴 때 컴파일하지 않는다).
# 빛 식·값을 바꿀 때: 옛 앱 커밋 + tool/rn_light.patch를 푼 사본에서 빛 파일을 고쳐 패치를 다시 만들고 이것을 다시 돌린다(자세히는 tool/README.md).
# 대체 경로(남은 일): 생성기(scene-light-sksl.ts·light-model.ts)를 Dart로 옮기면 node · 옛 커밋 의존이 없어진다.
# 필요한 것: git(옛 커밋), node 22(NODE_BIN), Flutter(FLUTTER_BIN). 옛 앱 node_modules를 따로 받아 둔 곳이 있으면 RN_NODE_MODULES=<폴더>
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
NODE_BIN=${NODE_BIN:-$HOME/.nvm/versions/node/v22.21.0/bin}
FLUTTER_BIN=${FLUTTER_BIN:-$HOME/flutter/bin}

# 옛 앱은 지우기 전 마지막 커밋의 app/을 임시 폴더에 풀어 쓴다. 다른 커밋을 쓰려면 APP_REF=<커밋>, 풀어 둔 폴더를 쓰려면 APP_SRC=<폴더> 로 돌린다
APP_REF=${APP_REF:-4f9e1d989e17a06c4fcd6b76ba910c523559397f}
if [ -z "$APP_SRC" ]; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  git -C "$ROOT/.." archive "$APP_REF" app | tar -x -C "$TMP"
  # node_modules: 받아 둔 곳(RN_NODE_MODULES)이 있으면 빌리고, 없으면 임시 폴더에 새로 깐다(옛 앱 package-lock.json 그대로)
  if [ -n "$RN_NODE_MODULES" ] && [ -d "$RN_NODE_MODULES" ]; then
    ln -s "$RN_NODE_MODULES" "$TMP/app/node_modules"
  else
    (cd "$TMP/app" && PATH=$NODE_BIN:$PATH npm ci --silent)
  fi
  APP_SRC="$TMP/app"
  echo "== 옛 앱: 커밋 $(git -C "$ROOT/.." rev-parse --short "$APP_REF")"
  # Flutter가 고친 빛(tool/rn_light.patch): 옛 앱 빛 파일(조명·스킨 모양·빛 모델·맞추기 값)에 덧대어 만든다.
  # 옛 앱 커밋에 같은 변경이 이미 들어 있으면 건너뛰고, 맞지 않으면 멈춘다(빛이 어긋난 채 만들지 않게)
  if [ -s "$ROOT/tool/rn_light.patch" ] && [ -z "$NO_LIGHT_PATCH" ]; then
    if (cd "$TMP" && patch -p1 -s --dry-run < "$ROOT/tool/rn_light.patch" >/dev/null 2>&1); then
      (cd "$TMP" && patch -p1 -s < "$ROOT/tool/rn_light.patch")
      echo "== Flutter 빛 패치 적용(tool/rn_light.patch)"
    elif (cd "$TMP" && patch -p1 -s -R --dry-run < "$ROOT/tool/rn_light.patch" >/dev/null 2>&1); then
      echo "== Flutter 빛 패치는 옛 앱 커밋에 이미 들어 있다"
    else
      echo "!! tool/rn_light.patch가 옛 앱 커밋과 맞지 않는다: APP_REF를 바꿨으면 패치를 다시 만든다" >&2
      exit 1
    fi
  fi
fi

echo "== SkSL·줄 구성 뽑기 (jest)"
cd "$APP_SRC"
PATH=$NODE_BIN:$PATH npx jest --silent=false \
  --config "{\"preset\":\"jest-expo\",\"rootDir\":\".\",\"testEnvironment\":\"node\",\"modulePaths\":[\"<rootDir>/node_modules\"],\"roots\":[\"$ROOT/tool\"],\"testMatch\":[\"**/dump_sksl.test.ts\",\"**/dump_schema.test.ts\",\"**/dump_bookmark.test.ts\",\"**/dump_reading.test.ts\",\"**/dump_rebinding.test.ts\",\"**/dump_physics.test.ts\",\"**/dump_locked.test.ts\",\"**/dump_qa_seed.test.ts\",\"**/dump_edit.test.ts\"],\"moduleNameMapper\":{\"^@/(.*)$\":\"<rootDir>/src/\$1\"}}" \
  2>&1 | grep -E "^\s+(console.log|\[dump\])|✓|✕|Tests:|Error|Cannot" | sed 's/^ *//'

echo "== GLSL 로 바꾸기"
cd "$ROOT"
PATH=$FLUTTER_BIN:$PATH dart run tool/sksl_to_glsl.dart build/sksl shaders

echo "== 굽기 셰이더 지문(굽기 캐시 열쇠)"
# 굽기 캐시는 같은 열쇠의 그림을 다시 쓴다: 굽기 셰이더가 바뀌면 열쇠도 바뀌어야 업데이트한 폰이 옛 그림을 쓰지 않는다(2026-11-17)
H=$(sha1sum shaders/bake.frag | cut -c1-16)
cat > lib/gen/bake_shader_hash.g.dart <<DART
// 만든 파일(tool/gen_shaders.sh): shaders/bake.frag의 sha1 앞 16자. 손으로 고치지 않는다
const bakeShaderHash = '$H';
DART
echo "[bake] $H"
