# Fast Reversal (MQL5)

Indicator `Indicators/FastReversal.mq5` untuk MetaTrader 5.

## Pasang
1. MT5 → File → Open Data Folder → `MQL5/Indicators/`
2. Salin `FastReversal.mq5`, buka di MetaEditor, tekan **F7** (Compile).
3. Seret indicator ke carta (contoh: BTCUSD / XAUUSD M15).

## Apa yang dipaparkan
- **Garisan trailing ATR** (biru = naik, merah = turun). Isyarat BUY/SELL bila harga tutup melepasi garisan.
- **Panel**: Mode, Setup (skor semasa isyarat), Live (skor sekarang), Context 1/2 (EMA 21/50 pada H1/H4),
  Market Bias, Volatility (ATR vs purata 100), Structure Bias (HH/HL vs LH/LL), Signal, Status, Momentum (ADX).
- **Paras**: HIGH/LOW ZONE (zon masuk), RISK (stop = garisan trailing), TP1 / TP2 / END (1R, 1.5R, 2R).

## Skor (0–100)
20 = Context 1 sehala, 20 = Context 2 sehala, 20 = struktur sehala, 0–20 = kekuatan ADX, 20 = +DI/-DI sehala.
Mode CONSERVATIVE hanya tunjuk isyarat dengan skor ≥ `InpMinScore`.

Untuk tujuan pendidikan sahaja. Uji dalam Strategy Tester / akaun demo dahulu.
