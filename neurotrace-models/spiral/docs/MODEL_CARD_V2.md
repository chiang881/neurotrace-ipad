# Parkinson Spiral XGBoost V2 Model Card

## Intended use

This is a lightweight research classifier for the same two spiral tasks and
28 engineered inputs used by V1:

- test `0`: static spiral
- test `1`: dynamic spiral

It is not a medical device and must not be used for diagnosis, exclusion of
disease, treatment, or other clinical decisions.

## Changes from V1

- Random Forest replaced by XGBoost.
- Trees reduced from 500 to 80.
- Maximum tree depth reduced from 4 to 3.
- Class imbalance handled with `scale_pos_weight=0.6`.
- Deployment threshold set to `0.45`.
- Native model stored in XGBoost UBJSON format.
- Existing 28-feature Python/Swift interface retained.

The model uses exact tree splits. On this small dataset they are inexpensive
and avoid histogram split-boundary differences between XGBoost 3.2 and the
Core ML Tools XGBoost converter.

## Hyperparameters

| Parameter | Value |
|---|---:|
| Trees | 80 |
| Maximum depth | 3 |
| Learning rate | 0.05 |
| Minimum child weight | 1 |
| Gamma | 0.05 |
| L1 regularization | 0 |
| L2 regularization | 1 |
| Row sampling | 1.0 |
| Column sampling | 1.0 |
| Tree method | exact |
| Decision threshold | 0.45 |

## Development validation

Leave-one-subject-out validation on the local 40-subject subset:

| Metric | V1 Random Forest | V2 XGBoost |
|---|---:|---:|
| Accuracy | 0.800 | 0.825 |
| Balanced accuracy | 0.773 | 0.807 |
| ROC AUC | 0.864 | 0.875 |
| Sensitivity | 0.880 | 0.880 |
| Specificity | 0.667 | 0.733 |
| Precision | 0.815 | 0.846 |
| F1 | 0.846 | 0.863 |

V2 confusion matrix: 11 true healthy, 4 false positive, 3 false negative, and
22 true PWP predictions.

The hyperparameters and threshold were developed on this cohort. These values
are development estimates and are not an unbiased external validation.

## Robustness check

Repeated stratified 5-fold validation, 10 repeats:

| Metric | V1 Random Forest | V2 XGBoost |
|---|---:|---:|
| Mean ROC AUC | 0.879 | 0.849 |
| Mean balanced accuracy | 0.780 | 0.755 |

This alternate split does not confirm a general performance gain. The cohort
is too small to establish model superiority; the strongest verified V2 gain is
deployment complexity.

## Complexity

| Measure | V1 Random Forest | V2 XGBoost | Reduction |
|---|---:|---:|---:|
| Trees | 500 | 80 | 84.0% |
| Nodes | 5,032 | 464 | 90.8% |
| Leaves | 2,766 | 272 | 90.2% |
| Native model bytes | 604,121 | 69,355 | 88.5% |
| Core ML model bytes | 103,239 | 18,511 | 82.1% |

Core ML and native XGBoost probabilities were checked on all 40 subjects. The
maximum absolute difference was `8.38e-8`.

## Limitations

- Only 40 local subjects are available: 15 healthy and 25 PWP.
- No independent, prospective, or iPad-collected validation cohort exists.
- Threshold selection and hyperparameter exploration used the local cohort.
- Device, demographic, medication-state, and collection-site bias may remain.
- V2 still expects both spiral tasks and must not be used for line or hold-still
  tasks without task-specific training data.

## Required next study

1. Freeze the feature extractor, protocol, hyperparameters, and threshold.
2. Collect an age- and sex-matched iPad cohort using the production workflow.
3. Evaluate the frozen model once on a held-out external site.
4. Report confidence intervals, calibration, subgroup performance, and failure
   rates.
5. Recalibrate or retrain only after the frozen external evaluation is complete.
