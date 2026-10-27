#!/usr/bin/env bash
#
# 在 macOS 上把本工程打成未签名 IPA。
#
#   ./scripts/build-ipa.sh                  # 未签名，TrollStore 安装
#   ./scripts/build-ipa.sh --appgroup       # 未签名 + 注入 App Group，小组件可用
#   ./scripts/build-ipa.sh --config Debug   # 指定构建配置
#
# 产物：dist/MGControl-<Config>-unsigned.ipa
#
set -euo pipefail

CONFIG="Release"
WITH_APPGROUP=0
DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-16.0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --appgroup) WITH_APPGROUP=1; shift ;;
    --config)   CONFIG="$2"; shift 2 ;;
    --target)   DEPLOYMENT_TARGET="$2"; shift 2 ;;
    *) echo "未知参数：$1"; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# --- 前置检查 ---------------------------------------------------------------
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误：找不到 xcodebuild，请先安装 Xcode。"
  exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "错误：找不到 xcodegen，执行 brew install xcodegen"
  exit 1
fi

echo "==> Xcode: $(xcodebuild -version | head -1)"
echo "==> 配置: $CONFIG"
echo "==> 部署目标: iOS $DEPLOYMENT_TARGET"

# --- 生成工程 ---------------------------------------------------------------
echo "==> xcodegen generate"
xcodegen generate

# --- 归档（关闭签名）--------------------------------------------------------
echo "==> xcodebuild archive（未签名）"
rm -rf build/App.xcarchive build/DerivedData
mkdir -p build
if ! xcodebuild archive \
  -project MGControl.xcodeproj \
  -scheme MGControl \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' \
  -archivePath build/App.xcarchive \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS="" \
  IPHONEOS_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  2>&1 | tee build/archive.log | tail -25; then
  echo
  echo "==== 编译错误摘要 ===="
  grep -E "error:" build/archive.log | head -20 || echo "（未匹配到 error:，请查看 build/archive.log）"
  echo "==== 完整日志：build/archive.log ===="
  exit 1
fi

APP="$(ls -d build/App.xcarchive/Products/Applications/*.app 2>/dev/null | head -1 || true)"
if [[ -z "$APP" ]]; then
  echo "错误：归档产物中没有 .app，请检查上面的 xcodebuild 输出。"
  exit 1
fi
NAME="$(basename "$APP" .app)"
echo "==> App: $APP"

# --- 组装 Payload -----------------------------------------------------------
echo "==> 组装 Payload"
rm -rf build/pkg
mkdir -p build/pkg/Payload
ditto "$APP" "build/pkg/Payload/$NAME.app"

# --- 可选：注入 App Group ---------------------------------------------------
# 未签名的二进制不带 entitlements，TrollStore 会套用默认模板（不含 App Group），
# 小组件就读不到共享容器。这里显式写入完整 entitlements，让 TrollStore 原样保留。
if [[ "$WITH_APPGROUP" == "1" ]]; then
  if ! command -v ldid >/dev/null 2>&1; then
    echo "错误：--appgroup 需要 ldid，执行 brew install ldid（或从 TrollStore.app 中取）。"
    exit 1
  fi
  ENT="build/appgroup.entitlements"
  cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>application-identifier</key>
	<string>TROLLTROLL.*</string>
	<key>com.apple.developer.team-identifier</key>
	<string>TROLLTROLL</string>
	<key>get-task-allow</key>
	<true/>
	<key>keychain-access-groups</key>
	<array>
		<string>TROLLTROLL.*</string>
		<string>com.apple.token</string>
	</array>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.alanpfx.mgcontrol.shared</string>
	</array>
</dict>
</plist>
PLIST
  echo "==> 注入 App Group entitlements"
  ldid -S"$ENT" "build/pkg/Payload/$NAME.app/$NAME"
  for BIN in build/pkg/Payload/"$NAME".app/PlugIns/*.appex/*; do
    [[ -f "$BIN" && -x "$BIN" ]] || continue
    case "$BIN" in *.plist|*.car|*.png) continue ;; esac
    echo "    - $(basename "$BIN")"
    ldid -S"$ENT" "$BIN"
  done
fi

# --- 修正权限 ---------------------------------------------------------------
# 目录 755、原本可执行的文件 755、其余 644。
# a+rX 的 X 只作用于目录和已有执行位的文件，正好命中这个规则。
chmod -R a+rX build/pkg/Payload
find build/pkg/Payload -type d -exec chmod 755 {} \;

# --- 打包 -------------------------------------------------------------------
mkdir -p dist
OUT="dist/${NAME}-${CONFIG}-unsigned.ipa"
rm -f "$OUT"
( cd build/pkg && zip -qry "$ROOT/$OUT" Payload )

echo
echo "==> 完成：${OUT}（$(du -h "$OUT" | cut -f1)）"
echo "--- 包内结构 ---"
unzip -Z "$OUT" | head -18
