# Main Program Interface Package

这个文件夹只整理主程序对接材料，不包含完整 App 或业务程序。

## 文件清单

| 路径 | 用途 |
|---|---|
| `model/ParkinsonSpiralXGBV2.mlmodel` | 给 Xcode / Core ML 使用的第二代模型 |
| `swift_core/HandwritingSample.swift` | 主程序需要传入的单个触点数据结构 |
| `swift_core/ParkinsonFeatureExtractor.swift` | 将原始触点转换为模型需要的 28 个特征 |
| `swift_core/ParkinsonSpiralPredictor.swift` | Core ML 推理封装，支持 V2 阈值 |
| `example/SpiralCanvasView.swift` | Apple Pencil 采样字段映射参考 |
| `docs/INPUT_SPEC.md` | 输入字段、范围、单位和影响说明 |
| `docs/MODEL_CARD_V2.md` | 模型用途、指标、限制 |
| `docs/hyperparameters.json` | V2 参数与决策阈值 |
| `docs/metrics.json` | V2 本地验证结果 |

## 主程序对接顺序

1. 把 `model/ParkinsonSpiralXGBV2.mlmodel` 加入 iOS target。
2. 把 `swift_core` 下 3 个 Swift 文件加入同一个 target，或放入主程序自己的模型模块。
3. 主程序采集两段螺旋触点数据：静态螺旋 `testID = 0`，动态螺旋 `testID = 1`。
4. 将两段样本合并后交给 `ParkinsonSpiralPredictor`。
5. V2 使用 `decisionThreshold = 0.45`。输出只能作为研究模型结果，不可作为诊断。

## 输出

`ParkinsonSpiralPredictor` 输出：

| 字段 | 类型 | 含义 |
|---|---|---|
| `label` | `String` | 按阈值后的 `Healthy` 或 `Parkinson` |
| `parkinsonProbability` | `Double` | 模型输出的 Parkinson 概率，范围 `0...1` |
| `classProbabilities` | `[String: Double]` | `Healthy` 与 `Parkinson` 的概率字典 |

注意：`Parkinson` 是模型类别名，不等于医学诊断。
