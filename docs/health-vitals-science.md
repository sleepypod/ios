# Health Vitals: Science & Implementation Notes

## Data Sources

The Sleepypod pod uses piezoelectric sensors embedded in the mattress cover to detect:
- **Ballistocardiography (BCG)** — micro-movements from heartbeats
- **Respiratory effort** — chest/abdomen movement during breathing

These are converted to heart rate, HRV, and breathing rate by the biometrics pipeline on `sleepypod-core`.

## Heart Rate (HR)

### Measurement
BCG detects the mechanical recoil of the body with each heartbeat. The inter-beat interval (IBI) is extracted from the BCG waveform, and instantaneous HR is calculated as:

```
HR (BPM) = 60 / IBI (seconds)
```

### Normal Ranges
| Context | Range (BPM) | Source |
|---------|-------------|--------|
| Resting (awake) | 60-100 | AHA |
| Sleep (adults) | 40-80 | Ohayon et al., 2004 |
| Deep sleep (N3) | 40-60 | Trinder et al., 2001 |
| REM sleep | 55-90 | Lanfranchi et al., 2007 |

### Filtering
We discard HR values outside 30-200 BPM as physiologically impossible during sleep. Common causes of bad readings:
- Movement artifacts (turning over, getting out of bed)
- Sensor contact issues
- Multiple occupants with overlapping signals

**Reference:** Brüser et al., "Ambient and Unobtrusive Cardiorespiratory Monitoring Techniques," IEEE Reviews in Biomedical Engineering, 2015.

## Heart Rate Variability (HRV)

### Measurement
HRV is the variation in time between consecutive heartbeats (R-R intervals). We use **RMSSD** (Root Mean Square of Successive Differences), which is the standard for short-term HRV measurement:

```
RMSSD = sqrt(mean((RR[i+1] - RR[i])^2))
```

Where RR[i] is the i-th inter-beat interval in milliseconds.

### Normal Ranges
| Age Group | RMSSD (ms) | Source |
|-----------|-----------|--------|
| 20-29 | 20-80 | Nunan et al., 2010 |
| 30-39 | 18-65 | Nunan et al., 2010 |
| 40-49 | 15-55 | Nunan et al., 2010 |
| 50+ | 10-45 | Nunan et al., 2010 |
| During sleep | 20-100+ | Stein & Pu, 2012 |

### Clinical Significance
- **Higher HRV** → better parasympathetic tone, recovery, cardiovascular health
- **Lower HRV** → stress, fatigue, overtraining, or cardiovascular risk
- **Night-to-night trends** are more meaningful than absolute values

**Reference:** Shaffer & Ginsberg, "An Overview of Heart Rate Variability Metrics and Norms," Frontiers in Public Health, 2017.

### Filtering
We discard HRV values > 300ms as likely artifacts. True HRV during sleep rarely exceeds 200ms RMSSD even in young, fit individuals.

## Breathing Rate (BR)

### Measurement
Respiratory rate is derived from the low-frequency component of the BCG/piezo signal. The chest expansion/contraction creates a modulation envelope on the BCG signal:

```
BR (breaths/min) = count(respiratory_cycles) / duration(minutes)
```

### Normal Ranges
| Context | Range (BPM) | Source |
|---------|-------------|--------|
| Awake, resting | 12-20 | WHO |
| Sleep (adults) | 10-18 | Carskadon & Dement, 2011 |
| Deep sleep (N3) | 10-15 | Douglas et al., 1982 |
| REM sleep | 14-22 (irregular) | Douglas et al., 1982 |

### Current Limitation
The sleepypod-core pipeline currently returns a hardcoded breathing rate of 12 BPM. This is a placeholder — real respiratory rate extraction is not yet implemented. See [core#172](https://github.com/sleepypod/core/issues/172).

## Data Smoothing

### Exponential Moving Average (EMA)
We apply EMA for trend lines to reduce noise while preserving physiologically meaningful changes:

```
EMA[t] = α × value[t] + (1 - α) × EMA[t-1]
```

Where α (alpha) controls responsiveness:
- **HR: α = 0.15-0.20** — responsive enough to show sleep stage transitions
- **HRV: α = 0.10** — smoother, HRV is inherently more variable

**Reference:** Roberts, "Digital Smoothing of Physiological Data," Medical & Biological Engineering, 1966.

### Catmull-Rom Spline Interpolation
Swift Charts `.catmullRom` interpolation produces smooth curves that pass through all data points while maintaining C1 continuity. This is preferred over linear interpolation for physiological data because vital signs change gradually — sharp corners are artifacts, not physiology.

**Reference:** Catmull & Rom, "A class of local interpolating splines," Computer Aided Geometric Design, 1974.

### Outlier Detection
We use simple boundary filtering:
- HR: reject if < 30 or > 200 BPM
- HRV: reject if > 300 ms
- BR: reject if < 4 or > 40 BPM

A more sophisticated approach would use the Hampel identifier (median absolute deviation) or IQR-based filtering, but boundary filtering is sufficient for our data quality.

## Zone Annotations

### Heart Rate Zones (Sleep Context)
| Zone | Range (BPM) | Color | Interpretation |
|------|-------------|-------|----------------|
| Deep rest | < 60 | Blue | Likely deep sleep (N3) |
| Normal sleep | 60-100 | Green | Light sleep or REM |
| Elevated | 100-140 | Amber | Possible arousal, movement, or stress |

These are simplified from the 5-zone exercise model (Karvonen method) adapted for sleep context where max HR is not relevant.

### HRV Zones
| Zone | Range (ms) | Color | Interpretation |
|------|-----------|-------|----------------|
| Low | < 30 | Amber | Poor recovery, stress, or fatigue |
| Normal | 30-100 | Green | Healthy parasympathetic activity |
| High | > 100 | Blue | Strong vagal tone, good recovery |

### Breathing Rate Zones
| Zone | Range (BPM) | Interpretation |
|------|-------------|----------------|
| Normal sleep | 12-20 | Expected range |

## Trend Analysis

### Baseline Comparison
We compare recent measurements (last 20 samples) against older baseline (previous 20 samples):

```
delta% = ((recent_avg - baseline_avg) / baseline_avg) × 100
```

- **> +10%**: "Improving" (for HRV) or "Elevated" (for HR)
- **< -10%**: "Declining" (for HRV) or "Recovering" (for HR)
- **Within ±10%**: "Stable"

### Recovery Score (Future)
Combines multiple signals:
```
recovery = f(resting_HR, HRV_vs_baseline, BR_stability)
```

This requires calibrated data and multiple nights of baseline — not implemented until core#172 is resolved.

## References

1. Brüser et al., "Ambient and Unobtrusive Cardiorespiratory Monitoring Techniques," IEEE Reviews in Biomedical Engineering, 2015
2. Shaffer & Ginsberg, "An Overview of Heart Rate Variability Metrics and Norms," Frontiers in Public Health, 2017
3. Nunan et al., "A quantitative systematic review of normal values for short-term HRV," Pacing and Clinical Electrophysiology, 2010
4. Ohayon et al., "Meta-analysis of quantitative sleep parameters," Sleep, 2004
5. Trinder et al., "Sleep and cardiovascular regulation," Pflügers Archiv, 2001
6. Catmull & Rom, "A class of local interpolating splines," Computer Aided Geometric Design, 1974
7. Stein & Pu, "Heart rate variability, sleep and sleep disorders," Sleep Medicine Reviews, 2012
8. Carskadon & Dement, "Normal human sleep: an overview," Principles and Practice of Sleep Medicine, 2011
