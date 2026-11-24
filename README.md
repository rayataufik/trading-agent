# AI Agent Lens — MT5 (MQL5)

Satu implementasi logika, dua program. `AILens.mqh` adalah satu-satunya tempat strategi
hidup. Indikator dan EA sama-sama `#include` file itu, jadi angka di chart dan angka di
sinyal Telegram tidak bisa berbeda.

```
mql5/
  AILens.mqh        inti logika: skor, regime, struktur, sesi, trade state
  AILens_Ind.mq5    indikator: gambar panel, level, box risiko
  AILens_EA.mq5     EA: sinyal + Telegram (+ order opsional, default MATI)
```

## Instalasi

1. Di MT5: **File → Open Data Folder**
2. Masuk ke `MQL5\Indicators\`, buat folder `AILens\`
3. Copy **ketiga** file ke folder itu (`.mqh` harus satu folder dengan `.mq5`)
4. Buka MetaEditor (F4), buka tiap file, tekan **F7** untuk compile
5. Kembali ke MT5, refresh panel Navigator

Compile harus **0 errors, 0 warnings**. Kalau ada error, kirim ke Saya: nama file,
nomor baris, dan pesan lengkapnya. Error pertama yang paling penting — error setelahnya
biasanya hanya efek dari yang pertama.

## Indikator

Drag `AILens_Ind` ke chart. Panel muncul di kiri atas dengan:

| Baris | Arti |
|---|---|
| hero | LONG / SHORT / WAIT + skor sisi itu |
| Regime | TREND_UP / TREND_DOWN / RANGE / HIGH_VOLATILITY |
| Session | ASIA / LONDON / NY / OVERLAP / OFF, plus "(blocked)" kalau filter menolak |
| Long/Short | dua skor berdampingan |
| Confluence | berapa faktor yang selaras dari berapa faktor aktif |
| Entry/Stop/Targets | hanya kalau ada trade terbuka |
| HTF / RSI / ADX | konteks |
| Structure | BULLISH / BEARISH / MIXED + BREAK_UP / BREAK_DOWN |

Garis putus-putus: PDH, PDL, VWAP sesi.

## EA

1. **Tools → Options → Expert Advisors**
2. Centang **Allow WebRequest for listed URL**
3. Tambahkan persis: `https://api.telegram.org`
4. Isi input `InpBotToken` dan `InpChatId`
5. `InpEnableOrders` biarkan **false** dulu

Kalau WebRequest tidak diizinkan, setiap kiriman gagal dengan **error 4014** dan muncul
di tab Experts. Itu bukan bug.

Default sekarang **signal-only**: EA hanya mengirim pesan, tidak membuka posisi.

## Angka default sudah disamakan dengan `config.yaml`

| Parameter | Nilai |
|---|---|
| score threshold | 70 |
| min ADX entry | 20 |
| anti-chase | 1.5 × ATR |
| cooldown | 6 bar |
| stop | 2.0 × ATR |
| T1 / T2 | 1.0R / 2.0R |
| partial di T1 | 0% (tidak ada partial) |
| move BE / trailing | mati |

T1 = 1R dan T2 = 2R cocok dengan mandat Anda $50 risiko / $100 target.

## Satu perbedaan yang harus Anda tahu: ADX

Ini penting, dan tidak bisa diakali.

ADX bawaan MetaTrader (`iADX`) **bukan** implementasi Wilder yang dipakai Pine
`ta.dmi`. MT5 menghitung DI dan ADX dengan penghalusan yang berbeda, jadi nilainya bisa
berbeda beberapa poin pada data yang sama. Konsekuensinya: ADX di MT5 akan kadang
melewati ambang 20 saat ADX Pine masih 18, dan sebaliknya.

Yang **tidak** terpengaruh: EMA, RSI, MACD, ATR — semuanya memakai definisi yang sama
di kedua platform.

Jadi kalau Anda membandingkan panel MT5 dengan panel TradingView, jangan heran kalau
skor beda 1–4 poin. Itu ADX dan feed harga, bukan bug. Kalau beda 20, baru curiga.

Kalau Anda ingin ADX identik dengan Pine, ganti `iADX` di `Init()` dengan ADX yang
dihitung manual di dalam core. Bisa Saya kerjakan, tapi baru layak kalau Anda memang
butuh paritas angka, bukan paritas perilaku.

## Backtest

EA ini bisa langsung diuji di **Strategy Tester MT5** — model "Every tick based on real
ticks", dengan spread dan komisi akun Anda. Itu jauh lebih jujur daripada backtester
Python yang belum kita buat, karena memakai feed dan biaya yang sebenarnya.

Catatan: dengan `InpEnableOrders = false`, Strategy Tester tidak akan menghasilkan
trades. Untuk mengukur strategi, set `true` di Strategy Tester saja — jangan di akun
live.

## Urutan yang Saya sarankan

1. Compile ketiganya, laporkan error kalau ada
2. Pasang indikator di XAUUSD M15, lihat panel masuk akal
3. Cocokkan beberapa bar dengan `parity_check.py` (toleransi ADX berlaku)
4. Strategy Tester 1 tahun, lihat jumlah trade dan R rata-rata
5. Baru isi token Telegram dan jalankan signal-only di demo
6. Live order hanya setelah langkah 4–5 meyakinkan
