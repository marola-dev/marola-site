//// The colour band of a score. The page colours by CSS class, never by an
//// inline style: its CSP blocks `style=`.

import gleam/option.{type Option, None, Some}

pub type Band {
  Unscored
  Avoid
  Poor
  Fair
  Good
}

/// No score is `Unscored`; an unfit beach or a score of 0 or less is `Avoid`.
pub fn of_score(score: Option(Int), unfit: Bool) -> Band {
  case score {
    None -> Unscored
    Some(s) if unfit || s <= 0 -> Avoid
    Some(s) if s >= 70 -> Good
    Some(s) if s >= 40 -> Fair
    Some(_) -> Poor
  }
}

pub fn css_class(band: Band) -> String {
  case band {
    Unscored -> "cna"
    Avoid -> "c0"
    Poor -> "c1"
    Fair -> "c40"
    Good -> "c70"
  }
}
