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

## Jam sesi dan jam pasar

Dua hal berbeda, jangan dicampur:

| | Apa | Bisa dimatikan? |
|---|---|---|
| **Jam sesi** | Asia/London/NY — pilihan Anda mau trading kapan | Ya: `InpUseSessionFilter = false` |
| **Jam pasar** | Kapan broker benar-benar tutup (weekend, Jumat larut) | **Tidak.** Itu fakta, bukan selera |

Jam pasar **dibaca dari MT5**, bukan ditebak: `SymbolInfoSessionQuote()` per hari. Itu
penting karena "weekend" bukan selalu Sabtu-Minggu — broker yang buka Minggu malam punya
hari buka sendiri, dan CFD index tutup Jumat sore.

### Baris log saat dipasang

```
AILens_Ind: XAUUSD.x M30 | session clock: broker-2h -> UTC (you typed -2h) [auto-detected]; clocks now: broker 11:28, UTC 09:28 (gap +2h)
AILens_Ind: XAUUSD.x market hours (broker time): Mon-Fri 01:00-23:59
```

**Baris pertama** menjawab: jam berapa yang dipakai untuk menghitung sesi.

- `broker-2h -> UTC` — jam broker dikurangi 2 jam menjadi UTC. Broker Anda UTC+2.
- `[auto-detected]` — angka itu **dibaca dari terminal**, bukan dari input. Saat broker
  pindah ke summer time (UTC+3), angka ini ikut berubah sendiri jadi `-3h`.
- `[fallback ...]` — terminal tidak bisa dibaca saat itu, jadi dipakai angka yang Anda isi.
- `[FALLBACK - ... gap looked impossible]` — jarak jam broker dan UTC tidak masuk akal.
  Penyebabnya hampir selalu **jam atau timezone Windows Anda salah**, bukan broker.

Bagian `clocks now` adalah bukti, bukan klaim: `broker 11:28, UTC 09:28`. Bandingkan
dengan jam di ponsel Anda. Kalau UTC-nya meleset, jam PC yang salah — dan auto-deteksi
akan ikut salah, karena `TimeGMT()` mengambil waktu dari PC.

**Baris kedua** adalah jam pasar yang dipakai aturan weekend/Jumat. `Mon-Fri 01:00-23:59`
artinya tiap hari bursa buka 01:00 dan tutup 23:59 **waktu broker**, dan Sabtu-Minggu
tidak ada sesi sama sekali. Jeda 23:59–01:00 itu istirahat harian XAUUSD (17:00 New York),
bukan bug.

Kalau tertulis `<none published - market assumed open>`, simbol itu tidak mempublikasikan
jamnya; gate tidak memblokir apa pun, dan Anda harus memperhatikan tutup pasar sendiri.

## EA

1. **Tools → Options → Expert Advisors**
2. Centang **Allow WebRequest for listed URL**
3. Tambahkan persis: `https://api.telegram.org`
4. Isi input `InpBotToken` dan `InpChatId`
5. `InpEnableOrders` biarkan **false**

Kalau WebRequest tidak diizinkan, setiap kiriman gagal dengan **error 4014** dan muncul
di tab Experts. Itu bukan bug.

Default sekarang **signal-only**: EA hanya mengirim pesan, tidak membuka posisi.

### Dua input Telegram, dan kenapa namanya tidak terlihat

Di panel input, **komentar menggantikan nama variabel**. Jadi yang Anda lihat adalah:

| Yang tampil di panel | Variabel sebenarnya | Isi dengan |
|---|---|---|
| `from @BotFather; leave empty to disable sending` | `InpBotToken` | token bot |
| `your chat id` | `InpChatId` | **angka**, bukan token |

Token selalu berbentuk `123456789:AA...` — ada titik dua di tengah. Angka sebelum titik dua
itu **ID bot itu sendiri**, dan bukan chat id Anda. Salah menaruh token di kolom chat id
menghasilkan error yang menyesatkan:

```
403 Forbidden: the bot can't send messages to the bot
```

Artinya bot disuruh mengirim pesan ke dirinya sendiri. EA sekarang menangkap ini saat
dipasang dan menulis sebabnya di tab Experts, jadi tidak perlu menunggu sinyal pertama.

### Cara mendapatkan chat id

1. Buka bot Anda di Telegram, tekan **Start**, kirim pesan apa saja
2. Buka di browser:

```
https://api.telegram.org/bot<TARUH_TOKEN>/getUpdates
```

3. Cari `"chat":{"id":...}` — itulah chat id. Kalau kosong, kirim pesan lagi lalu refresh.
4. Alternatif cepat: kirim pesan ke **@userinfobot**, dia membalas id Anda.
5. Untuk grup/channel, id-nya **negatif** (mis. `-1001234567890`). Tanda minusnya bagian
   dari id, jangan dihapus.

Tabel arti error lain yang sekarang otomatis dijelaskan EA:

| Pesan Telegram | Sebabnya |
|---|---|
| `403 ... can't send messages to the bot` | chat id diisi id bot, bukan id Anda |
| `400 ... chat not found` | chat id salah, atau Anda belum pernah `/start` ke bot |
| `401 Unauthorized` | token salah atau sudah di-revoke |
| `403 ... not enough rights` | bot tidak punya izin posting di channel/grup itu |
| `403 ... bot was blocked by the user` | Anda memblokir bot; buka blokir lalu `/start` |

**Jangan bagikan token Anda.** Siapa pun yang memegangnya bisa mengirim pesan sebagai bot
Anda. Kalau pernah bocor, buka @BotFather → `/mybots` → API Token → **Revoke**.

### Baris "Telegram" di panel

Saat EA dipasang, ia **mengirim satu pesan tes** ke chat id Anda. Itu bukan spam — itu
satu-satunya bukti jujur bahwa seluruh rantai bekerja: `getMe` cukup untuk memastikan
token hidup, tapi tidak membuktikan chat id bisa menerima, dan justru chat id itulah
yang pernah salah.

| Tampilan di panel | Artinya |
|---|---|
| `Telegram    connected 11:28` (hijau) | Pesan tes **sampai** — cek Telegram Anda, harusnya ada |
| `Telegram    FAILED 11:28 - see Experts log` (merah) | Gagal; sebabnya di baris log tepat di atasnya |
| `Telegram    off (inputs empty)` (abu) | EA jalan tapi Telegram sengaja tidak diisi |
| `Telegram    no data (EA not attached)` (abu) | EA belum pernah jalan di terminal ini |

Status ini dibawa EA lewat Global Variable terminal, jadi indikator di chart mana pun
menunjukkan hasil pengiriman terakhir. Berlaku juga untuk sinyal asli: setelah satu setup
terkirim, jam di baris itu diperbarui.

### Target 1:2, dan dari mana angka 1:3 tadi

Default di kedua file sudah lama benar: `InpT1R = 1.0`, `InpT2R = 2.0` — sesuai mandat
$50 risiko / $100 target. Angka 1:3 yang Anda lihat bukan dari sini, dua kemungkinannya:

1. **MT5 mengingat input terakhir** per indikator per chart. Indikator yang nempel di
   chart Anda masih membawa angka lama (1.5 / 3.0) dari sebelum default disamakan.
   Fix: klik kanan chart → *Indicators List* → pilih AI Lens+ → **Edit** → isi `1.0`
   dan `2.0`. Atau lepas dan pasang ulang indikatornya, lalu tekan **Reset** di
   jendela input supaya semua nilai kembali ke default baru.
2. Dulu pesan Telegram menghitung target dari input terpisah (`InpRewardRisk`). Itu
   **bug** dan sudah dihapus: target sekarang selalu dibaca dari trade (`t.t2`), jadi
   panel, pesan Telegram, dan box di chart **tidak mungkin** berbeda lagi.

Baris `Targets` di panel sekarang menunjukkan R-nya juga:

```
Targets     2705.50 / 2711.00   (1.0 / 2.0 R)
```

Kalau angka di dalam kurung bukan `1.0 / 2.0 R`, input di chart itu yang salah —
terlihat langsung di tempat, tidak perlu membongkar setting.

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
