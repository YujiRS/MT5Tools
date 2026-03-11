"""
GC_DC_SwingNotifier 継続性分析
上位足の状態がシグナルの継続性（持続bars数, MFE/MAE）に影響するかを検証

分析観点:
1. シグナルTFより上位のTFが同方向（MaDiff符号一致）かどうか
2. 上位TFのMaDiff絶対値（乖離幅）の大きさ
3. 上位TFのSlope方向・強さ
4. SlopeFastAvg5 / SlopeSlowAvg5 の加速度
5. SwingToCrossDistance / ATR 比率
"""

import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from pathlib import Path

OUTPUT_DIR = Path(__file__).resolve().parent / "output"

TF_HIERARCHY = ["M5", "M15", "H1", "H4"]


def load_all_signals():
    """全銘柄のシミュレーション結果を統合"""
    frames = []
    for f in OUTPUT_DIR.glob("sim_*_signals.tsv"):
        df = pd.read_csv(f, sep="\t")
        frames.append(df)
    if not frames:
        raise FileNotFoundError("No simulation TSV files found in output/")
    return pd.concat(frames, ignore_index=True)


def get_upper_tfs(tf):
    """指定TFより上位のTFリストを返す"""
    idx = TF_HIERARCHY.index(tf)
    return TF_HIERARCHY[idx + 1:]


def add_derived_columns(df):
    """分析用の派生カラムを追加"""
    # MFE/MAE比率（リスクリワード指標）
    df["MFE_MAE_Ratio"] = df["MaxFavorableExcursion"] / df["MaxAdverseExcursion"].replace(0, np.nan)

    # SwingDistance / ATR 比率
    df["SwingDistATR"] = df["SwingToCrossDistance"] / df["ATR"].replace(0, np.nan)

    # 上位TF同方向フラグ
    for _, row_tf in enumerate(TF_HIERARCHY):
        upper_tfs = get_upper_tfs(row_tf)
        for utl in upper_tfs:
            col = f"{utl}_Aligned"
            # シグナルがGCなら上位TFのMaDiffが正, DCなら負で同方向
            df.loc[df["Timeframe"] == row_tf, col] = df.loc[df["Timeframe"] == row_tf].apply(
                lambda r: (r[f"{utl}_MaDiff"] > 0) if r["Signal"] == "GC"
                          else (r[f"{utl}_MaDiff"] < 0),
                axis=1
            )

    # 全上位TF同方向フラグ
    def all_upper_aligned(row):
        tf = row["Timeframe"]
        upper = get_upper_tfs(tf)
        if not upper:
            return np.nan  # H4は上位なし
        return all(row.get(f"{u}_Aligned", False) for u in upper)

    df["AllUpperAligned"] = df.apply(all_upper_aligned, axis=1)

    # 上位TFのMaDiff絶対値合計（正規化: ATRで割る）
    def upper_madiff_strength(row):
        tf = row["Timeframe"]
        upper = get_upper_tfs(tf)
        if not upper:
            return np.nan
        total = 0
        for u in upper:
            val = row.get(f"{u}_MaDiff", 0)
            if pd.notna(val):
                # GCなら正が順方向、DCなら負が順方向
                if row["Signal"] == "GC":
                    total += val
                else:
                    total -= val  # DCでは符号反転して合算
        return total

    df["UpperMaDiffStrength"] = df.apply(upper_madiff_strength, axis=1)

    return df


def analyze_alignment(df):
    """上位足方向一致 vs 不一致の継続性比較"""
    print("\n" + "=" * 70)
    print("【分析1】上位TF方向一致 vs 不一致")
    print("=" * 70)

    # データ終端のシグナルを除外（NextCrossBarsが不正確）
    df_clean = df[df["NextCrossAtEnd"] == False].copy()

    for tf in ["M5", "M15", "H1"]:  # H4は上位なし
        tf_data = df_clean[df_clean["Timeframe"] == tf]
        if len(tf_data) == 0:
            continue

        aligned = tf_data[tf_data["AllUpperAligned"] == True]
        not_aligned = tf_data[tf_data["AllUpperAligned"] == False]

        print(f"\n--- {tf} ---")
        print(f"  全上位TF同方向: {len(aligned)} signals")
        if len(aligned) > 0:
            print(f"    avg持続bars:  {aligned['NextCrossBars'].mean():.1f}")
            print(f"    avg MFE:      {aligned['MaxFavorableExcursion'].mean():.4f}")
            print(f"    avg MAE:      {aligned['MaxAdverseExcursion'].mean():.4f}")
            print(f"    avg MFE/MAE:  {aligned['MFE_MAE_Ratio'].mean():.2f}")

        print(f"  上位TF逆方向含: {len(not_aligned)} signals")
        if len(not_aligned) > 0:
            print(f"    avg持続bars:  {not_aligned['NextCrossBars'].mean():.1f}")
            print(f"    avg MFE:      {not_aligned['MaxFavorableExcursion'].mean():.4f}")
            print(f"    avg MAE:      {not_aligned['MaxAdverseExcursion'].mean():.4f}")
            print(f"    avg MFE/MAE:  {not_aligned['MFE_MAE_Ratio'].mean():.2f}")

        if len(aligned) > 0 and len(not_aligned) > 0:
            bars_ratio = aligned['NextCrossBars'].mean() / max(not_aligned['NextCrossBars'].mean(), 1)
            mfe_ratio = aligned['MaxFavorableExcursion'].mean() / max(not_aligned['MaxFavorableExcursion'].mean(), 1e-10)
            print(f"  → 持続bars比: {bars_ratio:.2f}x | MFE比: {mfe_ratio:.2f}x")


def analyze_per_upper_tf(df):
    """個別上位TFごとの方向一致効果"""
    print("\n" + "=" * 70)
    print("【分析2】個別上位TFの方向一致効果")
    print("=" * 70)

    df_clean = df[df["NextCrossAtEnd"] == False].copy()

    for tf in ["M5", "M15", "H1"]:
        upper = get_upper_tfs(tf)
        tf_data = df_clean[df_clean["Timeframe"] == tf]
        if len(tf_data) == 0:
            continue

        print(f"\n--- {tf} ({len(tf_data)} signals) ---")
        for u in upper:
            col = f"{u}_Aligned"
            if col not in tf_data.columns:
                continue
            aligned = tf_data[tf_data[col] == True]
            not_aligned = tf_data[tf_data[col] == False]
            print(f"  {u} 同方向: {len(aligned)} / 逆方向: {len(not_aligned)}")
            if len(aligned) > 0 and len(not_aligned) > 0:
                a_bars = aligned['NextCrossBars'].mean()
                n_bars = not_aligned['NextCrossBars'].mean()
                a_mfe = aligned['MaxFavorableExcursion'].mean()
                n_mfe = not_aligned['MaxFavorableExcursion'].mean()
                print(f"    同方向: 持続{a_bars:.1f}bars, MFE={a_mfe:.4f}")
                print(f"    逆方向: 持続{n_bars:.1f}bars, MFE={n_mfe:.4f}")
                print(f"    → 持続比: {a_bars/max(n_bars,1):.2f}x  MFE比: {a_mfe/max(n_mfe,1e-10):.2f}x")


def analyze_slope_acceleration(df):
    """SlopeAvg5（加速度）と継続性の関係"""
    print("\n" + "=" * 70)
    print("【分析3】Slope加速度と継続性")
    print("=" * 70)

    df_clean = df[df["NextCrossAtEnd"] == False].copy()

    # SlopeAvg5の絶対値で3分位に分割
    for tf in TF_HIERARCHY:
        tf_data = df_clean[df_clean["Timeframe"] == tf].copy()
        if len(tf_data) < 6:
            continue

        # 方向正規化: GCならそのまま、DCなら符号反転
        tf_data["NormSlopeFastAvg5"] = tf_data.apply(
            lambda r: r["SlopeFastAvg5"] if r["Signal"] == "GC" else -r["SlopeFastAvg5"], axis=1
        )

        # 3分位
        try:
            tf_data["SlopeQ"] = pd.qcut(tf_data["NormSlopeFastAvg5"], 3, labels=["Low", "Mid", "High"])
        except ValueError:
            continue

        print(f"\n--- {tf} ---")
        for q in ["Low", "Mid", "High"]:
            grp = tf_data[tf_data["SlopeQ"] == q]
            if len(grp) > 0:
                print(f"  SlopeAvg5 {q:>4}: n={len(grp):>3} | 持続={grp['NextCrossBars'].mean():.1f}bars | MFE={grp['MaxFavorableExcursion'].mean():.4f} | MAE={grp['MaxAdverseExcursion'].mean():.4f}")


def analyze_swing_distance(df):
    """SwingDistance/ATR比率と継続性"""
    print("\n" + "=" * 70)
    print("【分析4】SwingDistance/ATR比率と継続性")
    print("=" * 70)

    df_clean = df[(df["NextCrossAtEnd"] == False) & df["SwingDistATR"].notna()].copy()

    for tf in TF_HIERARCHY:
        tf_data = df_clean[df_clean["Timeframe"] == tf].copy()
        if len(tf_data) < 6:
            continue

        try:
            tf_data["DistQ"] = pd.qcut(tf_data["SwingDistATR"], 3, labels=["Near", "Mid", "Far"])
        except ValueError:
            continue

        print(f"\n--- {tf} ---")
        for q in ["Near", "Mid", "Far"]:
            grp = tf_data[tf_data["DistQ"] == q]
            if len(grp) > 0:
                print(f"  SwingDist/ATR {q:>4}: n={len(grp):>3} | 持続={grp['NextCrossBars'].mean():.1f}bars | MFE={grp['MaxFavorableExcursion'].mean():.4f}")


def analyze_upper_madiff_strength(df):
    """上位TF MaDiff合計強度と継続性"""
    print("\n" + "=" * 70)
    print("【分析5】上位TF MaDiff合計強度と継続性")
    print("=" * 70)

    df_clean = df[(df["NextCrossAtEnd"] == False) & df["UpperMaDiffStrength"].notna()].copy()

    for tf in ["M5", "M15", "H1"]:
        tf_data = df_clean[df_clean["Timeframe"] == tf].copy()
        if len(tf_data) < 6:
            continue

        # 正（順方向）vs 負（逆方向）
        positive = tf_data[tf_data["UpperMaDiffStrength"] > 0]
        negative = tf_data[tf_data["UpperMaDiffStrength"] <= 0]

        print(f"\n--- {tf} ---")
        print(f"  上位TF順方向(+): n={len(positive)}")
        if len(positive) > 0:
            print(f"    持続={positive['NextCrossBars'].mean():.1f}bars | MFE={positive['MaxFavorableExcursion'].mean():.4f} | MFE/MAE={positive['MFE_MAE_Ratio'].mean():.2f}")
        print(f"  上位TF逆方向(-): n={len(negative)}")
        if len(negative) > 0:
            print(f"    持続={negative['NextCrossBars'].mean():.1f}bars | MFE={negative['MaxFavorableExcursion'].mean():.4f} | MFE/MAE={negative['MFE_MAE_Ratio'].mean():.2f}")

        # 3分位
        if len(tf_data) >= 6:
            try:
                tf_data["StrQ"] = pd.qcut(tf_data["UpperMaDiffStrength"], 3, labels=["Weak", "Mid", "Strong"])
                print(f"  三分位:")
                for q in ["Weak", "Mid", "Strong"]:
                    grp = tf_data[tf_data["StrQ"] == q]
                    if len(grp) > 0:
                        print(f"    {q:>6}: n={len(grp):>3} | 持続={grp['NextCrossBars'].mean():.1f}bars | MFE={grp['MaxFavorableExcursion'].mean():.4f} | MFE/MAE={grp['MFE_MAE_Ratio'].mean():.2f}")
            except ValueError:
                pass


def create_charts(df):
    """可視化チャート生成"""
    df_clean = df[(df["NextCrossAtEnd"] == False)].copy()

    fig, axes = plt.subplots(2, 2, figsize=(16, 12))
    fig.suptitle("GC/DC Signal Continuation Analysis", fontsize=14)

    # Chart 1: 上位TF Alignment vs NextCrossBars (boxplot by TF)
    ax = axes[0, 0]
    for i, tf in enumerate(["M5", "M15", "H1"]):
        tf_data = df_clean[df_clean["Timeframe"] == tf]
        aligned = tf_data[tf_data["AllUpperAligned"] == True]["NextCrossBars"]
        not_aligned = tf_data[tf_data["AllUpperAligned"] == False]["NextCrossBars"]
        positions = [i * 3, i * 3 + 1]
        bp = ax.boxplot([aligned.dropna(), not_aligned.dropna()],
                        positions=positions, widths=0.7, patch_artist=True)
        bp["boxes"][0].set_facecolor("lightgreen")
        bp["boxes"][1].set_facecolor("lightsalmon")
    ax.set_xticks([0.5, 3.5, 6.5])
    ax.set_xticklabels(["M5", "M15", "H1"])
    ax.set_ylabel("NextCrossBars")
    ax.set_title("Upper TF Aligned (green) vs Not (red): Duration")
    ax.legend(["Aligned", "Not aligned"], loc="upper right")

    # Chart 2: 上位TF Alignment vs MFE/MAE Ratio
    ax = axes[0, 1]
    for i, tf in enumerate(["M5", "M15", "H1"]):
        tf_data = df_clean[df_clean["Timeframe"] == tf]
        aligned = tf_data[tf_data["AllUpperAligned"] == True]["MFE_MAE_Ratio"].clip(upper=10)
        not_aligned = tf_data[tf_data["AllUpperAligned"] == False]["MFE_MAE_Ratio"].clip(upper=10)
        positions = [i * 3, i * 3 + 1]
        bp = ax.boxplot([aligned.dropna(), not_aligned.dropna()],
                        positions=positions, widths=0.7, patch_artist=True)
        bp["boxes"][0].set_facecolor("lightgreen")
        bp["boxes"][1].set_facecolor("lightsalmon")
    ax.set_xticks([0.5, 3.5, 6.5])
    ax.set_xticklabels(["M5", "M15", "H1"])
    ax.set_ylabel("MFE/MAE Ratio (capped at 10)")
    ax.set_title("Upper TF Aligned (green) vs Not (red): Risk/Reward")

    # Chart 3: UpperMaDiffStrength scatter vs NextCrossBars
    ax = axes[1, 0]
    for tf in ["M5", "M15", "H1"]:
        tf_data = df_clean[(df_clean["Timeframe"] == tf) & df_clean["UpperMaDiffStrength"].notna()]
        ax.scatter(tf_data["UpperMaDiffStrength"], tf_data["NextCrossBars"],
                   alpha=0.6, s=30, label=tf)
    ax.axvline(x=0, color="gray", linestyle="--", alpha=0.5)
    ax.set_xlabel("Upper TF MaDiff Strength (normalized)")
    ax.set_ylabel("NextCrossBars")
    ax.set_title("Upper TF Strength vs Duration")
    ax.legend()

    # Chart 4: per-symbol bar chart of aligned vs not
    ax = axes[1, 1]
    symbols = df_clean["Symbol"].unique()
    x = np.arange(len(symbols))
    width = 0.35
    aligned_mfe = []
    not_aligned_mfe = []
    for sym in symbols:
        sym_data = df_clean[(df_clean["Symbol"] == sym) & (df_clean["Timeframe"] != "H4")]
        a = sym_data[sym_data["AllUpperAligned"] == True]["MFE_MAE_Ratio"].mean()
        n = sym_data[sym_data["AllUpperAligned"] == False]["MFE_MAE_Ratio"].mean()
        aligned_mfe.append(a if pd.notna(a) else 0)
        not_aligned_mfe.append(n if pd.notna(n) else 0)
    ax.bar(x - width/2, aligned_mfe, width, label="Aligned", color="lightgreen")
    ax.bar(x + width/2, not_aligned_mfe, width, label="Not aligned", color="lightsalmon")
    ax.set_xticks(x)
    ax.set_xticklabels(symbols, fontsize=9)
    ax.set_ylabel("Avg MFE/MAE Ratio")
    ax.set_title("Per-Symbol: Upper TF Alignment Effect")
    ax.legend()

    plt.tight_layout()
    chart_path = OUTPUT_DIR / "continuation_analysis.png"
    plt.savefig(chart_path, dpi=150)
    print(f"\nChart saved: {chart_path}")
    plt.close()


def analyze_by_symbol(df):
    """銘柄別の分析サマリー"""
    print("\n" + "=" * 70)
    print("【分析6】銘柄別サマリー")
    print("=" * 70)

    df_clean = df[df["NextCrossAtEnd"] == False].copy()

    for symbol in df_clean["Symbol"].unique():
        sym_data = df_clean[df_clean["Symbol"] == symbol]
        print(f"\n--- {symbol} ---")
        for tf in TF_HIERARCHY:
            tf_data = sym_data[sym_data["Timeframe"] == tf]
            if len(tf_data) == 0:
                continue

            if tf != "H4" and "AllUpperAligned" in tf_data.columns:
                aligned = tf_data[tf_data["AllUpperAligned"] == True]
                not_aligned = tf_data[tf_data["AllUpperAligned"] == False]
                a_str = f"Aligned:{len(aligned)}→持続{aligned['NextCrossBars'].mean():.0f}bars,MFE/MAE={aligned['MFE_MAE_Ratio'].mean():.2f}" if len(aligned) > 0 else "Aligned:0"
                n_str = f"Not:{len(not_aligned)}→持続{not_aligned['NextCrossBars'].mean():.0f}bars,MFE/MAE={not_aligned['MFE_MAE_Ratio'].mean():.2f}" if len(not_aligned) > 0 else "Not:0"
                print(f"  {tf:>3}: {a_str} | {n_str}")
            else:
                print(f"  {tf:>3}: n={len(tf_data)} | 持続={tf_data['NextCrossBars'].mean():.0f}bars | MFE/MAE={tf_data['MFE_MAE_Ratio'].mean():.2f}")


def main():
    print("Loading simulation results...")
    df = load_all_signals()
    print(f"Total signals: {len(df)}")

    df = add_derived_columns(df)

    analyze_alignment(df)
    analyze_per_upper_tf(df)
    analyze_slope_acceleration(df)
    analyze_swing_distance(df)
    analyze_upper_madiff_strength(df)
    analyze_by_symbol(df)

    create_charts(df)


if __name__ == "__main__":
    main()
