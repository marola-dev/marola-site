# Sic Mundus Creatus Est

2026-10-09

marola 上線了，開放原始碼、非營利。它是一幅涵蓋 Florianópolis、Rio de Janeiro 與 Salvador 海灘的地圖，今天與明天的分數完全由公開資料計算而成。最新版本 0.2.1 已於10月8日發布。

::: release v0.2.1 2026-10-08
- marola 的引用文獻新增三位作者: Elisa Oliveira、Leonardo Ramos Almeida 與 Pablo Ribeiro（[#712](https://github.com/marola-dev/marola/pull/712)、[#714](https://github.com/marola-dev/marola/pull/714)）
- AI 代理技能改為固定版本、每週更新（[MIP-0080](https://github.com/marola-dev/marola/pull/701)）
- 一份不讓 marola 綁定單一供應商、評估外部語言模型的提案（[MIP-0081](https://github.com/marola-dev/marola/pull/704)）
[版本說明](https://github.com/marola-dev/marola/releases/tag/v0.2.1) · [自 0.2.0 以來的變更](https://github.com/marola-dev/marola/compare/v0.2.0...v0.2.1)

## 官方連結

- 地圖: [marola.dev](https://marola.dev/)
- 文件: [docs.marola.dev](https://docs.marola.dev/)
- 程式碼（MIT 授權）: [github.com/marola-dev](https://github.com/marola-dev)
- 引用: Zenodo 上的 [10.5281/zenodo.23224155](https://doi.org/10.5281/zenodo.23224155)。此 DOI 永遠指向最新版本，目前是 [0.2.1](https://github.com/marola-dev/marola/releases/tag/v0.2.1)。[README](https://github.com/marola-dev/marola#how-to-cite) 附有 ABNT、APA 與 BibTeX 條目。
- marola 的語言模型 marola-sea: 在 [marola-ml](https://github.com/marola-dev/marola-ml) 訓練，目前只有小型測試版本
- 公開討論: [GitHub Discussions](https://github.com/marola-dev/marola/discussions)

## marola 是什麼、不是什麼

分數結合了海況、風、浪、潮汐，以及 Santa Catarina（IMA）、Rio de Janeiro（INEA）與 Bahia（INEMA）州環境機關的官方水質判定。任何可能讓身處風險的因素，都由任何人都能讀懂的簡單規則決定。AI 只撰寫摘要，從不改動分數。沒有 Cookie、沒有自有追蹤、不需帳號。

marola 不是救生員、不是官方預報、也不是警報服務。緊急情況下，地圖的緊急按鈕列出巴西的免費緊急電話，例如消防與救生員的 193。

## 網站如何運作

地圖是靜態的: 你開啟頁面時，沒有任何運算、也沒有任何 AI 在跑。每天四次，專案自己的伺服器（位於巴西的 Hostinger KVM 4 虛擬機器）上的例行工作執行 marola-app，為每個海灘計分並發布檔案。供應 marola.dev 的也是同一台機器，由 nginx 提供服務，沒有 CDN，也沒有 Cloudflare。INEA 與 INEMA 只回應巴西的位址，而這台機器就在巴西，因此不需要代理。

資料將移入 Cloudflare R2（一種檔案儲存服務），放進仍在建置中的資料湖（移往 R2 已於 [marola#692](https://github.com/marola-dev/marola/pull/692) 獲得接受; 結構的 [marola-oods#22](https://github.com/marola-dev/marola-oods/pull/22) 仍在審查。詳情見下）。

## 儲存庫

marola 的每個部分都是 [marola-dev](https://github.com/marola-dev) 組織裡的獨立儲存庫，各有自己的測試與版本。沒有任何一部分直接使用另一部分的程式碼: 一律使用已發布的版本。

### [marola](https://github.com/marola-dev/marola)

主儲存庫，把其他部分繫在一起。它持有每次變更的計畫（MIP，marola 的變更提案）、階段清單、工作方式與文件網站。可供引用的版本從這裡發布。

### [marola-app](https://github.com/marola-dev/marola)

主力程式，以 [Kyo](https://getkyo.io/) 寫成的 Scala 3。它從 OpenStreetMap 取得海灘、從 Open-Meteo 取得海況與天氣、取得水質公告，計算分數、套用安全否決，並附帶命令列工具與讓 AI 助手查詢 marola 的 MCP 伺服器。它發布的 Docker 映像檔就是組建地圖的東西。

### [marola-site](https://github.com/marola-dev/marola-site)

marola.dev 的地圖。頁面是 Elm，伺服器與靜態頁面是 Haskell（[ADR 0005](https://github.com/marola-dev/marola-site/blob/main/docs/adr/0005-elm-and-haskell.md)），跑在網站自己的底圖上，沒有 Mapbox、沒有權杖。支援葡萄牙文、英文、日文與繁體中文。

### [marola-oods](https://github.com/marola-dev/marola-oods)

Open Ocean Data Store: 將保存海灘與水質樣本開放資料湖的結構。目前還沒有資料。

### [marola-ml](https://github.com/marola-dev/marola-ml)

不會在地圖上執行的 Python 程式碼: 以 DSPy 編譯提示、維護模型上線前必須通過的品質閘門，並訓練 marola-sea。

### [marola-corpus](https://github.com/marola-dev/marola-corpus)

marola 據以回答的海洋筆記，每一則都附出處。

### [marola-devkit](https://github.com/marola-dev/marola-devkit)

每個儲存庫共用的工具箱: 腳本、git掛鉤、AI 代理技能與共用 CI。

### [agent-skills](https://github.com/marola-dev/agent-skills)

marola 使用的 AI 代理技能目錄: 每個技能在哪裡、從哪裡來、測試過什麼。

組織也維護 [awesome-ocean-science](https://github.com/marola-dev/awesome-ocean-science)，一份關於海洋的開放軟體、資料與工具清單。

## 我們正在打造什麼: 資料湖

今天，地圖每次更新都從頭抓取海灘與水質，歷史也就流失了。[MIP-0075](https://github.com/marola-dev/marola/blob/main/docs/MIPs/MIP-0075-water-quality-store-r2.md) 提議把一切保存在開放資料湖裡: [DuckLake](https://ducklake.select/) — Parquet 檔案加上 DuckDB 目錄。MIP 原本以 Backblaze B2 撰寫，[marola#692](https://github.com/marola-dev/marola/pull/692) 提議改用 Cloudflare R2 並獲接受。marola-app 的每週任務會寫入資料湖，結構由 marola-oods 定義。先來海灘，然後是 Santa Catarina 的水質，再來是 Rio 與 Bahia。

結構（[marola-oods#22](https://github.com/marola-dev/marola-oods/pull/22)）仍在審查。資料湖還沒有收到任何資料。

下一篇文章會解釋 marola 為什麼需要資料湖。

## 與 Leave No Trace 的合作

教人親近自然不留痕跡的非營利組織 [Leave No Trace](https://lnt.org/)，已接受 marola 加入它的社區合作計畫。

這個計畫向夥伴開放 Leave No Trace 的教育資料，並讓認證講師得以核發課程證書。這會為 marola 帶來什麼，將在下一篇文章說明（[#96](https://github.com/marola-dev/marola-site/issues/96)）。

marola 繼續對環境機構，以及能提供資料或運算資源的人，保持不涉金錢的合作（[關於](about.html)）。

## 如何追蹤或幫忙

使用地圖，發現錯誤就告訴我們。可以用葡萄牙文或英文開 [issue](https://github.com/marola-dev/marola/issues)，或挑一個標了 [good first issue](https://github.com/search?q=org%3Amarola-dev+is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22&type=issues) 的任務。也可以[支持這個專案](support.html)。
