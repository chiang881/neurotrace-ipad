# Main 程序对接接口包

本目录只放对接材料，不包含主程序实现。

## 目录结构

- `model/ParkinsonXGBoostV2AllCommon.mlmodel`
  - Core ML 模型文件，拖入 Xcode target 后会编译为 `.mlmodelc`。
- `schema/interface_contract.json`
  - 主程序最小输入/输出契约。
- `schema/feature_schema.json`
  - 72 个特征的固定顺序、模型输入名、输出名和元数据。
- `schema/feature_ranges.csv`
  - 每个特征在训练集中的 min/p01/p05/median/p95/p99/max 范围。
- `schema/ParkinsonXGBoostV2AllCommonSchema.swift`
  - Swift 中可直接引用的特征顺序常量。
- `schema/ParkinsonXGBoostV2AllCommon.swift`
  - Xcode 生成的 Core ML Swift wrapper，可选使用。
- `schema/conversion_report.json`
  - XGBoost 到 Core ML 的一致性验证报告。
- `schema/training_metrics.json`
  - all-common 模型训练与交叉验证指标。
- `schema/feature_importance.csv`
  - XGBoost gain/cover/weight 特征重要性。
- `examples/*_feature_vector.json`
  - 已按模型顺序排列的示例输入向量。
- `INPUT_SPEC.md`
  - 原始输入、特征输入、范围、单位和量纲影响说明。

## 主程序最小接入

模型不直接接收原始采样点，而是接收一个 72 维 `Float32` 特征向量：

```text
input name: features
shape: [72]
dtype: Float32
missing: Float.nan
```

输出：

```text
classLabel: Int64
  0 = control pattern
  1 = Parkinson pattern

classProbability: Dictionary<Int64, Double>
  classProbability[1] = Parkinson pattern probability
```

主程序必须按 `schema/feature_schema.json` 或
`schema/ParkinsonXGBoostV2AllCommonSchema.swift` 中的顺序填充向量。不要按字典遍历顺序、CSV 列顺序猜测。

## 推荐接入方式

1. 主程序采集测试 `0` 和测试 `1` 的轨迹。
2. 特征工程模块把轨迹变成 72 个汇总特征。
3. 缺失或无法计算的特征填 `Float.nan`，不要填 `0`。
4. 将 72 个值写入 `MLMultiArray(shape: [72], dataType: .float32)`。
5. 调用 Core ML 模型，读取 `classProbability[1]`。

## 注意

该 `all-common` 模型包含 `Z` 特征。如果主程序运行在纯 Apple Pencil 采集端，Apple Pencil 没有与训练数据同定义的笔尖高度 `Z`，不能简单填 `0` 替代。需要重新训练 `--ipad-compatible` 版本，或在采集端提供等价的 `Z` 信号。

该模型是研究筛查原型，不是临床诊断模型。
