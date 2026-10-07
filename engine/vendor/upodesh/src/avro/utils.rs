pub fn fix_string(s: &str) -> String {
    let s = s.trim();
    let mut prev = ' ';
    let mut result = String::new();

    for (i, c) in s.char_indices() {
        // Fix string for o. In the beginning, after punctuations etc it should be capital O
        if (c == 'o' || c == 'O') && (i == 0 || !prev.is_ascii_alphabetic()) {
            result.push('O');
        } else if c.is_ascii_alphanumeric() || c == '`' {
            result.push(c.to_ascii_lowercase());
        }

        prev = c;
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fix_string() {
        assert_eq!(fix_string("o"), "O");
        assert_eq!(fix_string("o!"), "O");
        assert_eq!(fix_string("o!o"), "OO");
        assert_eq!(fix_string("osomapto"), "Osomapto");
        assert_eq!(fix_string("6t``"), "6t``");
    }
}
