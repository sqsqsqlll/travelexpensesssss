"""生成 Cloudflare Pages 的发布目录 dist/：账本在根目录，行程规划在 plan/，_worker.js 负责 /.cloud 同域转发。

Cloudflare Pages 构建命令：bash scripts/build-pages.sh（输出目录 dist）
本机：PLAN_DIR=../do-travel-plan-page python3 scripts/build_site.py
"""
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
# 账本：只发布网页需要的文件；supabase/、docs/、overview.md 等不发布
LEDGER_FILES = ["index.html", "旅游AA账本.html"]
LEDGER_DIRS = ["vendor", "templates"]
# 行程规划：发布整个仓库，排除开发用的目录和文件
PLAN_SKIP_DIRS = {"tests", "scripts", "optional", "functions", "references", "advanced", "schemas", "node_modules"}
PLAN_SKIP_FILES = {"package.json", "package-lock.json", "local-preview-server.mjs", "CNAME", "_headers", "LICENSE", "SKILL.md"}


def collect():
    """返回 [(本地路径, 发布路径)]"""
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
