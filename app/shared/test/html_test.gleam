//// escape_html and safe_href, with the inputs an attacker would try.

import gleam/list
import gleam/string
import marola/html

pub fn escape_html_escapes_the_five_characters_test() {
  assert html.escape_html("<a href=\"x\" title='y'>&</a>")
    == "&lt;a href=&quot;x&quot; title=&#39;y&#39;&gt;&amp;&lt;/a&gt;"
}

pub fn escape_html_does_not_escape_twice_test() {
  assert html.escape_html("&lt;") == "&amp;lt;"
  assert html.escape_html("") == ""
  assert html.escape_html("ação · 日本 😀") == "ação · 日本 😀"
}

pub fn safe_href_allows_http_https_and_mailto_test() {
  assert html.safe_href("https://example.com/a?b=c#d")
    == Ok("https://example.com/a?b=c#d")
  assert html.safe_href("http://example.org") == Ok("http://example.org")
  assert html.safe_href("mailto:oi@marola.dev") == Ok("mailto:oi@marola.dev")
}

pub fn safe_href_ignores_case_of_the_scheme_test() {
  assert html.safe_href("HTTPS://EXAMPLE.COM") == Ok("HTTPS://EXAMPLE.COM")
  assert html.safe_href("MailTo:a@b.c") == Ok("MailTo:a@b.c")
}

pub fn safe_href_reads_the_url_as_a_browser_does_test() {
  assert html.safe_href("  https://a.com  ") == Ok("https://a.com")
  assert html.safe_href("\u{1}\u{2} https://a.com") == Ok("https://a.com")
  assert html.safe_href("https://a.com/x\ty\nz") == Ok("https://a.com/xyz")
  assert html.safe_href("https://a.com/\u{0}") == Ok("https://a.com/")
}

pub fn safe_href_refuses_script_and_data_schemes_test() {
  [
    "javascript:alert(1)",
    "JaVaScRiPt:alert(1)",
    "JAVASCRIPT:alert(1)",
    " javascript:alert(1)",
    "\u{0}javascript:alert(1)",
    "\u{1F}javascript:alert(1)",
    "java\tscript:alert(1)",
    "java\nscript:alert(1)",
    "java\rscript:alert(1)",
    "j\u{0}avascript:alert(1)",
    "javascript\t:alert(1)",
    "data:text/html,<script>alert(1)</script>",
    "DATA:text/html;base64,PHNjcmlwdD4=",
    "vbscript:msgbox(1)",
    "file:///etc/passwd",
    "ftp://example.com",
    "blob:https://example.com/x",
  ]
  |> list.each(fn(url) {
    assert html.safe_href(url) == Error(Nil)
  })
}

pub fn safe_href_refuses_what_is_not_an_absolute_link_test() {
  [
    "", " ", "\t\n", "//evil.example", "/relative", "#fragment", "?q=1", "https",
    "https//example.com", "https:", "mailto:", "ht tps://example.com",
    "\u{FEFF}https://example.com", "ｈttps://example.com", "1http://x.y",
    "javascript&colon;alert(1)", "https://example.com/\u{0}x",
    "https://example.com/\u{7F}", "https://example.com/\u{85}",
  ]
  |> list.each(fn(url) {
    assert html.safe_href(url) == Error(Nil)
  })
}

pub fn safe_href_only_ever_returns_an_allowed_scheme_test() {
  let attempts = [
    "javascript:1", "https://a.b", "\thttp://a.b", "mailto:x@y", "data:x",
    "  HTTPS://A.B", "java\u{9}script:1", "x:y",
  ]
  list.each(attempts, fn(url) {
    case html.safe_href(url) {
      Error(Nil) -> Nil
      Ok(href) -> {
        let lower = string.lowercase(href)
        assert string.starts_with(lower, "https:")
          || string.starts_with(lower, "http:")
          || string.starts_with(lower, "mailto:")
        assert !string.contains(href, "\t")
      }
    }
  })
}
