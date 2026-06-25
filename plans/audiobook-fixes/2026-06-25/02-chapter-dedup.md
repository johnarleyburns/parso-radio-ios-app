# Phase 1 — Chapter de-duplication

**Problem.** Every chapter appears 3× in the chapter list.

**Current behavior.** `InternetArchiveService.fetchTracksForIdentifier` selects MP3 files by format/extension but keeps EVERY matching file. IA ships multiple MP3 bitrate variants per chapter (e.g. 64k/128k/VBR), so each chapter yields N tracks with sequential part numbers. `partsAreClean` passes (one extension, sequential numbers) so the tripled set is cached/stored.

**Research signal.** Existing `InternetArchiveServiceTests.testFetchTracksForIdentifierPicksSingleFormat` only covers mixed formats (mp3+ogg+flac), never multi-MP3-variant.

**Design.**
```
chosen files ──▶ group by chapterKey(file)
   chapterKey = normalized(title) ?? filenameStem stripped of bitrate/size tokens
   within group: keep best by bitrateRank(format)  (320>256>192>VBR>128>64>MP3)
   ties / unknown: keep first in natural order
──▶ one file per chapter ──▶ natural sort ──▶ sequential partNumbers
```
Harden `partsAreClean`: reject when normalized chapter keys collide (forces re-probe of stale tripled DB rows).

**Data-model deltas.** None.

**Implementation steps.**
1. `MP3AudioFormatSelector.bitrateRank(_ format:) -> Int`.
2. Dedup helper in `InternetArchiveService` applied after format selection.
3. `PlayerViewModel.partsAreClean` collision check (add a chapter-key helper).

**Testing.** Unit: 64k/128k/VBR ×5 chapters → 5 unique sequential parts. `partsAreClean` false on tripled input. UI: seeded "Gallipoli" chapter list shows each chapter once.

**Open questions.** None.
