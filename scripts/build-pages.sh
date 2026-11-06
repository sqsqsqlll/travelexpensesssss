#!/usr/bin/env bash
# Cloudflare Pages 构建命令（输出目录：dist）
# 拉取行程规划仓库的最新 main，与账本一起生成 dist/
set -euo pipefail
rm -rf _plan
git clone --depth 1 https://github.com/sqsqsqlll/Do-Travel-Plan-Page.git _plan
PLAN_DIR=_plan python3 scripts/build_site.py
