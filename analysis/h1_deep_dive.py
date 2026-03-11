"""
H1シグナルの持続時間上位を詳細分析
クロス前後のH4/H1の状態から共通特徴を探る
"""

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from pathlib import Path

OUTPUT_DIR = Path(__file__).resolve().parent / "output"


def load_all_signals():
    frames = []
    for f in OUTPUT_DIR.glob("sim_*_signals.tsv"):
        df = pd.read_csv(f, sep="\t")
        frames.append(df)
    return pd.concat(frames, ignore_index=True)


def main():
    df = load_all_signals()

    # H1シグナルのみ抽出、データ終端を除外
    h1 = df[(df["Timeframe"] == "H1") & (df["NextCrossAtEnd"] == False)].copy()
    h1 = h1.sort_values("NextCrossBars", ascending=False).reset_index(drop=True)

    print(f"H1 signals (excluding end-of-data): {len(h1)}")
    print(f"\n{'='*100}")
    print("H1 持続時間上位10 — 全カラム俯瞰")
    print(f"{'='*100}\n")

    top_n = min(10, len(h1))
    top = h1.head(top_n)
    bottom = h1.tail(top_n)

    # 見やすい表示用カラム
    display_cols = [
        "Symbol", "Signal", "BarTime", "NextCrossBars",
        "MaxFavorableExcursion", "MaxAdverseExcursion",
        "Close", "ATR",
        # シグナルTF(H1)自身
        "MaDiff", "SlopeFast", "SlopeSlow", "SlopeFastAvg5", "SlopeSlowAvg5",
        # Swing
        "SwingBarIndex", "SwingPrice", "SwingToCrossBars", "SwingToCrossDistance",
        # H4スナップショット
        "H4_FastMA", "H4_SlowMA", "H4_MaDiff", "H4_SlopeFast", "H4_SlopeSlow",
        # H1スナップショット（自TFだが比較用）
        "H1_FastMA", "H1_SlowMA", "H1_MaDiff", "H1_SlopeFast", "H1_SlopeSlow",
    ]

    for i, (_, row) in enumerate(top.iterrows()):
        is_gc = row["Signal"] == "GC"
        direction = "↑" if is_gc else "↓"

        print(f"--- #{i+1} {row['Symbol']} {row['Signal']}{direction} {row['BarTime']} | 持続: {row['NextCrossBars']:.0f} bars ---")
        print(f"  Price:  Close={row['Close']:.5g}  ATR={row['ATR']:.5g}")
        print(f"  MFE={row['MaxFavorableExcursion']:.5g}  MAE={row['MaxAdverseExcursion']:.5g}  MFE/MAE={row['MaxFavorableExcursion']/max(row['MaxAdverseExcursion'],1e-10):.2f}")
        print(f"  H1自身: MaDiff={row['MaDiff']:.5g}  SlopeFast={row['SlopeFast']:.5g}  SlopeSlow={row['SlopeSlow']:.5g}")
        print(f"           SlopeFastAvg5={row['SlopeFastAvg5']:.5g}  SlopeSlowAvg5={row['SlopeSlowAvg5']:.5g}")
        print(f"  Swing:  BarIdx={row['SwingBarIndex']:.0f}  Price={row['SwingPrice']:.5g}  ToCrossBars={row['SwingToCrossBars']:.0f}  Dist={row['SwingToCrossDistance']:.5g}  Dist/ATR={row['SwingToCrossDistance']/max(row['ATR'],1e-10):.3f}")

        # H4の状態
        h4_aligned = (row["H4_MaDiff"] > 0) if is_gc else (row["H4_MaDiff"] < 0)
        h4_slope_aligned = (row["H4_SlopeFast"] > 0) if is_gc else (row["H4_SlopeFast"] < 0)
        print(f"  H4:     MaDiff={row['H4_MaDiff']:.5g}  SlopeFast={row['H4_SlopeFast']:.5g}  SlopeSlow={row['H4_SlopeSlow']:.5g}")
        print(f"           方向一致={'YES' if h4_aligned else 'NO'}  Slope方向={'YES' if h4_slope_aligned else 'NO'}")

        # 正規化指標
        atr = max(row["ATR"], 1e-10)
        print(f"  正規化: MaDiff/ATR={row['MaDiff']/atr:.4f}  H4_MaDiff/ATR={row['H4_MaDiff']/atr:.4f}")
        print()

    # === 上位 vs 下位の統計比較 ===
    print(f"\n{'='*100}")
    print("上位10 vs 下位10 の統計比較")
    print(f"{'='*100}\n")

    def group_stats(grp, label):
        atr_mean = grp["ATR"].mean()
        print(f"  [{label}] n={len(grp)}")
        print(f"    持続bars:      mean={grp['NextCrossBars'].mean():.1f}  median={grp['NextCrossBars'].median():.1f}")
        print(f"    MFE:           mean={grp['MaxFavorableExcursion'].mean():.5g}")
        print(f"    MFE/MAE:       mean={(grp['MaxFavorableExcursion']/grp['MaxAdverseExcursion'].replace(0,np.nan)).mean():.2f}")

        # 方向正規化した値
        def norm_val(row, col):
            return row[col] if row["Signal"] == "GC" else -row[col]

        # H4 MaDiff方向一致率
        h4_aligned_pct = grp.apply(
            lambda r: (r["H4_MaDiff"] > 0) if r["Signal"] == "GC" else (r["H4_MaDiff"] < 0), axis=1
        ).mean() * 100
        print(f"    H4方向一致率:  {h4_aligned_pct:.0f}%")

        # H4 Slope方向一致率
        h4_slope_pct = grp.apply(
            lambda r: (r["H4_SlopeFast"] > 0) if r["Signal"] == "GC" else (r["H4_SlopeFast"] < 0), axis=1
        ).mean() * 100
        print(f"    H4Slope一致率: {h4_slope_pct:.0f}%")

        # H4 MaDiff/ATR (方向正規化)
        h4_madiff_norm = grp.apply(lambda r: norm_val(r, "H4_MaDiff") / max(r["ATR"], 1e-10), axis=1)
        print(f"    H4_MaDiff/ATR: mean={h4_madiff_norm.mean():.4f}  median={h4_madiff_norm.median():.4f}")

        # H4 SlopeFast/ATR (方向正規化)
        h4_slope_norm = grp.apply(lambda r: norm_val(r, "H4_SlopeFast") / max(r["ATR"], 1e-10), axis=1)
        print(f"    H4_Slope/ATR:  mean={h4_slope_norm.mean():.4f}  median={h4_slope_norm.median():.4f}")

        # H1 MaDiff/ATR
        h1_madiff_norm = grp.apply(lambda r: norm_val(r, "MaDiff") / max(r["ATR"], 1e-10), axis=1)
        print(f"    H1_MaDiff/ATR: mean={h1_madiff_norm.mean():.4f}  median={h1_madiff_norm.median():.4f}")

        # H1 SlopeFastAvg5/ATR
        h1_slopeavg_norm = grp.apply(lambda r: norm_val(r, "SlopeFastAvg5") / max(r["ATR"], 1e-10), axis=1)
        print(f"    H1_SlpAvg5/ATR:mean={h1_slopeavg_norm.mean():.4f}  median={h1_slopeavg_norm.median():.4f}")

        # SwingDist/ATR
        swing_dist_atr = grp["SwingToCrossDistance"] / grp["ATR"].replace(0, np.nan)
        print(f"    SwingDist/ATR: mean={swing_dist_atr.mean():.4f}  median={swing_dist_atr.median():.4f}")

        # MaDiff / ATR の絶対値
        madiff_atr_abs = (grp["MaDiff"].abs()) / grp["ATR"].replace(0, np.nan)
        print(f"    |MaDiff|/ATR:  mean={madiff_atr_abs.mean():.4f}  median={madiff_atr_abs.median():.4f}")

    group_stats(top, "上位10(長持続)")
    print()
    group_stats(bottom, "下位10(短持続)")

    # === 全H1シグナルの相関分析 ===
    print(f"\n{'='*100}")
    print("全H1シグナルの相関（NextCrossBars vs 各指標）")
    print(f"{'='*100}\n")

    # 方向正規化カラム追加
    def norm(row, col):
        return row[col] if row["Signal"] == "GC" else -row[col]

    h1["H4_MaDiff_Norm"] = h1.apply(lambda r: norm(r, "H4_MaDiff") / max(r["ATR"], 1e-10), axis=1)
    h1["H4_SlopeFast_Norm"] = h1.apply(lambda r: norm(r, "H4_SlopeFast") / max(r["ATR"], 1e-10), axis=1)
    h1["H4_SlopeSlow_Norm"] = h1.apply(lambda r: norm(r, "H4_SlopeSlow") / max(r["ATR"], 1e-10), axis=1)
    h1["H1_MaDiff_Norm"] = h1.apply(lambda r: norm(r, "MaDiff") / max(r["ATR"], 1e-10), axis=1)
    h1["H1_SlopeFastAvg5_Norm"] = h1.apply(lambda r: norm(r, "SlopeFastAvg5") / max(r["ATR"], 1e-10), axis=1)
    h1["SwingDist_ATR"] = h1["SwingToCrossDistance"] / h1["ATR"].replace(0, np.nan)
    h1["MaDiff_ATR_abs"] = h1["MaDiff"].abs() / h1["ATR"].replace(0, np.nan)

    corr_cols = [
        "H4_MaDiff_Norm", "H4_SlopeFast_Norm", "H4_SlopeSlow_Norm",
        "H1_MaDiff_Norm", "H1_SlopeFastAvg5_Norm",
        "SwingDist_ATR", "MaDiff_ATR_abs",
        "SwingToCrossBars",
    ]

    for col in corr_cols:
        valid = h1[["NextCrossBars", col]].dropna()
        if len(valid) > 3:
            r = valid["NextCrossBars"].corr(valid[col])
            print(f"  NextCrossBars vs {col:<25}: r={r:+.3f}  (n={len(valid)})")

    # MFEとの相関も
    print()
    for col in corr_cols:
        valid = h1[["MaxFavorableExcursion", col]].dropna()
        if len(valid) > 3:
            r = valid["MaxFavorableExcursion"].corr(valid[col])
            print(f"  MFE vs {col:<25}: r={r:+.3f}  (n={len(valid)})")

    # === チャート ===
    fig, axes = plt.subplots(2, 3, figsize=(18, 10))
    fig.suptitle("H1 Signal Deep Dive: What predicts continuation?", fontsize=14)

    # 1. H4_MaDiff_Norm vs NextCrossBars
    ax = axes[0, 0]
    for sym in h1["Symbol"].unique():
        sd = h1[h1["Symbol"] == sym]
        ax.scatter(sd["H4_MaDiff_Norm"], sd["NextCrossBars"], alpha=0.7, s=50, label=sym)
    ax.axvline(0, color="gray", ls="--", alpha=0.5)
    ax.set_xlabel("H4 MaDiff / ATR (direction-normalized)")
    ax.set_ylabel("NextCrossBars")
    ax.set_title("H4 MaDiff vs Duration")
    ax.legend(fontsize=8)

    # 2. H4_SlopeFast_Norm vs NextCrossBars
    ax = axes[0, 1]
    for sym in h1["Symbol"].unique():
        sd = h1[h1["Symbol"] == sym]
        ax.scatter(sd["H4_SlopeFast_Norm"], sd["NextCrossBars"], alpha=0.7, s=50, label=sym)
    ax.axvline(0, color="gray", ls="--", alpha=0.5)
    ax.set_xlabel("H4 SlopeFast / ATR (direction-normalized)")
    ax.set_ylabel("NextCrossBars")
    ax.set_title("H4 Slope vs Duration")
    ax.legend(fontsize=8)

    # 3. H4_MaDiff_Norm vs MFE
    ax = axes[0, 2]
    for sym in h1["Symbol"].unique():
        sd = h1[h1["Symbol"] == sym]
        ax.scatter(sd["H4_MaDiff_Norm"], sd["MaxFavorableExcursion"], alpha=0.7, s=50, label=sym)
    ax.axvline(0, color="gray", ls="--", alpha=0.5)
    ax.set_xlabel("H4 MaDiff / ATR (direction-normalized)")
    ax.set_ylabel("Max Favorable Excursion")
    ax.set_title("H4 MaDiff vs MFE")
    ax.legend(fontsize=8)

    # 4. SwingDist/ATR vs NextCrossBars
    ax = axes[1, 0]
    for sym in h1["Symbol"].unique():
        sd = h1[h1["Symbol"] == sym]
        ax.scatter(sd["SwingDist_ATR"], sd["NextCrossBars"], alpha=0.7, s=50, label=sym)
    ax.set_xlabel("SwingDist / ATR")
    ax.set_ylabel("NextCrossBars")
    ax.set_title("Swing Distance vs Duration")
    ax.legend(fontsize=8)

    # 5. H1 SlopeFastAvg5 vs NextCrossBars
    ax = axes[1, 1]
    for sym in h1["Symbol"].unique():
        sd = h1[h1["Symbol"] == sym]
        ax.scatter(sd["H1_SlopeFastAvg5_Norm"], sd["NextCrossBars"], alpha=0.7, s=50, label=sym)
    ax.axvline(0, color="gray", ls="--", alpha=0.5)
    ax.set_xlabel("H1 SlopeFastAvg5 / ATR (direction-normalized)")
    ax.set_ylabel("NextCrossBars")
    ax.set_title("H1 Slope Acceleration vs Duration")
    ax.legend(fontsize=8)

    # 6. 上位10 vs 下位10 のレーダー的比較 (棒グラフ)
    ax = axes[1, 2]
    metrics = ["H4_MaDiff_Norm", "H4_SlopeFast_Norm", "H1_MaDiff_Norm", "SwingDist_ATR"]
    labels = ["H4 MaDiff", "H4 Slope", "H1 MaDiff", "SwingDist"]
    top_means = [top.apply(lambda r: norm(r, "H4_MaDiff") / max(r["ATR"], 1e-10), axis=1).mean(),
                 top.apply(lambda r: norm(r, "H4_SlopeFast") / max(r["ATR"], 1e-10), axis=1).mean(),
                 top.apply(lambda r: norm(r, "MaDiff") / max(r["ATR"], 1e-10), axis=1).mean(),
                 (top["SwingToCrossDistance"] / top["ATR"].replace(0, np.nan)).mean()]
    bottom_means = [bottom.apply(lambda r: norm(r, "H4_MaDiff") / max(r["ATR"], 1e-10), axis=1).mean(),
                    bottom.apply(lambda r: norm(r, "H4_SlopeFast") / max(r["ATR"], 1e-10), axis=1).mean(),
                    bottom.apply(lambda r: norm(r, "MaDiff") / max(r["ATR"], 1e-10), axis=1).mean(),
                    (bottom["SwingToCrossDistance"] / bottom["ATR"].replace(0, np.nan)).mean()]
    x = np.arange(len(labels))
    w = 0.35
    ax.bar(x - w/2, top_means, w, label="Top10 (long)", color="steelblue")
    ax.bar(x + w/2, bottom_means, w, label="Bottom10 (short)", color="coral")
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=9)
    ax.set_ylabel("Normalized value")
    ax.set_title("Top10 vs Bottom10: Key Metrics")
    ax.legend(fontsize=8)
    ax.axhline(0, color="gray", ls="--", alpha=0.3)

    plt.tight_layout()
    path = OUTPUT_DIR / "h1_deep_dive.png"
    plt.savefig(path, dpi=150)
    print(f"\nChart saved: {path}")
    plt.close()


if __name__ == "__main__":
    main()
