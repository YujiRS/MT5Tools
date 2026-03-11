"""
GC_DC_SwingNotifier シミュレーション
M1 OHLC CSV → 各TFにリサンプル → EMA13/21クロス検出(3フィルタ) → TSV + 継続性メトリクス

仕様書準拠: docs/GC_DC_SwingNotifier_spec.md
"""

import pandas as pd
import numpy as np
import os
import sys
from pathlib import Path

# === パラメータ（仕様書デフォルト値） ===
EMA_FAST = 13
EMA_SLOW = 21
SWING_STRENGTH = 5
SWING_WINDOWS = {"M5": 5, "M15": 6, "H1": 8, "H4": 10}
ATR_PERIOD = 14
SLOPE_AVG_BARS = 5

TF_RESAMPLE = {
    "M5":  "5min",
    "M15": "15min",
    "H1":  "1h",
    "H4":  "4h",
}


def load_m1_csv(filepath):
    """MT5エクスポートのM1 CSVを読み込む"""
    df = pd.read_csv(
        filepath, sep="\t",
        names=["date", "time", "open", "high", "low", "close", "tickvol", "vol", "spread"],
        skiprows=1,
    )
    df["datetime"] = pd.to_datetime(df["date"] + " " + df["time"], format="%Y.%m.%d %H:%M:%S")
    df = df.set_index("datetime").sort_index()
    return df[["open", "high", "low", "close", "spread"]]


def resample_ohlc(m1_df, rule):
    """M1データを上位足にリサンプル"""
    ohlc = m1_df.resample(rule).agg({
        "open":   "first",
        "high":   "max",
        "low":    "min",
        "close":  "last",
        "spread": "last",
    }).dropna(subset=["open"])
    return ohlc


def calc_ema(series, period):
    """EMAを計算（MT5互換: 全データ使用）"""
    return series.ewm(span=period, adjust=False).mean()


def calc_atr(high, low, close, period=14):
    """ATR(period)を計算"""
    prev_close = close.shift(1)
    tr = pd.concat([
        high - low,
        (high - prev_close).abs(),
        (low - prev_close).abs(),
    ], axis=1).max(axis=1)
    return tr.ewm(span=period, adjust=False).mean()


def is_swing_high(highs, center, strength):
    """Fractal方式 Swing High判定（等値は不成立）"""
    if center - strength < 0 or center + strength >= len(highs):
        return False
    center_val = highs[center]
    for i in range(1, strength + 1):
        if highs[center - i] >= center_val:
            return False
        if highs[center + i] >= center_val:
            return False
    return True


def is_swing_low(lows, center, strength):
    """Fractal方式 Swing Low判定（等値は不成立）"""
    if center - strength < 0 or center + strength >= len(lows):
        return False
    center_val = lows[center]
    for i in range(1, strength + 1):
        if lows[center - i] <= center_val:
            return False
        if lows[center + i] <= center_val:
            return False
    return True


def detect_signals(tf_df, tf_name, swing_window):
    """
    1つのTFに対してGC/DCシグナルを検出
    MQL5のCheckTimeframe()を忠実に再現

    Returns: list of signal dicts
    """
    fast_ema = calc_ema(tf_df["close"], EMA_FAST).values
    slow_ema = calc_ema(tf_df["close"], EMA_SLOW).values
    atr_vals = calc_atr(tf_df["high"], tf_df["low"], tf_df["close"], ATR_PERIOD).values
    highs = tf_df["high"].values
    lows = tf_df["low"].values
    closes = tf_df["close"].values
    spreads = tf_df["spread"].values
    times = tf_df.index

    signals = []
    last_cross_dir = 0  # 同方向クロス抑制

    # MQL5ではshift[0]=未確定足, shift[1]=最新確定足, shift[2]=その前
    # シミュレーションでは全て確定済みなので、i=現在バー, shift[1]=i-1, shift[2]=i-2
    # ただしリアルタイムの"最新確定足"を再現するため、
    # 各バーiについて「shift[1]=i, shift[2]=i-1」として判定する
    # （iが確定した時点でCheckTimeframeが呼ばれる想定）

    min_start = max(EMA_SLOW + 10, swing_window + SWING_STRENGTH * 2 + 5, SLOPE_AVG_BARS + 5)

    for i in range(min_start, len(tf_df)):
        # shift[1] = i-1 (最新確定足), shift[2] = i-2 (その前)
        # MQL5のCopyBufferは[0]=最新, [1]=1本前... の降順
        # ここでは shift[1]=i-1, shift[2]=i-2 とする
        s1 = i - 1  # 確定足
        s2 = i - 2  # その前

        # クロス判定
        cross_gc = (fast_ema[s2] < slow_ema[s2]) and (fast_ema[s1] > slow_ema[s1])
        cross_dc = (fast_ema[s2] > slow_ema[s2]) and (fast_ema[s1] < slow_ema[s1])

        if not cross_gc and not cross_dc:
            continue

        # 方向性フィルター
        slope_fast = fast_ema[s1] - fast_ema[s2]
        slope_slow = slow_ema[s1] - slow_ema[s2]

        if cross_gc and (slope_fast <= 0 or slope_slow <= 0):
            continue
        if cross_dc and (slope_fast >= 0 or slope_slow >= 0):
            continue

        # Swing近辺フィルター
        # MQL5では配列が降順(shift[0]が最新)で、center=SwingStrength〜swWindowを走査
        # シミュレーションでは昇順なので、s1からの相対オフセットで考える
        # MQL5のshift[s] はクロスバー(shift[1])からs本前 → インデックス = s1 - s + 1
        # ただしMQL5ではshift[0]が最新で、CheckTimeframe時のshift基準は最新バー
        # つまりshift[1]=確定足, shift[SwingStrength]は確定足からSwingStrength-1本前
        # 実際のコード: for(s = SwingStrength; s <= swWindow; s++) IsSwingLow(low, s, ...)
        # ここでlowは[0]=最新の降順、sはそのインデックス
        # シミュレーション: 未確定足=i, shift[0]=i, shift[1]=i-1, shift[s]=i-s
        swing_bar_idx = -1
        swing_price = 0.0

        if cross_gc:
            for s in range(SWING_STRENGTH, swing_window + 1):
                actual_idx = i - s  # shift[s]に対応する実インデックス
                if actual_idx - SWING_STRENGTH < 0 or actual_idx + SWING_STRENGTH >= len(lows):
                    continue
                if is_swing_low(lows, actual_idx, SWING_STRENGTH):
                    swing_bar_idx = s
                    swing_price = lows[actual_idx]
                    break
        else:  # cross_dc
            for s in range(SWING_STRENGTH, swing_window + 1):
                actual_idx = i - s
                if actual_idx - SWING_STRENGTH < 0 or actual_idx + SWING_STRENGTH >= len(highs):
                    continue
                if is_swing_high(highs, actual_idx, SWING_STRENGTH):
                    swing_bar_idx = s
                    swing_price = highs[actual_idx]
                    break

        if swing_bar_idx < 0:
            continue

        # 同方向クロス抑制
        current_dir = 1 if cross_gc else -1
        if last_cross_dir == current_dir:
            continue
        last_cross_dir = current_dir

        # SlopeAvg5
        n = SLOPE_AVG_BARS
        slope_fast_avg5 = (fast_ema[s1] - fast_ema[s1 - n]) / n if s1 - n >= 0 else np.nan
        slope_slow_avg5 = (slow_ema[s1] - slow_ema[s1 - n]) / n if s1 - n >= 0 else np.nan

        sig = {
            "bar_index": s1,  # 確定足のインデックス（継続性計算用）
            "signal": "GC" if cross_gc else "DC",
            "tf": tf_name,
            "bar_time": times[s1],
            "close": closes[s1],
            "high": highs[s1],
            "low": lows[s1],
            "fast_ma1": fast_ema[s1],
            "fast_ma2": fast_ema[s2],
            "slow_ma1": slow_ema[s1],
            "slow_ma2": slow_ema[s2],
            "ma_diff": fast_ema[s1] - slow_ema[s1],
            "slope_fast": slope_fast,
            "slope_slow": slope_slow,
            "slope_fast_avg5": slope_fast_avg5,
            "slope_slow_avg5": slope_slow_avg5,
            "swing_bar_index": swing_bar_idx,
            "swing_price": swing_price,
            "swing_to_cross_bars": swing_bar_idx - 1,
            "swing_to_cross_distance": abs(closes[s1] - swing_price),
            "atr": atr_vals[s1] if s1 < len(atr_vals) else np.nan,
            "spread": spreads[s1] if s1 < len(spreads) else np.nan,
        }
        signals.append(sig)

    return signals, fast_ema, slow_ema


def add_cross_tf_snapshots(signals, all_tf_data):
    """各シグナルに他TFのMAスナップショットを付与"""
    for sig in signals:
        sig_time = sig["bar_time"]
        for tf_name in ["M5", "M15", "H1", "H4"]:
            if tf_name not in all_tf_data:
                for col in ["FastMA", "SlowMA", "MaDiff", "SlopeFast", "SlopeSlow"]:
                    sig[f"{tf_name}_{col}"] = np.nan
                continue

            tf_df, fast_ema, slow_ema = all_tf_data[tf_name]

            # シグナル時刻以前の最新バーを取得（shift[0]相当）
            mask = tf_df.index <= sig_time
            if mask.sum() < 2:
                for col in ["FastMA", "SlowMA", "MaDiff", "SlopeFast", "SlopeSlow"]:
                    sig[f"{tf_name}_{col}"] = np.nan
                continue

            idx = mask.sum() - 1  # 最新バーのインデックス
            sig[f"{tf_name}_FastMA"] = fast_ema[idx]
            sig[f"{tf_name}_SlowMA"] = slow_ema[idx]
            sig[f"{tf_name}_MaDiff"] = fast_ema[idx] - slow_ema[idx]
            sig[f"{tf_name}_SlopeFast"] = fast_ema[idx] - fast_ema[idx - 1]
            sig[f"{tf_name}_SlopeSlow"] = slow_ema[idx] - slow_ema[idx - 1]


def add_continuation_metrics(signals, all_tf_data):
    """
    各シグナルに継続性メトリクスを追加:
    - next_cross_bars: 同TFで次のクロス（逆方向）が発生するまでのバー数
    - max_favorable_excursion: シグナル方向への最大順行幅（pips相当）
    - max_adverse_excursion: シグナル逆方向への最大逆行幅
    """
    # TFごとにシグナルをグループ化
    tf_signals = {}
    for sig in signals:
        tf_signals.setdefault(sig["tf"], []).append(sig)

    for tf_name, tf_sigs in tf_signals.items():
        tf_df, fast_ema, slow_ema = all_tf_data[tf_name]
        closes = tf_df["close"].values
        highs = tf_df["high"].values
        lows = tf_df["low"].values
        total_bars = len(tf_df)

        for i, sig in enumerate(tf_sigs):
            bar_idx = sig["bar_index"]
            is_gc = sig["signal"] == "GC"
            entry_price = sig["close"]

            # 次の逆方向クロスまでのバー数を探す
            # （同TF内の次のシグナルは必ず逆方向: 同方向抑制があるため）
            if i + 1 < len(tf_sigs):
                next_sig = tf_sigs[i + 1]
                next_cross_bars = next_sig["bar_index"] - bar_idx
            else:
                next_cross_bars = total_bars - 1 - bar_idx  # データ終端まで

            sig["next_cross_bars"] = next_cross_bars
            sig["next_cross_at_end"] = (i + 1 >= len(tf_sigs))  # データ終端フラグ

            # 最大順行幅・最大逆行幅（次クロスまでの区間）
            end_idx = min(bar_idx + next_cross_bars + 1, total_bars)
            segment_highs = highs[bar_idx + 1:end_idx]
            segment_lows = lows[bar_idx + 1:end_idx]

            if len(segment_highs) == 0:
                sig["max_favorable_excursion"] = 0.0
                sig["max_adverse_excursion"] = 0.0
                continue

            if is_gc:
                # GC: 上昇方向が順行
                sig["max_favorable_excursion"] = float(np.max(segment_highs) - entry_price)
                sig["max_adverse_excursion"] = float(entry_price - np.min(segment_lows))
            else:
                # DC: 下降方向が順行
                sig["max_favorable_excursion"] = float(entry_price - np.min(segment_lows))
                sig["max_adverse_excursion"] = float(np.max(segment_highs) - entry_price)


def run_simulation(symbol, m1_filepath, output_dir):
    """1銘柄のシミュレーション実行"""
    print(f"\n=== {symbol} ===")
    print(f"Loading: {m1_filepath}")
    m1_df = load_m1_csv(m1_filepath)
    print(f"M1 bars: {len(m1_df)} ({m1_df.index[0]} ~ {m1_df.index[-1]})")

    # 各TFにリサンプル & EMA計算
    all_tf_data = {}  # {tf_name: (df, fast_ema, slow_ema)}
    all_signals = []

    for tf_name, rule in TF_RESAMPLE.items():
        tf_df = resample_ohlc(m1_df, rule)
        print(f"  {tf_name}: {len(tf_df)} bars")

        sw = SWING_WINDOWS[tf_name]
        sigs, fast_ema, slow_ema = detect_signals(tf_df, tf_name, sw)
        all_tf_data[tf_name] = (tf_df, fast_ema, slow_ema)
        all_signals.extend(sigs)
        print(f"    Signals: {len(sigs)} (GC: {sum(1 for s in sigs if s['signal']=='GC')}, DC: {sum(1 for s in sigs if s['signal']=='DC')})")

    # 他TFスナップショット付与
    add_cross_tf_snapshots(all_signals, all_tf_data)

    # 継続性メトリクス追加
    add_continuation_metrics(all_signals, all_tf_data)

    # 時刻順ソート
    all_signals.sort(key=lambda s: s["bar_time"])

    # TSV出力
    if all_signals:
        df_out = signals_to_dataframe(all_signals, symbol)
        tsv_path = os.path.join(output_dir, f"sim_{symbol}_signals.tsv")
        df_out.to_csv(tsv_path, sep="\t", index=False)
        print(f"  Output: {tsv_path} ({len(df_out)} rows)")

    return all_signals, all_tf_data


def signals_to_dataframe(signals, symbol):
    """シグナルリストを仕様準拠の43カラム + 追加メトリクスのDataFrameに変換"""
    rows = []
    for sig in signals:
        row = {
            "LogTime": sig["bar_time"].strftime("%Y.%m.%d %H:%M:%S"),
            "Symbol": symbol,
            "Signal": sig["signal"],
            "Timeframe": sig["tf"],
            "BarTime": sig["bar_time"].strftime("%Y.%m.%d %H:%M"),
            "Close": sig["close"],
            "High": sig["high"],
            "Low": sig["low"],
            "FastMA1": sig["fast_ma1"],
            "FastMA2": sig["fast_ma2"],
            "SlowMA1": sig["slow_ma1"],
            "SlowMA2": sig["slow_ma2"],
            "MaDiff": sig["ma_diff"],
            "SlopeFast": sig["slope_fast"],
            "SlopeSlow": sig["slope_slow"],
            "SlopeFastAvg5": sig["slope_fast_avg5"],
            "SlopeSlowAvg5": sig["slope_slow_avg5"],
            "SwingBarIndex": sig["swing_bar_index"],
            "SwingPrice": sig["swing_price"],
            "SwingToCrossBars": sig["swing_to_cross_bars"],
            "SwingToCrossDistance": sig["swing_to_cross_distance"],
            "ATR": sig["atr"],
            "Spread": sig["spread"],
        }
        # 他TFスナップショット
        for tf in ["M5", "M15", "H1", "H4"]:
            for col in ["FastMA", "SlowMA", "MaDiff", "SlopeFast", "SlopeSlow"]:
                row[f"{tf}_{col}"] = sig.get(f"{tf}_{col}", np.nan)

        # 追加メトリクス
        row["NextCrossBars"] = sig["next_cross_bars"]
        row["NextCrossAtEnd"] = sig["next_cross_at_end"]
        row["MaxFavorableExcursion"] = sig["max_favorable_excursion"]
        row["MaxAdverseExcursion"] = sig["max_adverse_excursion"]

        rows.append(row)

    return pd.DataFrame(rows)


def main():
    dat_dir = Path(__file__).resolve().parent.parent / "dat"
    output_dir = Path(__file__).resolve().parent / "output"
    output_dir.mkdir(exist_ok=True)

    csv_files = {
        "BTCUSD#": dat_dir / "BTCUSD#_M1_202512010000_202602270000.csv",
        "USDJPY#": dat_dir / "USDJPY#_M1_202512010000_202602270000.csv",
        "GOLD#":   dat_dir / "GOLD#_M1_202509010100_202511282139.csv",
    }

    all_results = {}
    for symbol, filepath in csv_files.items():
        if not filepath.exists():
            print(f"Skip: {filepath} not found")
            continue
        sigs, tf_data = run_simulation(symbol, filepath, str(output_dir))
        all_results[symbol] = (sigs, tf_data)

    # サマリー
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    for symbol, (sigs, _) in all_results.items():
        print(f"\n{symbol}: {len(sigs)} signals total")
        for tf in ["M5", "M15", "H1", "H4"]:
            tf_sigs = [s for s in sigs if s["tf"] == tf]
            if tf_sigs:
                gc_count = sum(1 for s in tf_sigs if s["signal"] == "GC")
                dc_count = sum(1 for s in tf_sigs if s["signal"] == "DC")
                avg_bars = np.mean([s["next_cross_bars"] for s in tf_sigs if not s["next_cross_at_end"]])
                avg_mfe = np.mean([s["max_favorable_excursion"] for s in tf_sigs])
                avg_mae = np.mean([s["max_adverse_excursion"] for s in tf_sigs])
                print(f"  {tf:>3}: {gc_count} GC + {dc_count} DC | avg持続={avg_bars:.1f}bars | avgMFE={avg_mfe:.2f} | avgMAE={avg_mae:.2f}")


if __name__ == "__main__":
    main()
