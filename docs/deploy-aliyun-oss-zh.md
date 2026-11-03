# 部署到阿里云 OSS（自动发布）

合并到 `main` 后，GitHub Actions（`.github/workflows/deploy-aliyun-oss.yml`）会自动把账本上传到阿里云 OSS。
账目数据仍然保存在 WorkBuddy 云端 + 浏览器本机，换托管位置不影响已有数据。

## 先决定地域

域名 `sqsqsq.online` **没有 ICP 备案**：

| 地域 | 能否绑定 sqsqsq.online | 说明 |
| --- | --- | --- |
| 中国内地（杭州、上海等） | ❌ 必须先备案 | OSS 默认域名打开 HTML 会被强制下载，不能当网站用；备案通常需要一台内地的云服务器，审核要 1–3 周 |
| **中国香港（推荐）** | ✅ 无需备案 | 同一个阿里云账号即可，国内访问速度可以接受 |

已经在内地地域建了 Bucket 也没关系：不收费的空 Bucket 可以直接删除，再在中国香港新建一个。

## 第 1 步：创建 Bucket

1. 阿里云控制台 → **对象存储 OSS** → **Bucket 列表** → **创建 Bucket**
2. 名称：例如 `travel-aa-ledger`（全局唯一，记下来）；地域：**中国（香港）**
3. 读写权限：**公共读**（网页需要被所有人访问）。如果提示“阻止公共访问”，先在该 Bucket 的 **权限控制 → 阻止公共访问** 里关闭
4. 进入 Bucket → **数据管理 → 静态页面**：默认首页填 `index.html`，保存

## 第 2 步：创建只能写这个 Bucket 的 AccessKey

1. 控制台 → **RAM 访问控制** → **用户** → **创建用户**，勾选 **OpenAPI 调用访问**，保存好 AccessKey ID / Secret（只显示一次）
2. 给这个用户 **新增授权** → 自定义策略（把 `travel-aa-ledger` 换成你的 Bucket 名）：

```json
{
  "Version": "1",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["oss:PutObject", "oss:GetObject"],
    "Resource": ["acs:oss:*:*:travel-aa-ledger/*"]
  }]
}
```

不要使用主账号的 AccessKey。

## 第 3 步：在 GitHub 填写配置

仓库 → **Settings → Secrets and variables → Actions**：

- **Secrets** 标签页 → New repository secret
  - `ALIYUN_ACCESS_KEY_ID`
  - `ALIYUN_ACCESS_KEY_SECRET`
- **Variables** 标签页 → New repository variable
  - `OSS_BUCKET` = `travel-aa-ledger`
  - `OSS_ENDPOINT` = `oss-cn-hongkong.aliyuncs.com`（内地杭州为 `oss-cn-hangzhou.aliyuncs.com`）

然后到 **Actions → Deploy to Aliyun OSS → Run workflow** 手动跑一次；以后每次合并到 main 会自动发布。
没填配置时这个工作流会直接跳过，不会报错。

## 第 4 步：绑定域名 sqsqsq.online

1. Bucket → **Bucket 配置 → 域名管理 → 绑定域名**，填 `sqsqsq.online`（或子域名，例如 `aa.sqsqsq.online`）
2. 按页面提示到域名的 DNS 服务商添加 CNAME 记录，指向 `<Bucket名>.oss-cn-hongkong.aliyuncs.com`
   - 根域名 `sqsqsq.online` 本身做 CNAME 需要 DNS 支持“CNAME 拉平”（Cloudflare 支持）；不支持就用子域名
3. HTTPS：阿里云 **数字证书管理服务** 可申请免费 DV 证书，签发后在 **域名管理 → 证书托管** 里给这个域名上传/选择证书

打开 `https://sqsqsq.online/` 就能看到账本。

## 常见问题

- **打开后提示无法同步云端**：账本的云端数据库在 WorkBuddy（`travel-aa-ledger-72643.app.workbuddy.host`）。如果它只允许原来的网址跨域访问，需要在 WorkBuddy 应用设置里把新域名加入允许来源；在此之前数据会先保存在本机。
- **更新后没变化**：HTML 设置了 `Cache-Control: no-cache`，刷新即可；如果前面套了 CDN，需要在 CDN 里刷新缓存。
- **GitHub Pages 还要吗**：可以继续保留作为备用地址，两边内容相同。
