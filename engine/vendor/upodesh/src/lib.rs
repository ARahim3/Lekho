use once_cell::sync::Lazy;

use crate::fst::FstTree;

/// The FST containing the valid Bengali words for suggestions.
static WORDS: Lazy<FstTree<&[u8]>> = Lazy::new(|| FstTree::from_fst(include_bytes!("words.fst")));

pub mod avro;
pub mod bangla;
mod fst;
