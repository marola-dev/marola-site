-- | What the form says for each error code, in both languages, in one place. The API keeps its
-- English @message@; the web form shows these next to the fields. @{lo}@ and @{hi}@ are the limits.
module Marola.Server.Messages (table, codes, text) where

import Data.Text (Text)
import Data.Text qualified as T
import Marola.Layout (Language (..))
import Marola.Study

-- | code, pt-BR, English.
table :: [(Text, Text, Text)]
table =
  [ ("required", "preencha este campo", "fill in this field"),
    ("too_short", "escreva pelo menos {lo} caracteres", "write at least {lo} characters"),
    ("too_long", "escreva no máximo {hi} caracteres", "write at most {hi} characters"),
    ("too_many", "há linhas demais: o máximo é {hi}", "there are too many lines: the most is {hi}"),
    ("invalid", "este valor não é válido", "this value is not valid"),
    ("unknown_value", "escolha uma das opções da lista", "pick one of the options in the list"),
    ("bad_name", "cada nome precisa de 2 a 120 caracteres", "each name needs 2 to 120 characters"),
    ("bad_orcid", "o ORCID iD não é válido; confira o dígito final", "the ORCID iD is not valid; check the last digit"),
    ("bad_link", "use um link que comece com https://", "use a link that starts with https://"),
    ("must_be_true", "confirme que você pode publicar este arquivo", "confirm that you may publish this file"),
    ("invalid_utf8", "o texto tem caracteres que não dá para ler", "the text has characters that cannot be read"),
    ("duplicate_field", "o formulário chegou com defeito; recarregue a página e tente de novo", "the form arrived damaged; reload the page and try again"),
    ("unknown_field", "o formulário chegou com defeito; recarregue a página e tente de novo", "the form arrived damaged; reload the page and try again"),
    ("too_many_parts", "o formulário chegou com defeito; recarregue a página e tente de novo", "the form arrived damaged; reload the page and try again"),
    ("malformed_multipart", "o formulário chegou com defeito; recarregue a página e tente de novo", "the form arrived damaged; reload the page and try again"),
    ("unsupported_media_type", "o formulário chegou com defeito; recarregue a página e tente de novo", "the form arrived damaged; reload the page and try again"),
    ("not_pdf", "este arquivo não é um PDF", "this file is not a PDF"),
    ("truncated", "o PDF parece cortado; exporte de novo", "the PDF looks cut short; export it again"),
    ("active_content", "o PDF tem script, anexo ou ação de abertura; exporte de novo sem isso", "the PDF has a script, an attachment or an open action; export it again without them"),
    ("pdf_encrypted", "o PDF é criptografado e não dá para verificá-lo; exporte de novo sem senha", "the PDF is encrypted and cannot be checked; export it again without a password"),
    ("pdf_unscannable", "não foi possível verificar o PDF por dentro; exporte de novo (por exemplo, com outro programa)", "the PDF could not be checked inside; export it again (for example, with another program)"),
    ("too_large", "o arquivo passa de 20 MB", "the file is over 20 MB"),
    ("duplicate", "esta conta já enviou este arquivo", "this account already sent this file"),
    ("quota_exceeded", "o espaço para estudos está cheio; tente mais tarde", "the space for studies is full; try again later"),
    ("account_too_new", "a conta do GitHub precisa ter pelo menos 7 dias", "the GitHub account must be at least 7 days old"),
    ("rate_limited", "muitos envios em pouco tempo; espere um minuto", "too many requests; wait a minute"),
    ("unauthorized", "entre com o GitHub primeiro", "log in with GitHub first"),
    ("too_soon", "um envio por conta a cada 10 minutos", "one submission per account every 10 minutes"),
    ("daily_limit", "no máximo 10 envios por conta em 24 horas", "at most 10 submissions per account in 24 hours"),
    ("csrf", "a sessão do formulário venceu; recarregue a página", "the form session ended; reload the page")
  ]

codes :: [Text]
codes = [c | (c, _, _) <- table]

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
text lang e = case [r | r@(c, _, _) <- table, c == e.code] of
  [] -> e.message
  (_, pt, en) : _ ->
    let (lo, hi) = limits e.field
     in T.replace "{hi}" (T.pack (show hi)) (T.replace "{lo}" (T.pack (show lo)) (if lang == En then en else pt))
