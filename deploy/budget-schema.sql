-- 预算云端同步（Cloudflare D1，绑定名 BUDGET_DB）。_worker.js 第一次收到请求时会自动执行这些语句，这里仅作说明
-- kind：item = 预算项，plan = 预算设定（总预算 / 浮动 / 分类分配）
-- mt：最后修改时间（毫秒）；负数表示已删除（墓碑），payload 为空
CREATE TABLE IF NOT EXISTS ledger_budget (
  kind TEXT NOT NULL,
  id TEXT NOT NULL,
  trip TEXT NOT NULL DEFAULT '',
  mt INTEGER NOT NULL,
  payload TEXT,
  PRIMARY KEY (kind, id)
);
CREATE INDEX IF NOT EXISTS idx_ledger_budget_trip ON ledger_budget(trip);
