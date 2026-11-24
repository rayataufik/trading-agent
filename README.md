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

### Kalau panel belum muncul (label oranye "waiting")

Indikator **tidak pernah** gagal-menempel karena riwayat belum siap. Saat pertama kali
dipasang, atau **setiap kali ganti timeframe**, MT5 membuat ulang seluruh handle
indikator; sampai MT5 selesai menghitungnya, `CopyBuffer` belum bisa mengisi data. Jadi
indikator menunggu dan mencoba lagi sendiri — label oranye di kiri atas menunjukkan
alasannya, misalnya:

```
XAUUSD.x M15: waiting - chart history 240 bars, need 415
XAUUSD.x M15: waiting - indicators calculated 180 of 415 bars (chart has 5000)
```

Dua pesan itu **berbeda masalah**, dan itu disengaja:

| Pesan | Artinya | Yang dilakukan |
|---|---|---|
| `chart history ... bars` | MT5 belum mengunduh riwayat chart | tunggu; atau set **Tools → Options → Charts → Max bars in chart = Unlimited**, lalu tutup-buka chart |
| `indicators calculated ...` | riwayat chart ada, tapi buffer indikator belum selesai dihitung | tunggu beberapa detik |

Kalau angkanya **tidak bergerak** setelah ~30 detik pada pesan `chart history`, riwayat
broker memang belum terunduh. Buka chart itu, scroll ke belakang sekali untuk memaksa
unduhan, lalu tunggu.

### Ganti timeframe

Aman. Setiap ganti timeframe, `OnDeinit` melepas semua handle lama (kalau tidak, handle
bocor dan MT5 punya kuota terbatas), lalu `OnInit` membuat yang baru dan indikator
menunggu lagi seperti saat pertama dipasang. Ini normal, bukan kerusakan.

## Timeframe: semua didukung, tapi dua hal berubah

Kode **tidak** dikunci ke M15. Indikator dan EA selalu memakai timeframe chart itu
sendiri (`Period()`), jadi jalan di M1 sampai MN1. Yang tercetak di panel dan di pesan
Telegram juga mengikuti TF chart — di H1 tertulis `H1`.

Tapi "jalan" tidak sama dengan "sama artinya". Dua hal ini perlu Anda sadari:

### 1. HTF harus di ATAS timeframe chart

`InpHtfTf` default **H4**. Kode hanya memakai HTF kalau lebih tinggi dari TF chart:

```mql5
if((int)m_cfg.htfTf > (int)m_tf)     // HTF valid hanya kalau di atas chart
```

| Chart | HTF H4 | Komposisi skor |
|---|---|---|
| M1–H1 | valid | 5 faktor, HTF 20 poin |
| H4 | **tidak valid** | 4 faktor, 20 poin HTF didistribusikan ulang |
| D1, W1 | **tidak valid** | sama seperti H4 |

Bukan error — `InpHtfUnavailable = "Redistribute"` memang menangani ini. Tapi skornya
jadi tidak sebanding dengan sinyal M15. Kalau Anda trade H1, set `InpHtfTf = H4`. Kalau
trade H4, set `InpHtfTf = D1`.

### 2. Angka strategi bersifat "per bar", bukan "per jam"

Sesuai keputusan Anda, satu set angka dipakai di semua TF. Konsekuensinya:

| Parameter | Nilai | Di M15 | Di M5 | Di H1 |
|---|---|---|---|---|
| `cooldown_bars` | 6 | 1,5 jam | 30 menit | **6 jam** tanpa setup baru |
| `atr_pct_len` | 100 | ~25 jam | ~8 jam | **~4 hari** |
| `max_extension_atr` | 1.5 | 1,5×ATR M15 | ATR M5 lebih kecil → lebih sulit lolos | ATR H1 lebih besar → lebih mudah lolos |
| warmup minimal | ~321 bar | ~3,3 hari | ~1,1 hari | ~53 hari |

Jadi di H1 Anda akan mendapat **jauh lebih sedikit** sinyal (cooldown 6 jam), dan di M1
stop 2.0×ATR sangat rawan kena noise + spread. Strategi ini dirancang dan dikalibrasi di
M15; TF lain akan berperilaku lain, bukan salah, tapi belum teruji.

## EA

1. **Tools → Options → Expert Advisors**
2. Centang **Allow WebRequest for listed URL**
3. Tambahkan persis: `https://api.telegram.org`
4. Isi input `InpBotToken` dan `InpChatId`
5. `InpEnableOrders` biarkan **false**

Kalau WebRequest tidak diizinkan, setiap kiriman gagal dengan **error 4014** dan muncul
di tab Experts. Itu bukan bug.

Default sekarang **signal-only**: EA hanya mengirim pesan, tidak membuka posisi.

### `InpEnableOrders` bukan saklar live

Kalau suatu saat Anda menyalakannya, ketahui persis apa yang **tidak** ada di EA ini:

- tidak ada batas rugi harian
- tidak ada batas jumlah trade per hari
- tidak ada batas posisi terbuka bersamaan

Yang ada hanya stop-loss dan take-profit per order, plus filter spread. Artinya chart
yang dibiarkan terbuka bisa terus membuka posisi sepanjang hari. Karena itu default-nya
`false`, dan satu-satunya pemakaian yang Saya sarankan adalah **Strategy Tester**.
`config.yaml` sengaja tidak lagi memuat kunci guardrail, supaya tidak terlihat seperti
perlindungan yang sebenarnya tidak dijalankan kode.

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
2. Pasang indikator di XAUUSD.x M15, lihat panel masuk akal
3. Cocokkan beberapa bar dengan `parity_check.py` (toleransi ADX berlaku)
4. Ganti-ganti timeframe, pastikan tidak macet lagi
5. Strategy Tester 1 tahun di M15, lihat jumlah trade dan R rata-rata
6. Baru isi token Telegram dan jalankan signal-only di demo
7. Trade otomatis: **tidak**, sesuai keputusan Anda EA tetap signal-only
