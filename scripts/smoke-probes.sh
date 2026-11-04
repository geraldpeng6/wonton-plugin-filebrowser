# FileBrowser Quantum：sso=oidc；清单没有 mcp。
SSO=oidc
MCP=0

web_assert() { grep -qi 'filebrowser'; }   # 标准输入：应用真实页面

identity_check() { # 应用自己的 OIDC 端点走完登录，再调自己的“当前用户”接口
  local me
  curl -sS --noproxy '*' -o /dev/null -L -b "$SMOKE_JAR" -c "$SMOKE_JAR" "$SMOKE_WEB_URL/api/auth/oidc/login" ||
    { echo "OIDC 登录链失败"; return 1; }
  me="$(web_get '/api/users?username=self' -H 'Accept: application/json')" || { echo "GET /api/users?username=self 失败：$me"; return 1; }
  jq -e --arg u "$SMOKE_OWNER" '.username == $u and .permissions.admin == true' <<<"$me" >/dev/null ||
    { echo "当前用户不是主人管理员：$me"; return 1; }
}
