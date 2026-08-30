# Input Specification

## 推荐接口层级

主程序推荐传入原始 Apple Pencil 触点数组，由 `ParkinsonFeatureExtractor`
在本地转换为 28 个 Core ML 特征。不要让主程序手写 28 个特征，除非完全复刻
同一版特征提取算法。

Core ML 模型本体的直接输入是 28 个 `Double` 特征；`swift_core` 已经封装了
从原始触点到这些特征的转换。

## 每个触点的输入字段

| 字段 | 类型 | 推荐来源 | 单位 / 范围 | 必填 |
|---|---|---|---|---|
| `x` | `Double` | `touch.location(in: view).x` | UIKit points，通常 `0...viewWidth` | 是 |
| `y` | `Double` | `touch.location(in: view).y` | UIKit points，通常 `0...viewHeight` | 是 |
| `pressure` | `Double` | `touch.force / touch.maximumPossibleForce` | 无量纲，推荐 `0...1` | 是 |
| `gripAngle` | `Double` | `touch.altitudeAngle` | radians，约 `0...pi/2` | 是 |
| `timestampSeconds` | `Double` | `touch.timestamp` | 秒，必须按时间递增 | 是 |
| `testID` | `Int` | 主程序任务状态 | 静态螺旋 `0`，动态螺旋 `1` | 是 |

`testID = 2` 或其他值不会进入当前模型特征。

## 每次预测需要的数据

| 项目 | 要求 |
|---|---|
| 任务数量 | 必须同时有 `testID = 0` 和 `testID = 1` |
| 样本顺序 | 建议按采集时间追加；时间相同或倒退的点会被忽略 |
| 最低样本数 | 每个 test 至少 3 个严格递增时间点；实际使用建议每段不少于 100 点 |
| 采样方式 | Apple Pencil 必须使用 coalesced touches，保留高频触点 |
| 任务类型 | 只能用于静态螺旋 + 动态螺旋；不能直接用于直线或 hold still |
| 输入数值 | 所有字段必须是有限数值，不能是 NaN 或 infinity |

训练数据中每个螺旋任务的实际范围如下，仅作为参考，不是硬性限制：

| 统计项 | 训练数据范围 |
|---|---:|
| 每段样本数 | `557...9390`，中位数约 `2963` |
| 每段时长 | `5.008...90.582 s`，中位数约 `25.353 s` |
| x 跨度 | `320...595` 数位板单位 |
| y 跨度 | `223...409` 数位板单位 |
| 原始压力 | `1...1023` 数位板单位 |
| 原始角度 | `360...2580` 数据集单位 |

iPad 输入不需要匹配这些原始数值单位；更重要的是采样流程、任务类型和时间单位一致。

## 单位和范围是否会影响结果

会影响，但不同字段影响方式不同。

### 坐标 `x/y`

特征提取会在每个任务内部用轨迹包围盒对角线做归一化，所以：

- 坐标原点变化基本不影响结果。
- `x` 和 `y` 同时乘以同一个比例，通常影响很小。
- 从 points 换成 pixels，如果 `x/y` 使用同一比例，通常影响很小。
- 非等比例缩放会影响结果，例如只压缩 x 或只拉伸 y。
- 螺旋画得太小会让触控噪声被放大，结果会不稳定。
- hold still 这类几乎没有坐标跨度的数据不适合此模型。

### 压力 `pressure`

特征提取会用每段轨迹压力的第 95 百分位做归一化，所以：

- 正比例缩放压力，通常影响较小。
- 绝对压力大小不是模型主要依据。
- 压力随时间的变化形状、压力标准差、压力与速度相关性会影响结果。
- 不建议传原始 `touch.force`；推荐传 `force / maximumPossibleForce`。
- 如果设备没有有效压力，或所有压力几乎恒定，压力相关特征会失真。
- 非线性变换压力，例如平方、截断、分段映射，会改变结果。

### 握笔角 `gripAngle`

特征提取使用相对角度变化，因此线性单位变化影响较小，但来源必须正确：

- 推荐使用 UIKit 的 `altitudeAngle`，单位 radians。
- 不要用 `azimuthAngle` 替代；这是不同含义，会明显改变结果。
- 如果角度长期接近 0，中位数归一化会变得不稳定。
- degrees 与 radians 在纯比例上影响较小，但主程序仍应统一使用 radians。

### 时间 `timestampSeconds`

时间单位会强烈影响结果：

- 必须是秒。
- 可以是系统绝对时间；特征提取会减去每段的第一个时间戳。
- 不能把毫秒当作秒传入，否则时长、速度、加速度都会严重错误。
- 不能把所有点间隔固定成假时间，除非它真实反映采样节奏。
- 采样频率本身会被重采样到 50 Hz，但原始时间戳决定速度和加速度。

### 样本数量和采样频率

模型不直接使用原始点数，特征提取会重采样到 50 Hz；但点太少仍会损失运动细节。

- 推荐保留 `coalescedTouches(for:)` 返回的所有 Pencil 触点。
- 每段 10 秒以上通常会产生足够样本。
- 不建议先对触点做强平滑、抽稀或插值后再传入。

## 28 个 Core ML 特征

如果主程序绕过 `swift_core`，必须按以下名称提供 28 个 `Double`：

```text
static_duration_s
static_normalized_path_length
static_median_speed
static_speed_iqr
static_speed_cv
static_acceleration_rms
static_median_abs_turn_rate
static_spiral_fit_rmse
static_radial_reversal_fraction
static_relative_pressure_mean
static_relative_pressure_std
static_pressure_speed_correlation
static_relative_angle_std
static_median_relative_angle_change
dynamic_duration_s
dynamic_normalized_path_length
dynamic_median_speed
dynamic_speed_iqr
dynamic_speed_cv
dynamic_acceleration_rms
dynamic_median_abs_turn_rate
dynamic_spiral_fit_rmse
dynamic_radial_reversal_fraction
dynamic_relative_pressure_mean
dynamic_relative_pressure_std
dynamic_pressure_speed_correlation
dynamic_relative_angle_std
dynamic_median_relative_angle_change
```

强烈建议不要在主程序中另写这些特征计算逻辑。任何重命名、顺序错误、单位错误或
算法细节差异都会改变模型输出。

## 质量检查建议

主程序提交预测前建议检查：

1. `testID = 0` 和 `testID = 1` 都存在。
2. 每段至少 3 个严格递增时间戳，生产环境建议每段不少于 100 点。
3. 每段 `x/y` 跨度不是 0，且用户确实完成螺旋任务。
4. `timestampSeconds` 单位为秒。
5. `pressure` 在 `0...1` 附近，偶发略高可以接受，但长期异常应提示重采。
6. `gripAngle` 来自 `altitudeAngle`。

## 重要限制

这个接口只适用于第二代螺旋书写研究模型。它不能直接迁移到直线、点按、hold still、
普通签名或其他任务。若主程序要做这些任务，应重新设计特征和重新训练模型。
