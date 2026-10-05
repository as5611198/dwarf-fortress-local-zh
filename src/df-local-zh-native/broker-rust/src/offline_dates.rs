//! Exact vanilla calendar formats. No regular expression or per-save inventory.
const MONTHS: [(&str, &str, &str, &str, &str); 12] = [
  ("Granite", "花崗岩月", "花岗岩月", "early spring", "初春"),
  ("Slate", "板岩月", "板岩月", "midspring", "仲春"),
  ("Felsite", "霏細岩月", "霏细岩月", "late spring", "暮春"),
  ("Hematite", "赤鐵礦月", "赤铁矿月", "early summer", "初夏"),
  ("Malachite", "孔雀石月", "孔雀石月", "midsummer", "仲夏"),
  ("Galena", "方鉛礦月", "方铅矿月", "late summer", "暮夏"),
  ("Limestone", "石灰岩月", "石灰岩月", "early autumn", "初秋"),
  ("Sandstone", "砂岩月", "砂岩月", "midautumn", "仲秋"),
  ("Timber", "林木月", "林木月", "late autumn", "暮秋"),
  ("Moonstone", "月光石月", "月光石月", "early winter", "初冬"),
  ("Opal", "蛋白石月", "蛋白石月", "midwinter", "仲冬"),
  ("Obsidian", "黑曜石月", "黑曜石月", "late winter", "暮冬"),
];

fn decimal(source: &str, max: u32) -> Option<u32> {
  if source.is_empty() || source.len() > 10 || !source.bytes().all(|b| b.is_ascii_digit())
    || (source.len() > 1 && source.starts_with('0')) { return None; }
  source.parse::<u32>().ok().filter(|n| *n <= max)
}

fn day_month(source: &str, simplified: bool) -> Option<(&str, &str, &str, &str)> {
  let (ordinal, month) = source.split_once(' ')?;
  let split = ordinal.bytes().take_while(|b| b.is_ascii_digit()).count();
  let (number, suffix) = ordinal.split_at(split);
  let day = decimal(number, 28)?;
  if day == 0 { return None; }
  let expected = match day {
    11..=13 => "th", _ => match day % 10 { 1 => "st", 2 => "nd", 3 => "rd", _ => "th" },
  };
  if suffix != expected { return None; }
  let entry = MONTHS.iter().find(|entry| entry.0 == month)?;
  Some((number, if simplified { entry.2 } else { entry.1 }, entry.3, entry.4))
}

pub(crate) fn lookup(source: &str, simplified: bool) -> Option<String> {
  if source.len() > 192 { return None; }
  if let Some(body) = source.strip_prefix("This event occurred on the ") {
    let body = body.strip_suffix('.')?;
    let (day, year) = body.split_once(" in the year ")?;
    decimal(year, i32::MAX as u32)?;
    let (day, month, _, _) = day_month(day, simplified)?;
    return Some(format!("{}{year}年{month}{day}日。", if simplified {"此事件发生于"} else {"此事件發生於"}));
  }
  let (date, tail) = source.split_once(", ")?;
  let (day, month, expected_season, season_zh) = day_month(date, simplified)?;
  let (year, season) = if let Some((season, year)) = tail.split_once(", ") {
    if season != expected_season { return None; }
    (year, format!("{season_zh} "))
  } else { (tail, String::new()) };
  decimal(year, i32::MAX as u32)?;
  Some(format!("{year}年{season}{month}{day}日"))
}

#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn every_month_and_ordinal_is_bounded_and_keeps_numbers() {
    for simplified in [false, true] {
      for &(month, hant, hans, season, season_zh) in &MONTHS {
        for day in 1..=28 {
          let suffix = match day {11..=13=>"th",_=>match day%10 {1=>"st",2=>"nd",3=>"rd",_=>"th"}};
          let localized = if simplified {hans} else {hant};
          assert_eq!(lookup(&format!("{day}{suffix} {month}, 1234"),simplified),Some(format!("1234年{localized}{day}日")));
          assert_eq!(lookup(&format!("{day}{suffix} {month}, {season}, 1234"),simplified),Some(format!("1234年{season_zh} {localized}{day}日")));
        }
      }
    }
  }
}
