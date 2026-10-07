use std::collections::HashSet;

use once_cell::sync::Lazy;

use crate::WORDS;

const CHARS: [char; 61] = [
    'অ', 'আ', 'ই', 'ঈ', 'উ', 'ঊ', 'ঋ', 'এ', 'ঐ', 'ও', 'ঔ', 'া', 'ি', 'ী', 'ু', 'ূ', 'ৃ', 'ে', 'ৈ', 'ো',
    'ৌ', 'ক', 'খ', 'গ', 'ঘ', 'ঙ', 'চ', 'ছ', 'জ', 'ঝ', 'ঞ', 'ট', 'ঠ', 'ড', 'ঢ', 'ণ', 'ত', 'থ', 'দ',
    'ধ', 'ন', 'প', 'ফ', 'ব', 'ভ', 'ম', 'য', 'র', 'ল', 'শ', 'ষ', 'স', 'হ', 'ৎ', 'ড়', 'ঢ়', 'য়', 'ং',
    'ঃ', 'ঁ', '্',
];

pub fn suggest(word: &str) -> Vec<String> {
    if word.is_empty() {
        return Vec::new();
    }
    
    let words = Lazy::force(&WORDS);

    let need_chars_upto = match word.chars().count() {
        1 => 0,
        2..=3 => 1,
        _ => 5,
    };

    let node = if let Some(n) = words.matching_node(word) {
        n
    } else {
        return Vec::new();
    };

    let mut nodes: Vec<_> = CHARS
        .iter()
        .filter_map(|&c| node.get_matching_node_by_char(c))
        .collect();

    for _ in 0..(need_chars_upto - 1) {
        let new_nodes: Vec<_> = nodes
            .iter()
            .flat_map(|node| {
                CHARS
                    .iter()
                    .filter_map(|&c| node.get_matching_node_by_char(c))
            })
            .collect();

        nodes.extend(new_nodes);
    }

    let suggestions = nodes
        .into_iter()
        .filter_map(|n| n.get_word())
        .collect::<HashSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();

    suggestions
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sort(mut vec: Vec<String>) -> Vec<String> {
        vec.sort();
        vec
    }

    #[test]
    fn test_suggestions() {
        assert_eq!(sort(sort(suggest(""))), Vec::<String>::new());
        assert_eq!(sort(sort(suggest("আমা"))), ["আমান", "আমার", "আমায়"]);
        assert_eq!(
            sort(sort(suggest("ই"))),
            ["ইজ", "ইট", "ইন", "ইফ", "ইভ", "ইহ"]
        );
        assert_eq!(
            sort(sort(suggest("কম্পি"))),
            [
                "কম্পিউটার",
                "কম্পিউটিং",
                "কম্পিউটেশন",
                "কম্পিটিশন",
                "কম্পিত",
                "কম্পিতা"
            ]
        );
        assert_eq!(sort(sort(suggest("আইনস্"))), ["আইনস্টাইন"]);
        assert_eq!(sort(sort(suggest("খ(১"))), Vec::<String>::new());
        assert_eq!(sort(sort(suggest("1"))), Vec::<String>::new());
    }
}
