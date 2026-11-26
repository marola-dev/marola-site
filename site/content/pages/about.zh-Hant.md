title: 關於 marola
description: marola 是什麼、為何公開且非營利、內部如何運作，以及資料的來源。

## marola 是什麼

::lede 想像一位熟知大海的朋友。你問:「明天能游泳嗎？ 幾點最好？」他看看浪、風與潮汐，確認水質是否適合下水，甚至附近有沒有水母，然後告訴你最佳時段，以及原因。

這位朋友就是 marola。目前，marola 是一幅涵蓋 Florianópolis、Rio de Janeiro 與 Salvador 海灘的地圖，每個海灘都有今天與明天的分數。它不捏造任何東西: 每個數字都來自公開資料。涉及風險時，做決定的是任何人都能讀懂的簡單規則。不知道的時候，它會說「無資料」。

## 為何公開且非營利

巴西海洋資料的大部分，掌握在企業與私人機構手中。沒有這些資料，就無法預測水質、氣候災害與環境事故。

因此 marola 公開而且非營利。承諾是: 以我們能做到的最好方式，把一切還給所有人。如果我們只是又一家公司，就很難向握有資料的人開口要資料。

## 水質優先

巴西的基礎污水處理離解決還很遠。這個題目太大，不是這一頁能講完的，但它決定了 marola 的起點: 水質。在衝浪、釣魚或潛水之前，先有「這水能下嗎？」這個問題。

其中一個想法是全國性的水質排行，已經在[公開討論](https://github.com/marola-dev/marola/discussions/676)中。我們還會寫很多: 誰把水照顧得好、誰照顧得差、怎麼做、為什麼。

## 一個水的超級應用

我們活在超級應用的時代，marola 最終會成為水的超級應用。與水有關的一切都在同一個地方: 海灘、海洋、水質與風險。不是把工具交給你自己想辦法，而是直接把答案交給你。

矽谷最大的投資基金之一 Sequoia Capital 稱這個轉變為「service as software」。軟體不再販售工具，而是交出完成的工作。

> @en
> "A copilot sells the tool. An autopilot sells the work."
> -- Julien Bek, [Services: The New Software](https://sequoiacap.com/article/services-the-new-software), Sequoia Capital, 2026. a ideia vem de [Generative AI's Act o1](https://sequoiacap.com/article/generative-ais-act-o1), de Sonya Huang e Pat Grady, 2024.

## 為何程式碼公開

到了 2026 年，已經沒有理由寫封閉的程式碼。有了 AI，做出新功能從未如此容易，程式碼不再是秘密。巴西需要的是長期的專案: 不受選舉時程左右，也不因政權更迭而消亡。程式碼公開，專案就能在創始人離開之後繼續存活。

## 不涉金錢的合作

marola 需要雲端運算: 儲存資料的空間，以及訓練與執行模型的顯示卡。雖然非營利，它仍接受願意提供這些資源或資料的企業合作，金錢不經手。作為回報，企業會在網站上獲得低調的銘謝。沒有廣告、橫幅或追蹤。

## 合作夥伴

marola 是 [Leave No Trace](https://lnt.org/) 的官方合作夥伴（Proud Partner），它教人親近自然而不留痕跡。

[OpenDiving](https://opendiving.app/) 是一份開放原始碼的潛水日誌，為了比任何潛水電腦廠商都活得久而打造。兩個專案都使用開放資料，並互相連結: OpenDiving 把 marola 列在它的合作夥伴應用之中。

## marola 如何組成

marola 是一組程式碼儲存庫，各司其職:

- **marola-app** 彙整海況預報、海灘與水質公告，計算分數。
- **marola-site** 就是你正在使用的地圖。
- **marola-corpus** 保存關於海的筆記，每一則都附出處。
- **marola-ml** 在 AI 進入 marola-app 之前，先訓練並測試它。
- **marola-oods** 是海灘與水質歷史的公開檔案庫。
- **marola-research** 保存 marola 的研究。
- **marola-skills** 與 **marola-agents** 列出在專案中工作的 AI 技能與代理。
- **marola-devkit** 是所有儲存庫共用的工具箱。
- **marola** 是傘狀儲存庫，持有計畫與規則，並把其他每一個以 git 子模組帶進來。

[開啟架構圖](/architecture) — marola 的儲存庫，以及每個儲存庫交給下一個的內容。


更多圖表: [資料來源](/data-flow)、[研究的流程](/studies-flow)、[從合併到 marola.dev](/deploy-flow)、[變更如何送達](/develop-flow)。
marola 的儲存庫，以及各自交給其他部分的東西。圖片與 [GitHub 組織頁面](https://github.com/marola-dev)上的相同（出處: [marola-dev/.github](https://github.com/marola-dev/.github/blob/main/profile/README.md)）。

這稱為分散式單體。說它是單體，因為它像一個零件般運作: 一個專案、一份計畫、一套做法，各部分的版本一起前進。說它分散，因為每個部分住在自己的儲存庫裡，有自己的測試，發布自己的版本。

我們這樣做有兩個原因。第一: 大部分程式碼是與 Anthropic 的 Claude 一起撰寫與維護的，無論是在 Claude Project，還是在終端機的 Claude Code。帶子模組的傘在這裡幫上忙: Claude 從上方看見整個專案，計畫與規則寫在同一個地方，每次只改動一個小儲存庫，連同它的測試。第二: 每個部分在某種程度上也能獨立行走。只想要水質資料的人，可以不用其他部分而直接使用 marola-oods；一個儲存庫的錯誤也不會拖垮其他部分。任何一部分都不直接讀取另一部分的程式碼: 它使用已發布的版本，只有自己決定時才換版。

網站運行在我們自己的伺服器上: 一台向 [Hostinger](https://www.hostinger.com/) 租用、位於巴西的 KVM 4 虛擬機器，以 [NixOS](https://nixos.org/) 設定。同一台機器交付頁面、海灘看板與底圖切片，中間沒有 CDN，也沒有其他公司。放在巴西，是因為某些州級機關只回應巴西的位址。

## Claude

marola 的大部分程式碼是在 Claude Project 中與 Anthropic 的 AI 助理 Claude 一起寫的: 在 claude.ai 上的一個空間裡，它閱讀儲存庫、開合併請求、與我們在討論串中對話。這個專案的設定寫在公開檔案 [CLAUDE_PROJECT.config.md](https://github.com/marola-dev/marola/blob/main/CLAUDE_PROJECT.config.md)（英文）裡: Claude 遵循的指示、它閱讀的儲存庫、執行環境，以及它自行執行的例行工作。任何人都能讀這份檔案，並據此組出一個一樣的專案。

## 分數如何運作

每個海灘落在地圖圖例的五個區間之一: **≥70** 良好、**40–69** 尚可、**1–39** 差、**0** 不適合，或某個來源沒有回應時的**無資料**。分數考慮海況、風、浪、潮汐與水質。一個語言模型撰寫短摘要，第二道自動審查核對摘要與數字是否相符。AI 只做說明: 它從不改分數，也不會解除警報。

## 資料從哪裡來

海灘來自 [OpenStreetMap](https://www.openstreetmap.org/copyright)，海況與天氣預報來自 [Open-Meteo](https://open-meteo.com/)，水質來自 IMA/SC、INEA（RJ）與 INEMA（BA）的官方公告。這些來源公開且免費。底圖是 marola 自己的: 地圖切片以 [Protomaps](https://protomaps.com/) 從 OpenStreetMap 資料裁切，存放在我們的伺服器，以開源地圖庫 [MapLibre](https://maplibre.org/) 繪製。目前只啟用了海灘與水質圖層。風、浪與 NASA 的衛星影像（[GIBS](https://www.earthdata.nasa.gov/gibs)）即將推出。

## 隱私

marola 不使用 Cookie，也沒有自有追蹤。底圖來自 marola 自己的伺服器: 樣式、切片與字型都是本站的檔案。因此，繪製地圖不會向任何人透露你來過這裡。只有兩件事會連到第三方，而且只在你開啟時: 衛星圖層（影像來自 NASA 的伺服器）與從 Spotify 載入的播放器。只有在這兩種情況下，對方才會看到你的 IP 位址。「靠近我」選項只在瀏覽器內使用你的位置，永遠不會外送。

## 誰在打造

打造 marola 的人在[成員頁面](/members.html)上，與 Zenodo 上 marola 登錄的作者名單相同。

marola 的研究在 [marola-research](https://github.com/marola-dev/marola-research/blob/main/README.md)。想參與或與我們共同發表，請閱讀[投稿與出版徵件](https://github.com/marola-dev/marola-research/blob/main/chamada/chamada.pdf)（PDF）。

做研究的人也可以在這裡發布研究。閱讀大家送出的[研究](/studies)，或[送出你自己的](/submit)。marola 不審查研究。

## 謝誌

緊急按鈕的想法來自 Carlos Toledo（[@carlostoledo1891](https://github.com/carlostoledo1891)）的 [swell-floripa](https://swell-floripa.vercel.app/)。

海浪的聲音是 Luftrum 的錄音（[freesound](https://freesound.org/s/48412/)，[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) 授權），由 Porrumentzio 為 [Blanket](https://github.com/rafaelmardojai/blanket) 剪輯成循環。

[OpenDiving](https://github.com/opendiving/opendiving) 的 Aleksei Vesnin（[@aleskiontherun](https://github.com/aleskiontherun)）將 marola 迎接為合作夥伴應用。

Pedro Veras Guimarães（[@pvguima](https://github.com/pvguima)）花了時間、善意與耐心，向 marola 的創辦人講解波浪物理。

## 如何幫忙

使用地圖，發現錯誤就告訴我們。也請告訴我們你在海裡看到的東西，例如水母，或缺少的海灘。請開 [issue](https://github.com/marola-dev/marola/issues)，中文或英文皆可。程式碼、計畫與每個決定都在 [GitHub](https://github.com/marola-dev)。[文件](https://docs.marola.dev/)寫明哪些已經能運作、哪些還是計畫。
