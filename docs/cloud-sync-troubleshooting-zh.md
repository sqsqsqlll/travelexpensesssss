# 云同步失败排查（travel.sqsqsq.online）

## 先看原因：⚙ 管理 → ☁️ 云同步诊断

诊断会显示云端地址、待上传条数、最近错误，并逐张表检测能否读取，最后给出提示。截图即可定位。

| 诊断里看到 | 原因 | 怎么改 |
| --- | --- | --- |
| `Failed to fetch` / `Load failed` / `NetworkError` | **跨域被拦截**：没有走同域转发（例如在 github.io 等其他地址打开） | 用 travel.sqsqsq.online 打开；或方案 B |
| `401` / `403` / `permission` | 访问密钥或表权限 | WorkBuddy 应用 → 数据库，确认表允许匿名读写 |
| `404` / `does not exist`（只有某张表） | 云端缺表，常见是 **行程表 `ledger_trips`**（v1.2 才加） | 在 WorkBuddy 数据库里建表，字段见下 |
| `column ... does not exist` | 缺字段，常见是账目表的 `trip` | 在 `ledger_transactions` 加文本字段 `trip` |

> **预算项和地点库目前只保存在本机**（导入 trip-data.json 时生成的预算项、地点不会上云），换设备看不到属于预期行为，不是失败。行程本身、账目、成员、设置会上云。

## 同域转发（已内置）

travel.sqsqsq.online 由 Cloudflare Pages 提供，构建时会生成 `_worker.js`（源码 `deploy/pages-worker.js`），把 `/.cloud/*` 转发到 WorkBuddy。页面自动检测到后改走同域，不会再被跨域拦截。

验证：打开 `https://travel.sqsqsq.online/.cloud/database/rest/ledger_settings?select=id&limit=1`，返回 JSON（没带密钥时是 401 的 JSON 错误）就说明转发正常；账本「⚙ 管理 → 云同步诊断」里云端地址应显示「（同域转发）」。

## 方案 B：让 WorkBuddy 允许新域名

在 WorkBuddy 应用设置（访问控制 / 允许的来源 / CORS）里加入 `https://travel.sqsqsq.online`。WorkBuddy 后台不一定提供这个选项。

## 方案 C：继续用 WorkBuddy 原地址

`https://travel-aa-ledger-72643.app.workbuddy.host` 上云同步本来就能用，可以先把那里当作主地址。

## 行程表字段（缺表时用）

`ledger_trips`：`id`（文本，主键）、`name`、`start_date`、`end_date`、`note`（文本）、`ts`（数字）。

## 这次代码里修掉的问题

- 一条记录上传失败时，后面所有记录都卡在队列里不再上传 → 失败的记录会跳过、稍后重试，其他记录照常上传
- 首次拉取云端失败、或“本机数据上云”失败后，后续轮询可能把“云端为空”当真、删掉本机的账目/行程 → 首次同步成功之前不再做删除
- 失败原因记录下来，在诊断里显示
