$ErrorActionPreference = "Stop"

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$zip = Join-Path $base "techavi-main.zip"
$extract = Join-Path $base "techavi_extract"
$target = Join-Path $base "TECHAVIII_HIZLI_ARAMA"

Write-Host "[1/5] GitHub'dan guncel proje indiriliyor..."
Invoke-WebRequest -Uri "https://github.com/c05538482-rgb/TECHAVIII/archive/refs/heads/main.zip" -OutFile $zip

Write-Host "[2/5] Proje aciliyor..."
Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $zip -DestinationPath $extract -Force
$root = Get-ChildItem $extract -Directory | Select-Object -First 1
Copy-Item $root.FullName $target -Recurse -Force

Write-Host "[3/5] Server endpointi ekleniyor..."
$serverPath = Join-Path $target "server.js"
$server = Get-Content $serverPath -Raw

$marker = 'app.get("/api/push/public-key", (req, res) => {'
if (-not $server.Contains($marker)) { throw "server.js icinde uygun ekleme noktasi bulunamadi." }

$endpoint = @'
app.get("/api/search-stream", async (req, res) => {
  const query = normalizeQuery(req.query.q);
  if (query.length < 2) return res.status(400).json({ ok: false, error: "En az 2 karakter yaz." });

  const stores = ["trendyol", "hepsiburada", "n11", "mediamarkt", "teknosa", "vatan", "amazon", "pazarama", "ciceksepeti"];

  res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  if (res.flushHeaders) res.flushHeaders();

  const send = (event, payload) => {
    if (res.writableEnded) return;
    res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
  };

  let closed = false;
  req.on("close", () => { closed = true; });

  const jobs = stores.map(async (store) => {
    try {
      const result = await searchStore(store, query);
      if (!closed) send("store", { store, result });
    } catch (e) {
      if (!closed) send("store", { store, error: e?.message || "Arama başarısız" });
    }
  });

  await Promise.allSettled(jobs);

  if (!closed) {
    send("done", { ok: true, query });
    res.end();
  }
});

'@

$server = $server.Replace($marker, $endpoint + $marker)
Set-Content $serverPath $server -Encoding UTF8

Write-Host "[4/5] Frontend kademeli aramaya geciriliyor..."
$appPath = Join-Path $target "public\app.js"
$app = Get-Content $appPath -Raw

$start = $app.IndexOf("async function searchProducts(q) {")
$end = $app.IndexOf("function scheduleSearch() {")
if ($start -lt 0 -or $end -lt 0) { throw "app.js icinde searchProducts bulunamadi." }

$newSearch = @'
async function searchProducts(q) {
  const clean = q.trim();
  state.query = clean;
  state.activeStore = "all";
  renderStoreCounts();

  if (state.controller) {
    try { state.controller.abort(); } catch {}
  }
  const myId = ++state.requestId;

  if (clean.length < 2) {
    state.allProducts = [];
    state.storeCounts = {
      trendyol: null, hepsiburada: null, n11: null, mediamarkt: null,
      teknosa: null, vatan: null, amazon: null
    };
    renderStoreCounts();
    render();
    return;
  }

  showLoading(clean);
  state.allProducts = [];

  const controller = new AbortController();
  state.controller = controller;

  const resetCounts = () => {
    state.storeCounts = {
      trendyol: null, hepsiburada: null, n11: null, mediamarkt: null,
      teknosa: null, vatan: null, amazon: null
    };
  };
  resetCounts();

  try {
    const response = await fetch(`/api/search-stream?q=${encodeURIComponent(clean)}`, {
      signal: controller.signal,
      headers: { Accept: "text/event-stream" }
    });

    if (!response.ok) {
      const j = await response.json().catch(() => ({}));
      throw new Error(j.error || "Arama başarısız.");
    }

    if (!response.body) throw new Error("Canlı arama bağlantısı desteklenmiyor.");

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    const handleBlock = block => {
      const lines = block.split(/\r?\n/);
      let event = "message";
      let data = "";

      for (const line of lines) {
        if (line.startsWith("event:")) event = line.slice(6).trim();
        else if (line.startsWith("data:")) data += line.slice(5).trim();
      }

      if (!data || myId !== state.requestId) return;

      let payload;
      try { payload = JSON.parse(data); } catch { return; }

      if (event === "store") {
        const store = payload.store;
        if (payload.result) {
          const result = payload.result;
          state.storeCounts[store] = Number(result.count ?? result.products?.length ?? 0);
          if (Array.isArray(result.products)) {
            state.allProducts.push(...result.products);
          }
        } else {
          state.storeCounts[store] = 0;
        }

        renderStoreCounts();
        render();
      }
    };

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const blocks = buffer.split(/\r?\n\r?\n/);
      buffer = blocks.pop() || "";

      for (const block of blocks) handleBlock(block);
    }

    if (buffer.trim()) handleBlock(buffer);

    if (myId === state.requestId) {
      renderStoreCounts();
      render();
    }
  } catch (e) {
    if (e.name === "AbortError") return;
    if (myId !== state.requestId) return;

    state.allProducts = [];
    $("#resultCount").textContent = "";
    $("#grid").innerHTML = `<div class="empty-grid"><div><b>Arama sırasında hata oluştu.</b><br><span>${esc(e.message)}</span></div></div>`;
  } finally {
    if (myId === state.requestId) state.controller = null;
  }
}

'@

$app = $app.Substring(0, $start) + $newSearch + $app.Substring($end)
Set-Content $appPath $app -Encoding UTF8

Write-Host "[5/5] Temizlik yapiliyor..."
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "========================================"
Write-Host "  HAZIR: $target"
Write-Host "========================================"
