-- | What the form says for each error code, in the four languages of the site, in one place. The
-- API keeps its English @message@; the web form shows these next to the fields. @{lo}@ and @{hi}@
-- are the limits. pt-BR is the source the owner manages, en is the ASD-STE100 pass after it, and
-- ja and zh-Hant are the LLM passes.
module Marola.Server.Messages (table, codes, text) where

import Data.Text (Text)
import Data.Text qualified as T
import Marola.Layout (Language (..))
import Marola.Study

-- | code, pt-BR, English, Japanese, Traditional Chinese.
table :: [(Text, Text, Text, Text, Text)]
table =
  [ ("required", "preencha este campo", "fill in this field", "この欄を入力してください", "請填寫這個欄位"),
    ("too_short", "escreva pelo menos {lo} caracteres", "write at least {lo} characters", "少なくとも{lo}文字を書いてください", "請至少寫 {lo} 個字"),
    ("too_long", "escreva no máximo {hi} caracteres", "write at most {hi} characters", "最大{hi}文字までにしてください", "請最多寫 {hi} 個字"),
    ("too_many", "há linhas demais: o máximo é {hi}", "there are too many lines: the most is {hi}", "行が多すぎます: 最大{hi}行です", "行數過多: 最多 {hi} 行"),
    ("invalid", "este valor não é válido", "this value is not valid", "この値は有効ではありません", "這個值無效"),
    ("unknown_value", "escolha uma das opções da lista", "pick one of the options in the list", "リストから1つ選んでください", "請從列表中選擇一個選項"),
    ("bad_name", "cada nome precisa de 2 a 120 caracteres", "each name needs 2 to 120 characters", "各名前は2〜120文字にしてください", "每個姓名需為 2 至 120 個字"),
    ("bad_orcid", "o ORCID iD não é válido; confira o dígito final", "the ORCID iD is not valid; check the last digit", "ORCID iDが無効です。末尾の数字を確認してください", "ORCID iD 無效; 請檢查最後一位數字"),
    ("bad_link", "use um link que comece com https://", "use a link that starts with https://", "https://で始まるリンクを使ってください", "請使用以 https:// 開頭的連結"),
    ("must_be_true", "confirme que você pode publicar este arquivo", "confirm that you may publish this file", "このファイルを公開できることを確認してください", "請確認你有權公開這個檔案"),
    ("invalid_utf8", "o texto tem caracteres que não dá para ler", "the text has characters that cannot be read", "テキストに読めない文字が含まれています", "文字中包含無法讀取的字元"),
    ("duplicate_field", "o formulário chegou com defeito; recarregue a página e tente de novo", "the form arrived damaged; reload the page and try again", "フォームが不正な状態で届きました。ページを再読み込みしてもう一度お試しください", "表單送達時已損壞; 請重新載入頁面後再試一次"),
    ("unknown_field", "o formulário chegou com defeito; recarregue a página e tente de novo", "the form arrived damaged; reload the page and try again", "フォームが不正な状態で届きました。ページを再読み込みしてもう一度お試しください", "表單送達時已損壞; 請重新載入頁面後再試一次"),
    ("too_many_parts", "o formulário chegou com defeito; recarregue a página e tente de novo", "the form arrived damaged; reload the page and try again", "フォームが不正な状態で届きました。ページを再読み込みしてもう一度お試しください", "表單送達時已損壞; 請重新載入頁面後再試一次"),
    ("malformed_multipart", "o formulário chegou com defeito; recarregue a página e tente de novo", "the form arrived damaged; reload the page and try again", "フォームが不正な状態で届きました。ページを再読み込みしてもう一度お試しください", "表單送達時已損壞; 請重新載入頁面後再試一次"),
    ("unsupported_media_type", "o formulário chegou com defeito; recarregue a página e tente de novo", "the form arrived damaged; reload the page and try again", "フォームが不正な状態で届きました。ページを再読み込みしてもう一度お試しください", "表單送達時已損壞; 請重新載入頁面後再試一次"),
    ("not_pdf", "este arquivo não é um PDF", "this file is not a PDF", "このファイルはPDFではありません", "這個檔案不是 PDF"),
    ("truncated", "o PDF parece cortado; exporte de novo", "the PDF looks cut short; export it again", "PDFが途中で切れているようです。もう一度書き出してください", "PDF 似乎被截斷; 請重新匯出"),
    ("active_content", "o PDF tem script, anexo ou ação de abertura; exporte de novo sem isso", "the PDF has a script, an attachment or an open action; export it again without them", "PDFにスクリプト、添付ファイルまたは開く動作が含まれています。それらを除いてもう一度書き出してください", "PDF 含有指令碼、附件或開啟動作; 請去除後重新匯出"),
    ("pdf_encrypted", "o PDF é criptografado e não dá para verificá-lo; exporte de novo sem senha", "the PDF is encrypted and cannot be checked; export it again without a password", "PDFは暗号化されていて確認できません。パスワードなしでもう一度書き出してください", "PDF 已加密，無法查核; 請解除密碼後重新匯出"),
    ("pdf_unscannable", "não foi possível verificar o PDF por dentro; exporte de novo (por exemplo, com outro programa)", "the PDF could not be checked inside; export it again (for example, with another program)", "PDFの内部を確認できませんでした。別のプログラムなどでもう一度書き出してください", "無法查核 PDF 內部; 請重新匯出（例如用其他程式）"),
    ("too_large", "o arquivo passa de 20 MB", "the file is over 20 MB", "ファイルが20 MBを超えています", "檔案超過 20 MB"),
    ("duplicate", "esta conta já enviou este arquivo", "this account already sent this file", "このアカウントはすでにこのファイルを送信しています", "這個帳號已送出過這個檔案"),
    ("quota_exceeded", "o espaço para estudos está cheio; tente mais tarde", "the space for studies is full; try again later", "研究の保存領域がいっぱいです。後でもう一度お試しください", "研究儲存空間已滿; 請稍後再試"),
    ("account_too_new", "a conta do GitHub precisa ter pelo menos 7 dias", "the GitHub account must be at least 7 days old", "GitHubアカウントは7日以上必要です", "GitHub 帳號需至少滿 7 天"),
    ("rate_limited", "muitos envios em pouco tempo; espere um minuto", "too many requests; wait a minute", "短時間に送信が多すぎます。1分ほどお待ちください", "短時間內送出過多; 請稍等一分鐘"),
    ("unauthorized", "entre com o GitHub primeiro", "log in with GitHub first", "先にGitHubでログインしてください", "請先用 GitHub 登入"),
    ("too_soon", "um envio por conta a cada 10 minutos", "one submission per account every 10 minutes", "1アカウントにつき10分に1回送信できます", "每個帳號每 10 分鐘限送出一次"),
    ("daily_limit", "no máximo 10 envios por conta em 24 horas", "at most 10 submissions per account in 24 hours", "1アカウントにつき24時間で最大10回送信できます", "每個帳號每 24 小時最多送出 10 次"),
    ("csrf", "a sessão do formulário venceu; recarregue a página", "the form session ended; reload the page", "フォームのセッションが切れました。ページを再読み込みしてください", "表單工作階段已過期; 請重新載入頁面"),
    ("not_github", "use o link do repositório no GitHub", "use the link of the repository on GitHub", "GitHubのリポジトリのリンクを使ってください", "請使用 GitHub 儲存庫的連結"),
    ("bad_archive", "use um link no Zenodo, no arXiv ou no aiXiv", "use a link on Zenodo, arXiv or aiXiv", "Zenodo、arXivまたはaiXivのリンクを使ってください", "請使用 Zenodo、arXiv 或 aiXiv 的連結")
  ]

codes :: [Text]
codes = [c | (c, _, _, _, _) <- table]

limits :: Text -> (Int, Int)
limits = \case
  "title" -> (titleMin, titleMax)
  "abstract" -> (abstractMin, abstractMax)
  "ai_models" -> (0, aiModelsMax)
  "ai_process" -> (0, aiProcessMax)
  "authors" -> (1, authorsMax)
  "sources" -> (0, sourcesMax)
  _ -> (0, linkMax)

-- | The message of an error in a language. A code with no row falls back to the API's English text.
text :: Language -> FieldError -> Text
text lang e = case [r | r@(c, _, _, _, _) <- table, c == e.code] of
  [] -> e.message
  (_, pt, en, ja, zh) : _ ->
    let (lo, hi) = limits e.field
        sentence = case lang of
          En -> en
          Ja -> ja
          ZhHant -> zh
          PtBr -> pt
     in T.replace "{hi}" (T.pack (show hi)) (T.replace "{lo}" (T.pack (show lo)) sentence)
