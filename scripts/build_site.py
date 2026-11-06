"""生成 Cloudflare Pages 的发布目录 dist/：账本在根目录，行程规划在 plan/，_worker.js 负责 /.cloud 同域转发。

Cloudflare Pages 构建命令：bash scripts/build-pages.sh（输出目录 dist）
本机：PLAN_DIR=../do-travel-plan-page python3 scripts/build_site.py
文件清单与阿里云 OSS 部署（scripts/deploy_oss.py）共用。
"""
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from deploy_oss import ROOT, collect  # noqa: E402

DIST = ROOT / "dist"


def main():
    if DIST.exists():
        shutil.rmtree(DIST)
    files = collect()
    for src, key in files:
        dest = DIST / key
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest)
    shutil.copyfile(ROOT / "deploy" / "pages-worker.js", DIST / "_worker.js")
    plan = sum(1 for _, key in files if key.startswith("plan/"))
    if plan == 0:
        print("警告：没有行程规划文件（未设置 PLAN_DIR），/plan/ 不会发布")
    print(f"dist/ 已生成：共 {len(files)} 个文件（行程规划 {plan} 个）+ _worker.js")


if __name__ == "__main__":
    main()
