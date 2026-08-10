# Finding: 两个新模型没有定价，70 行有 token 无成本（2026-08-10）

- **日期**: 2026-08-10
- **状态**: **待办** —— 需要用户提供定价后补 `schema/dim_model.csv`
- **严重度**: 中（成本类指标偏低报，且会随使用量放大）
- **发现方式**: `pytest` 的 `test_no_tokens_without_cost` 数据质量门禁失败

---

## 一句话结论

`gpt-5.6-terra` 和 `gpt-5.6-luna` 不在 `schema/dim_model.csv` 里，
`_cost()` 查不到价格返回 `None`，于是 **70 行有完整 token 但 `cost_usd IS NULL`**。
所有成本口径（日成本、成本归因、每条 prompt 成本）都因此**偏低**。

## 失败信号

```
tests/test_warehouse_integrity.py::test_no_tokens_without_cost
AssertionError: 70 rows have tokens but no cost
```

这个门禁是 warehouse Phase 4（PR #141）建的六维数据质量门禁之一，
**它按设计正常工作了** —— 新模型一进来就被抓住。

## 明细

| model | client | 行数 | input_tokens | output_tokens |
|---|---|---:|---:|---:|
| `gpt-5.6-terra` | `codex_exec` | 66 | 3,894,915 | 24,448 |
| `gpt-5.6-luna` | `Codex` | 4 | 48,502 | 151 |
| `gpt-5.6-luna` | `codex-tui` | 2 | NULL | NULL |

- 日期分布：`terra` 全部在 **2026-08-05**；`luna` 在 **08-06 / 08-07**。
- 那 2 行 `codex-tui` 的 token 是 NULL，**不在门禁范围内**（门禁只查
  input/output 都非空的行），属于正常留 NULL，不需要处理。
- 量级不小：`terra` 单独就有 **389 万 input token**，按同代 gpt-5.x
  的量级估算是**数美元级别**的漏计——不是可以忽略的尾数。

## 为什么没有自动修

`model_canon()` 对未知名字是**原样透传**（设计如此），所以 canon 不是问题；
问题是 `dim_model.csv` 里**根本没有这两行**。

**我没有替它们编一个价格。** 定价是事实不是猜测：
`adapters/raven.py::_cost()` 只按 `dim_model.csv` 查表，
往表里塞一个臆测的数字会让 70 行从"诚实的 NULL"变成"看起来精确的错数"——
后者更危险，因为它会静默地流进成本归因卡片而不再触发任何门禁。

`gpt-5.6-terra` / `gpt-5.6-luna` 看名字像是内部代号/未公开发布的型号，
**没有可查的公开定价**，所以这一条必须由用户拍板。

## 怎么修（拿到定价后）

在 `aidata/schema/dim_model.csv` 追加两行（单位：USD per 1M token）：

```csv
gpt-5.6-terra,<input>,<output>,<cache_read>,<cache_write>
gpt-5.6-luna,<input>,<output>,<cache_read>,<cache_write>
```

同代 `gpt-5.x` 现有行的形状可作参考（`gpt-5.5` = `1.25,10.00,0.125,0`），
但**不要直接照抄**——除非确认这两个型号同价。

然后重建并验证：

```bash
python3 cli.py normalize --source raven && python3 cli.py merge
pytest -q tests/test_warehouse_integrity.py::test_no_tokens_without_cost
```

## 顺带修掉的两个（已解决，非本 finding 范围）

同一轮 `pytest` 还有 2 个失败，都是**本地 L2 产物 schema 过期**：
`L2_normalize/clean/aidash_events.db` 缺 spec 005 新增的 `card_type` 列，
导致 `behavior/card-interest` 查询 `no such column: card_type`。
重跑 `python3 cli.py normalize --source aidash_events` 即修复，**无需改代码**。

教训：spec 改了 L2 schema 后，本地 clean DB **不会自动重建**，
下一次跑 L4 查询才会以一个看起来像代码 bug 的形式炸出来。
