"""把账本（根目录）和行程规划（/plan/）上传到阿里云 OSS（由 GitHub Actions 调用，也可在本机运行）。

需要的环境变量：
  ALIYUN_ACCESS_KEY_ID / ALIYUN_ACCESS_KEY_SECRET  RAM 子账号的 AccessKey（只给这个 Bucket 的写权限）
  OSS_BUCKET     Bucket 名称，例如 travel-aa-ledger
  OSS_ENDPOINT   地域 Endpoint，例如 oss-cn-hongkong.aliyuncs.com
  PLAN_DIR       （可选）Do-Travel-Plan-Page 的本地目录；提供时一起发布到 plan/
用法：python scripts/deploy_oss.py [--dry-run]
内容没变的文件会跳过（比较 MD5 与 OSS 上的 ETag）。
"""
import hashlib
import mimetypes
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# 账本：只发布网页需要的文件；supabase/、overview.md 等不上传
LEDGER_FILES = ["index.html", "旅游AA账本.html"]
LEDGER_DIRS = ["vendor", "templates"]
# 行程规划：发布整个仓库，排除开发用的目录和文件
PLAN_SKIP_DIRS = {".git", ".github", "tests", "scripts", "optional", "functions", "references", "advanced", "schemas", "node_modules"}
PLAN_SKIP_FILES = {"package.json", "package-lock.json", "local-preview-server.mjs", "CNAME", "_headers", "LICENSE", "SKILL.md"}

TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".mjs": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".csv": "text/csv; charset=utf-8",
    ".md": "text/markdown; charset=utf-8",
    ".svg": "image/svg+xml",
    ".webp": "image/webp",
    ".geojson": "application/geo+json",
}


def collect():
    """返回 [(本地路径, OSS key)]"""
    out = [(ROOT / f, f) for f in LEDGER_FILES]
    for d in LEDGER_DIRS:
        out += [(p, p.relative_to(ROOT).as_posix()) for p in sorted((ROOT / d).rglob("*")) if p.is_file()]
    plan_dir = os.environ.get("PLAN_DIR")
    if plan_dir:
        base = Path(plan_dir).resolve()
        if not (base / "index.html").is_file():
            sys.exit(f"PLAN_DIR 不是行程页目录：{base}")
        for p in sorted(base.rglob("*")):
            rel = p.relative_to(base)
            if (not p.is_file() or rel.parts[0] in PLAN_SKIP_DIRS or any(part.startswith(".") for part in rel.parts)
                    or (len(rel.parts) == 1 and (rel.name in PLAN_SKIP_FILES or rel.suffix == ".md"))):
                continue
            out.append((p, "plan/" + rel.as_posix()))
    return out


def headers_for(path: Path, key: str):
    ctype = TYPES.get(path.suffix.lower()) or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    suffix = path.suffix.lower()
    if suffix in (".html", ".json"):
        cache = "no-cache"  # 页面和行程数据：每次向服务器确认，更新后立刻生效
    elif key.startswith("vendor/"):
        cache = "public, max-age=31536000, immutable"  # 文件名带版本号
    else:
        cache = "public, max-age=86400"
    return {"Content-Type": ctype, "Cache-Control": cache, "Content-Disposition": "inline"}


def md5_hex(path: Path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    dry = "--dry-run" in sys.argv
    files = collect()
    if dry:
        for p, key in files:
            print(key, headers_for(p, key)["Content-Type"])
        print(f"共 {len(files)} 个文件")
        return
    import oss2

    need = ["ALIYUN_ACCESS_KEY_ID", "ALIYUN_ACCESS_KEY_SECRET", "OSS_BUCKET", "OSS_ENDPOINT"]
    missing = [k for k in need if not os.environ.get(k)]
    if missing:
        sys.exit("缺少环境变量：" + ", ".join(missing))
    auth = oss2.Auth(os.environ["ALIYUN_ACCESS_KEY_ID"], os.environ["ALIYUN_ACCESS_KEY_SECRET"])
    endpoint = os.environ["OSS_ENDPOINT"]
    if not endpoint.startswith("http"):
        endpoint = "https://" + endpoint
    bucket = oss2.Bucket(auth, endpoint, os.environ["OSS_BUCKET"])
    uploaded = skipped = 0
    for p, key in files:
        headers = headers_for(p, key)
        try:
            meta = bucket.head_object(key)
            same = (meta.etag or "").strip('"').lower() == md5_hex(p) and meta.content_type == headers["Content-Type"]
        except oss2.exceptions.NotFound:
            same = False
        if same:
            skipped += 1
            continue
        bucket.put_object_from_file(key, str(p), headers=headers)
        uploaded += 1
        print("uploaded", key)
    print(f"完成：上传 {uploaded} 个，未变化跳过 {skipped} 个")


if __name__ == "__main__":
    main()
