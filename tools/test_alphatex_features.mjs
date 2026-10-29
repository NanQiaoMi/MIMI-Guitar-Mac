import { importer } from '@coderline/alphatab';

const sample = `\\title "完整技巧测试"
\\tempo 120
\\ts 4 4
\\track "吉他"
\\tuning E2 A2 D3 G3 B3 E4
.
(0.1 1.2 0.3 2.4 3.5).4{ch "C" txt "歌词"} (2.2{h}).4 (3.2{ss}).4 (5.2{v}).4 |
(7.2{b (2)}).4 (12.1{nh}).4 (0.6{pm}).4 (x.1).4 |
(2.3).8{tu 3} (4.3).8{tu 3} (5.3).8{tu 3} (0.1 1.2 2.3 2.4 0.5).2{ch "Am"} |
`;

const imp = new importer.AlphaTexImporter();
try {
  imp.initFromString(sample);
  const score = imp.readScore();
  console.log('✓ AlphaTex FULL TECHNIQUES SUCCESS! Bars:', score.tracks[0].staves[0].bars.length);
} catch (e) {
  console.error('FAILED:', e.message);
  console.error('Parser errors:', imp.parserDiagnostics);
}

