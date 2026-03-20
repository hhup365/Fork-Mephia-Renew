#!/bin/bash
# ===== 个人配置（通过 GitHub Secrets 注入）=====
: "${DISCORD_TOKEN:?请设置 GitHub Secret: DISCORD_TOKEN}"
: "${SESSION_ID:?请设置 GitHub Secret: SESSION_ID}"

# ===== 公共配置 =====
GUILD_ID="1280090779766886437"
CHANNEL_ID="1312458506976235621"

# ===== 代理配置 =====
if [ -n "$GOST_PROXY" ]; then
  PROXY="-x http://127.0.0.1:8080"
  echo "🛡️ 使用代理模式"
else
  PROXY=""
  echo "🌐 直连模式"
fi

echo "🕐 运行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "🔧 Mephia 续期任务"
echo "========================================"

# ===== 获取 Application ID（slash command 需要） =====
echo "🔍 正在获取频道信息..."

# 获取 /renew 指令的 application_id 和 command_id
COMMANDS=$(curl -s $PROXY \
  "https://discord.com/api/v9/channels/${CHANNEL_ID}/application-commands/search?type=1&query=renew&limit=10" \
  -H "authorization: ${DISCORD_TOKEN}" \
  -H "user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36")

read COMMAND_ID APPLICATION_ID COMMAND_NAME < <(echo "$COMMANDS" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    cmds = data.get('application_commands', [])
    for c in cmds:
        if c.get('name') == 'renew':
            print(c['id'], c['application_id'], c['name'])
            exit()
    print('NOT_FOUND NOT_FOUND NOT_FOUND')
except Exception as e:
    print('NOT_FOUND NOT_FOUND NOT_FOUND')
")

if [ "$COMMAND_ID" = "NOT_FOUND" ]; then
  echo "❌ 未找到 /renew 指令，请检查 Token 或频道权限"
  RESULT="❌ 未找到 /renew 指令"
else
  echo "📌 COMMAND_ID:     $COMMAND_ID"
  echo "🤖 APPLICATION_ID: $APPLICATION_ID"

  # ===== 生成 nonce =====
  NONCE=$(python3 -c "import time; print(str(int((int(time.time()*1000) - 1420070400000) << 22)))")

  # ===== 发送 slash command 交互 =====
  echo "🚀 正在发送 /renew ..."
  RESPONSE=$(curl -s -w "\n%{http_code}" $PROXY \
    -X POST "https://discord.com/api/v9/interactions" \
    -H "authorization: ${DISCORD_TOKEN}" \
    -H "content-type: application/json" \
    -H "user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36" \
    -H "x-discord-locale: zh-CN" \
    -H "x-discord-timezone: Asia/Shanghai" \
    -H "origin: https://discord.com" \
    -H "referer: https://discord.com/channels/${GUILD_ID}/${CHANNEL_ID}" \
    -d "{
      \"type\": 2,
      \"application_id\": \"${APPLICATION_ID}\",
      \"guild_id\": \"${GUILD_ID}\",
      \"channel_id\": \"${CHANNEL_ID}\",
      \"session_id\": \"${SESSION_ID}\",
      \"nonce\": \"${NONCE}\",
      \"data\": {
        \"version\": \"${COMMAND_ID}\",
        \"id\": \"${COMMAND_ID}\",
        \"name\": \"renew\",
        \"type\": 1,
        \"options\": [],
        \"application_command\": {
          \"id\": \"${COMMAND_ID}\",
          \"application_id\": \"${APPLICATION_ID}\",
          \"name\": \"renew\",
          \"type\": 1
        },
        \"attachments\": []
      }
    }")

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | head -n-1)

  if [ "$HTTP_CODE" = "204" ]; then
    echo "✅ 成功！状态码: 204"
    echo "🎉 /renew 指令已成功发送！"
    RESULT="✅ 续期成功！"
  else
    echo "❌ 失败！状态码: ${HTTP_CODE}"
    echo "   响应: ${BODY}"
    case "$HTTP_CODE" in
      429) RESULT="❌ 失败！触发频率限制（rate limit）" ;;
      401) RESULT="❌ 失败！Token 失效，需要重新获取" ;;
      403) RESULT="❌ 失败！无权限" ;;
      *)   RESULT="❌ 失败！状态码: ${HTTP_CODE}" ;;
    esac
  fi
fi

# ===== TG 通知 =====
if [ -n "$TG_BOT" ]; then
  TG_CHAT_ID=$(echo "$TG_BOT" | cut -d',' -f1)
  TG_TOKEN=$(echo "$TG_BOT" | cut -d',' -f2)
  RUN_TIME=$(date '+%Y-%m-%d %H:%M:%S')

  MESSAGE="🔧 Mephia 续期任务
🕐 运行时间: ${RUN_TIME}
📊 续期结果: ${RESULT}"

  curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    -d text="${MESSAGE}" > /dev/null
  echo "📬 TG 通知已发送"
fi

# ===== 最终退出码 =====
if [[ "$RESULT" == ✅* ]]; then
  exit 0
else
  exit 1
fi
