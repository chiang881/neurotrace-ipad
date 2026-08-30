# Main 程序对接伪代码

本文件只描述对接流程，不提供可运行程序。

## 如果主程序已经有 72 维特征

```text
schema = load feature_schema.json
values = Float32[72]

for i in 0..<72:
    featureName = schema.feature_names[i]
    value = upstreamFeatureMap[featureName]
    if value missing or not finite:
        values[i] = Float.nan
    else:
        values[i] = Float32(value)

prediction = coreMLModel.predict(features: values)
score = prediction.classProbability[1]
label = prediction.classLabel
```

## 如果主程序只有原始轨迹

```text
samples = collect test_id 0 and test_id 1
validate units:
    x/y use fixed logical coordinate system
    pressure is 0..1023
    grip_angle is tenths of degree
    timestamp is milliseconds
    z is equivalent to training Z channel

featureMap = extract features exactly as training pipeline
values = order featureMap by feature_schema.json
missing features -> Float.nan
prediction = coreMLModel.predict(features: values)
```

## 禁止事项

```text
Do not reorder features.
Do not replace missing values with 0.
Do not pass pressure 0..1 directly.
Do not pass timestamps in seconds/nanoseconds without conversion.
Do not use Apple Pencil data with this Z-enabled model unless an equivalent Z signal exists.
```
