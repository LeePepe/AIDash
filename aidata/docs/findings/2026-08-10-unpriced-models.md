# Finding: 两个新模型没有定价，70 行有 token 无成本（2026-08-10）

- **日期**: 2026-08-10
- **状态**: **已解决** —— 决定：不定价，只看 token
- **严重度**: 低（成本口径按设计留 NULL，用量完整可测）
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

## 怎么修（已定：不定价，只看 token）

**决定：这两个模型不进 `dim_model.csv`，`cost_usd` 就留 NULL，用量按 token 衡量。**

理由见上——定价是事实不是猜测，而这两个看名字是内部代号/未公开型号，
没有可查的公开价。编一个数字会让 70 行从「诚实的 NULL」变成
「看起来精确的错数」，后者更危险。

实现：`config.py` 新增 `UNPRICED_MODELS`，`test_no_tokens_without_cost`
只豁免这个**显式名单**里的模型。配套加了 `test_unpriced_models_still_carry_tokens`
——豁免的是**缺价格**，绝不是缺用量，这两个模型的 token 必须照常填满。

名单**故意保持窄**：新出现的无定价模型**应该**继续把门禁弄失败、
大声报出来，而不是悄悄混进豁免集。已做变异验证：把 `terra` 从名单里
拿掉，门禁立刻失败——证明它还会咬人，不是一个永远为真的空门。

哪天拿到真实定价，就把名字从 `UNPRICED_MODELS` 移除、往
`schema/dim_model.csv` 加一行（USD per 1M token），然后：

```bash
python3 cli.py normalize --source raven && python3 cli.py merge
pytest -q tests/test_warehouse_integrity.py
```

## 读数时注意

`gpt-5.6-terra` / `gpt-5.6-luna` 的这些请求**不计入任何美元口径**
（日成本、成本归因、每条 prompt 成本都不含它们），但**完整计入 token 口径**。
所以看成本卡片时，它们是「不可见」的；看 token 用量时是全的。
这是有意的取舍，不是 bug。

## 顺带修掉的两个（已解决，非本 finding 范围）

同一轮 `pytest` 还有 2 个失败，都是**本地 L2 产物 schema 过期**：
`L2_normalize/clean/aidash_events.db` 缺 spec 005 新增的 `card_type` 列，
导致 `behavior/card-interest` 查询 `no such column: card_type`。
重跑 `python3 cli.py normalize --source aidash_events` 即修复，**无需改代码**。

教训：spec 改了 L2 schema 后，本地 clean DB **不会自动重建**，
下一次跑 L4 查询才会以一个看起来像代码 bug 的形式炸出来。
