# Google Maps MCP（行程规划用）

仓库根目录的 `.mcp.json` 接入了 [cablate/mcp-google-map](https://github.com/cablate/mcp-google-map)（固定版本 0.0.69）。
在这个仓库里打开 Claude Code（本机或云端会话），Claude 就能查真实地点、营业时间、评分、路线耗时、多点顺路排序、天气，用来做行程规划、补全地点库。

只开放了和旅行相关的 15 个只读工具（关掉了本地 SEO 排名、海拔、空气质量），减少上下文占用。

## 1. 申请 Google Maps API Key

1. 打开 Google Cloud Console，新建项目并**绑定结算账号**（有每月免费额度，超出会收费）
2. **API 和服务 → 库**，启用：
   - Places API (New)
   - Routes API
   - Geocoding API
   - Time Zone API、Weather API、Maps Static API（可选）
3. **凭据 → 创建凭据 → API 密钥**
4. 编辑这个密钥 → **API 限制**：只勾选上面启用的 API。应用限制选“无”（服务器端调用，不能用 HTTP 引荐来源限制）
5. 建议在 **结算 → 预算和提醒** 设一个月度预算提醒

## 2. 把 Key 交给 Claude（不要贴到聊天里，也不要提交到仓库）

- **Claude Code 云端会话**：会话标题栏的云端环境菜单 → Edit → 添加环境变量 `GOOGLE_MAPS_API_KEY`。之后**新开的会话**会自动加载。
- **本机 Claude Code**：在终端 `export GOOGLE_MAPS_API_KEY=...` 后再运行 `claude`，首次会询问是否信任项目里的 `.mcp.json`，选允许。
- **Claude Desktop**：把 `.mcp.json` 里的 `google-maps` 一段复制到 Claude Desktop 的 MCP 配置中，`GOOGLE_MAPS_API_KEY` 填实际值。

## 3. 检查

```bash
npx -y @cablate/mcp-google-map@0.0.69 doctor          # 不调用 Google，只检查环境
npx -y @cablate/mcp-google-map@0.0.69 doctor --live   # 会发几次计费请求
```

在 Claude Code 里输入 `/mcp` 能看到 `google-maps` 已连接。

## 用法举例

- “把关西熊野行程第 6–11 天京都的景点按区域分组，查营业时间，排出每天顺路的顺序”
- “查和歌山城市酒店到熊野本宫大社开车多久”
- “给地点库里没有地址的地点补上地址、评分、官网”

Google 返回的评论、照片等内容在网页里展示时要注明来源，不要大量长期缓存。
