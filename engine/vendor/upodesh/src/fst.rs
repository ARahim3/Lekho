use fst::raw::{Fst, Node};

#[derive(Clone)]
pub struct FstTree<D: AsRef<[u8]>> {
    fst: Fst<D>,
}

impl<D: AsRef<[u8]>> FstTree<D> {
    pub fn from_fst(data: D) -> FstTree<D> {
        let fst = Fst::new(data).expect("Failed to create FST from bytes");
        Self { fst }
    }

    pub fn match_longest_common_prefix<'a>(&self, prefix: &'a str) -> (&'a str, &'a str, bool) {
        let mut iter = prefix.chars();
        let mut index = 0;
        let mut node = self.fst.root();

        while let Some(c) = iter.next() {
            match node.find_input(c as u8) {
                Some(addr) => {
                    node = self.fst.node(node.transition_addr(addr));
                    index += c.len_utf8();
                }
                None => break,
            }
        }

        let (matched_prefix, remaining) = prefix.split_at(index);

        (matched_prefix, remaining, node.is_final())
    }

    pub fn matching_node<'a>(&'a self, word: &str) -> Option<FstNode<'a, D>> {
        let mut iter = word.chars();
        let mut node = self.fst.root();

        while let Some(c) = iter.next() {
            match node.find_input(c as u8) {
                Some(addr) => {
                    node = self.fst.node(node.transition_addr(addr));
                }
                None => return None,
            }
        }

        Some(FstNode {
            fst: &self.fst,
            node,
            word: word.to_string(),
        })
    }
}

#[cfg(test)]
impl FstTree<Vec<u8>> {
    fn from_strings(mut set: Vec<&str>) -> Self {
        set.sort();

        let mut builder = fst::raw::Builder::memory();

        for word in set {
            // Convert each Bengali character to its single byte representation
            let numbered_word = word.chars().map(|c| c as u8).collect::<Vec<u8>>();
            builder.add(&numbered_word).unwrap();
        }

        Self {
            fst: builder.into_fst(),
        }
    }
}

#[derive(Clone)]
pub struct FstNode<'a, D: AsRef<[u8]>> {
    fst: &'a Fst<D>,
    node: Node<'a>,
    word: String,
}

impl<'a, D: AsRef<[u8]>> FstNode<'a, D> {
    pub fn get_matching_node(&self, suffix: &str) -> Option<FstNode<'a, D>> {
        let mut iter = suffix.chars();
        let mut node = self.node;

        while let Some(c) = iter.next() {
            match node.find_input(c as u8) {
                Some(addr) => {
                    node = self.fst.node(node.transition_addr(addr));
                }
                None => return None,
            }
        }

        let word = self.word.clone() + suffix;

        Some(FstNode {
            fst: self.fst,
            node,
            word,
        })
    }

    pub fn get_matching_node_by_char(&self, suffix: char) -> Option<FstNode<'a, D>> {
        let mut node = self.node;

        match node.find_input(suffix as u8) {
            Some(addr) => {
                node = self.fst.node(node.transition_addr(addr));
            }
            None => return None,
        }

        Some(FstNode {
            fst: self.fst,
            node,
            word: format!("{}{}", self.word, suffix),
        })
    }

    pub fn get_word(self) -> Option<String> {
        if self.node.is_final() {
            Some(self.word)
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_match_longest_common_prefix() {
        let fst = FstTree::from_strings(vec![
            "ক",
            "কখগ",
            "কখগঘঙ",
            "চ",
            "চছজ",
            "চছজঝঞ",
            "১",
            "a",
            "bc",
            "abcd",
        ]);

        assert_eq!(fst.match_longest_common_prefix("ক"), ("ক", "", true));
        assert_eq!(
            fst.match_longest_common_prefix("ক1234"),
            ("ক", "1234", true)
        );
        assert_eq!(fst.match_longest_common_prefix("1234"), ("", "1234", false));
        assert_eq!(
            fst.match_longest_common_prefix("কখগঘঙচছজঝঞ"),
            ("কখগঘঙ", "চছজঝঞ", true)
        );

        assert_eq!(fst.match_longest_common_prefix("a"), ("a", "", true));
        assert_eq!(fst.match_longest_common_prefix("a123"), ("a", "123", true));
        assert_eq!(
            fst.match_longest_common_prefix("abcdefg"),
            ("abcd", "efg", true)
        );
    }

    #[test]
    fn test_find_matching_node() {
        let fst = FstTree::from_strings(vec!["ক", "কখ", "কখগঘঙচছ"]);

        let n1 = fst.matching_node("ক").unwrap();

        let n2 = n1.get_matching_node("খ").unwrap();

        _ = n2.get_matching_node("গঘ").unwrap();

        _ = fst.matching_node("কখগঘ").unwrap();
    }

    #[test]
    fn test_get_word() {
        let trie = FstTree::from_strings(vec!["ক", "কখ", "কখগঘঙচছ"]);

        let n1 = trie.matching_node("ক").unwrap();
        assert_eq!(n1.clone().get_word(), Some("ক".to_string()));

        let n2 = n1.get_matching_node("খ").unwrap();
        assert_eq!(n2.clone().get_word(), Some("কখ".to_string()));

        let n3 = n2.get_matching_node("গঘ").unwrap();
        assert_eq!(n3.get_word(), None);

        let n4 = trie.matching_node("কখগঘ").unwrap();
        assert_eq!(n4.get_word(), None);
    }
}
