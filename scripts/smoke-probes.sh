# shellcheck shell=bash
# FileBrowser Quantum：sso=oidc；清单没有 mcp。

web_assert() { grep -qi 'filebrowser'; }   # 标准输入：应用真实页面

identity_check() { # 应用自己的 OIDC 端点走完登录，再调自己的“当前用户”接口
  local me
  curl -sS --noproxy '*' -o /dev/null -L -b "$SMOKE_JAR" -c "$SMOKE_JAR" "$SMOKE_WEB_URL/api/auth/oidc/login" ||
    { echo "OIDC 登录链失败"; return 1; }
  me="$(web_get '/api/users?username=self' -H 'Accept: application/json')" || { echo "GET /api/users?username=self 失败：$me"; return 1; }
  jq -e --arg u "$SMOKE_OWNER" '.username == $u and .permissions.admin == true' <<<"$me" >/dev/null ||
    { echo "当前用户不是用户管理员：$me"; return 1; }
}

# 数据：「文档」源（读写共享）里的文件就是用户数据。以主人身份走应用自己的 API：往「文档」源根目录
# 上传一个文件名和内容都是标记的文件，重装/升级后经同一通道读回比对。
# 两个钩子都先 dweb --sso 重建完整登录链再调 API：装升级起点后马上就要 data_write，那时 SMOKE_JAR
# 还是空的；核心登录页是 JS 自动提交的隐藏字段表单，plain curl 跟不完（identity_check 能用 plain curl
# 是因为它跑在 probes_web 的 dweb 之后，网关会话已就位）。
_fb_marker_file() { # SMOKE_STATE 在套件里是状态目录（e2e 传的是标记文件本身），标记放对应路径
  if [[ -d "${SMOKE_STATE:-}" ]]; then printf '%s/filebrowser-marker' "$SMOKE_STATE"; else printf '%s' "${SMOKE_STATE:-}.marker"; fi
}

_fb_qs() { # <文件路径>：「文档」源 API 的查询串，源名是中文，路径和源名都要 URL 编码
  jq -rn --arg f "$1" '"path=" + ($f|@uri) + "&source=" + ("文档"|@uri)'
}

data_write() {
  local marker qs reply
  marker="FB-SMOKE-$(date +%s)-$RANDOM"
  qs="$(_fb_qs "/$marker")"
  dweb --sso / >/dev/null 2>&1 || { echo "重建 SSO 会话失败"; return 1; }
  reply="$(web_get "/api/resources?$qs" -H 'Content-Type: application/octet-stream' --data-binary "$marker")" ||
    { echo "上传标记文件 /$marker 失败（会话失效或没写权限？）：$reply"; return 1; }
  reply="$(web_get "/api/resources/download?$qs")" ||
    { echo "上传后当场读不回 /$marker：$reply"; return 1; }
  [[ "$reply" == "$marker" ]] || { echo "上传后读回内容对不上：期待 $marker，看到 $(head -c 200 <<<"$reply")"; return 1; }
  printf '%s' "$marker" >"$(_fb_marker_file)" || { echo "写不进状态文件 $(_fb_marker_file)"; return 1; }
  echo "已上传标记文件 /$marker 到「文档」源并读回核对"
}

data_check() {
  local marker qs reply
  marker="$(cat "$(_fb_marker_file)" 2>/dev/null)" || { echo "没有 data_write 留下的标记"; return 1; }
  [[ -n "$marker" ]] || { echo "标记是空的"; return 1; }
  qs="$(_fb_qs "/$marker")"
  dweb --sso / >/dev/null 2>&1 || { echo "重建 SSO 会话失败"; return 1; }
  reply="$(web_get "/api/resources/download?$qs")" ||
    { echo "读不回标记文件 /$marker（数据丢了？）：$reply"; return 1; }
  [[ "$reply" == "$marker" ]] || { echo "标记对不上：期待 $marker，看到 $(head -c 200 <<<"$reply")"; return 1; }
  echo "读回标记一致（$marker），「文档」源里的标记文件还在"
}
