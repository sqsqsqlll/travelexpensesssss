"""把账本静态文件上传到阿里云 OSS（由 GitHub Actions 调用，也可在本机运行）。

需要的环境变量：
  ALIYUN_ACCESS_KEY_ID / ALIYUN_ACCESS_KEY_SECRET  RAM 子账号的 AccessKey（只给这个 Bucket 的写权限）
  OSS_BUCKET     Bucket 名称，例如 travel-aa-ledger
  OSS_ENDPOINT   地域 Endpoint，例如 oss-cn-hongkong.aliyuncs.com
用法：python scripts/deploy_oss.py [--dry-run]
"""
import mimetypes
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# 只发布网页需要的文件；supabase/、overview.md 等不上传
FILES = ["index.html", "旅游AA账本.html"]
DIRS = ["vendor", "templates"]

TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".csv": "text/csv; charset=utf-8",
    ".md": "text/markdown; charset=utf-8",
}


def collect():
    paths = [ROOT / f for f in FILES]
    for d in DIRS:
        paths += sorted(p for p in (ROOT / d).rglob("*") if p.is_file())
    return paths


def headers_for(path: Path):
    ctype = TYPES.get(path.suffix.lower()) or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    # HTML 每次都向服务器确认，保证更新后立刻生效；SDK 文件名带版本号，可长期缓存
    cache = "no-cache" if path.suffix.lower() == ".html" else "public, max-age=86400"
    if path.parent.name == "vendor":
        cache = "public, max-age=31536000, immutable"
    return {"Content-Type": ctype, "Cache-Control": cache, "Content-Disposition": "inline"}


def main():
    dry = "--dry-run" in sys.argv
    files = collect()
    if dry:
        for p in files:
            print(p.relative_to(ROOT).as_posix(), headers_for(p))
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
    for p in files:
        key = p.relative_to(ROOT).as_posix()
        bucket.put_object_from_file(key, str(p), headers=headers_for(p))
        print("uploaded", key)
    print(f"完成：共上传 {len(files)} 个文件")


if __name__ == "__main__":
    main()
