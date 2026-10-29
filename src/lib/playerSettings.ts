import { Settings, TabRhythmMode, StaveProfile, ScrollMode, LayoutMode, NotationElement, Environment, PlayerMode, PlayerOutputMode } from '@coderline/alphatab';

/**
 * 密集和弦小节智能防重叠：单小节内多和弦（>2个或间距紧密）时自动降级为
 * 清爽和弦字母名，避免多个 50px 指法图互相覆盖。
 *
 * 歌词必须保留 AlphaTab 原生的 LyricsGlyph 布局。此前对私有 doLayout() 的全局
 * 覆盖把固定像素塞进 glyph 内部，既不会识别减时横线/连音线，又会改变 effect band
 * 的总高度，导致不同节奏型下的歌词间距不稳定。
 */
export function installScoreLayoutFixes(): void {
  // 和弦图/和弦名防重叠智能调度
  const env = Environment as any;
  const renderers = env.renderEngines?.default?.renderers || env.defaultRenderers;
  const slashFactory = renderers?.find((f: any) => f.constructor?.name === 'SlashBarRendererFactory');
  if (slashFactory) {
    const chordInfo = (slashFactory as any).effectBands?.find((eb: any) => eb.effect?.constructor?.name === 'ChordsEffectInfo')?.effect;
    const ChordProto = chordInfo?.constructor?.prototype;
    if (ChordProto && !ChordProto.__collisionPatched) {
      ChordProto.__collisionPatched = true;
      const origCreateNewGlyph = ChordProto.createNewGlyph;
      ChordProto.createNewGlyph = function (renderer: any, beat: any) {
        if (!beat.hasChord || !beat.chord) return null;
        const isDiagramMode = !!beat.voice?.bar?.staff?.track?.score?.stylesheet?.globalDisplayChordDiagramsInScore;

        if (isDiagramMode) {
          const chordBeats = beat.voice?.beats?.filter((b: any) => b.hasChord && b.chord) || [];
          if (chordBeats.length <= 2) {
            if (chordBeats.length === 2) {
              const barDur = beat.voice?.bar?.duration || 1920;
              const diff = Math.abs((chordBeats[1].playbackStart ?? 0) - (chordBeats[0].playbackStart ?? 0));
              if (diff >= barDur * 0.4) {
                // 空间充裕（>=半小节）：正常绘制 50px 指法图
                return origCreateNewGlyph.call(this, renderer, beat);
              }
            } else {
              // 单和弦小节：空间充足，绘制完整指法图
              return origCreateNewGlyph.call(this, renderer, beat);
            }
          }
        }

        // 密集和弦小节（如一小节 3~4 个和弦）：降级为清晰文本和弦名（C, G, Am, G），杜绝多指法图叠加重叠
        const score = beat.voice?.bar?.staff?.track?.score;
        const prev = score?.stylesheet?.globalDisplayChordDiagramsInScore;
        if (score?.stylesheet) score.stylesheet.globalDisplayChordDiagramsInScore = false;
        const result = origCreateNewGlyph.call(this, renderer, beat);
        if (score?.stylesheet) score.stylesheet.globalDisplayChordDiagramsInScore = prev;
        return result;
      };
    }
  }
}

/** 谱面统一字体：Cascadia Code（本机字体打包自托管；CJK 回退微软雅黑） */
const SCORE_FONT = ['Cascadia Code', 'Microsoft YaHei', '微软雅黑', 'sans-serif'];
/** 中文与数字字体：方正小标宋简体（标题/艺人/歌词/品数/简谱数字/小节号/指法数字等） */
const CJK_FONT = ['方正小标宋简体', 'Cascadia Code', 'Microsoft YaHei', '微软雅黑', 'sans-serif'];

/** 以参考站 guistudy 的渲染资源为准微调：字号/字体族/条号颜色等 */
function alignRenderingResources(s: Settings) {
  const res = s.display.resources as any;
  // 标题/副标题/歌词字体（参考站 24/16/14px Arial；本地默认 Georgia 偏大偏衬线）
  if (res.titleFont) {
    res.titleFont.size = 22;
    res.titleFont.families = [...CJK_FONT];
  }
  if (res.subTitleFont) {
    res.subTitleFont.size = 15;
    res.subTitleFont.families = [...CJK_FONT];
  }
  if (res.wordsFont) {
    res.wordsFont.size = 14;
    res.wordsFont.families = [...CJK_FONT];
  }
  if (res.copyrightFont) {
    res.copyrightFont.size = 0;
  }
  if (res.effectFont) {
    res.effectFont.size = 11;
    res.effectFont.style = 0; // FontStyle.Plain
    res.effectFont.families = [...SCORE_FONT];
  }
  // 条号颜色：参考站为半透明黑（本地默认 #C80000 红色）
  // 品数/数字谱/小节号/指法图数字等文字同样换用 Cascadia Code
  if (res.tablatureFont) {
    res.tablatureFont.families = [...CJK_FONT];
    res.tablatureFont.size = 13; // 品数 13px：在加大后的弦距下有清晰间隙
  }
  if (res.numberedNotationFont) {
    res.numberedNotationFont.families = [...CJK_FONT];
    res.numberedNotationFont.size = 12; // 数字谱旋律数字 12px：避免相邻数字盒重叠
  }
  // 注意：elementFonts 在构造时用 withSize() 复制了默认字体副本，直接改 res.effectFont（共享静态实例）不会传导；
  // 必须逐项改 map 里的条目。effectFont 系文字（和弦名/歌词/Capo/指法/标记等）统一 Cascadia Code 正体。
  // 中文/数字类元素（歌词/小节号/指法数字等）→ 方正小标宋简体
  for (const el of [
    NotationElement.ScoreArtist, NotationElement.ScoreCopyright,
    NotationElement.BarNumber, NotationElement.RepeatCount, NotationElement.ChordDiagramFretboardNumbers,
    NotationElement.EffectLyrics, NotationElement.EffectFingering, NotationElement.EffectCapo, NotationElement.ChordDiagrams,
    NotationElement.EffectTempo, NotationElement.GuitarTuning, NotationElement.TrackNames,
  ]) {
    const f = res.elementFonts?.get(el);
    if (f) {
      f.families = [...CJK_FONT];
      f.style = 0; // 全部正体（本机无斜体变体，避免合成斜体）
    }
  }
  // 拉丁类元素（和弦名/滑音/方向/演奏记号等）→ Cascadia Code
  for (const el of [
    NotationElement.ScoreBendSlur,
    NotationElement.EffectChordNames,
    NotationElement.EffectMarker, NotationElement.EffectText,
    NotationElement.EffectDirections, NotationElement.EffectBeatTimer,
    NotationElement.EffectHammerOnPullOffText, NotationElement.EffectSlideText, NotationElement.EffectHarmonics,
    NotationElement.EffectLetRing, NotationElement.EffectPalmMute, NotationElement.EffectWhammyBar,
    NotationElement.EffectPickSlide, NotationElement.EffectTripletFeel, NotationElement.EffectRasgueado,
    NotationElement.EffectFreeTime, NotationElement.EffectTap, NotationElement.EffectBeatBarre,
    NotationElement.EffectAlternateEndings,
  ]) {
    const f = res.elementFonts?.get(el);
    if (f) {
      f.families = [...SCORE_FONT];
      f.style = 0;
    }
  }
  // 字号：和弦名 11、歌词 13（中文可读性）、其余效果类 11
  const sizeEls: Array<[NotationElement, number]> = [
    [NotationElement.ScoreArtist, 15],
    [NotationElement.EffectChordNames, 11],
    [NotationElement.EffectLyrics, 13],
  ];
  for (const [el, sz] of sizeEls) {
    const f = res.elementFonts?.get(el);
    if (f) f.size = sz;
  }
  if (res.barNumberColor) {
    res.barNumberColor.raw = ((128 & 0xff) << 24) | 0; // rgba(0,0,0,0.5)
    res.barNumberColor.updateRgba();
  }
  // 小节分隔线颜色：参考站 rgba(44,44,44,1)
  if (res.barSeparatorColor) {
    res.barSeparatorColor.raw = ((255 & 0xff) << 24) | (44 << 16) | (44 << 8) | 44;
    res.barSeparatorColor.updateRgba();
  }
  // Tab 弦距：默认 13.5 偏紧导致堆叠品数盒重叠；加大到 17（实测约 14.3px 弦距）
  if (res.engravingSettings) {
    res.engravingSettings.tabLineSpacing = 17;
  }
}

/** 构建与原站一致的 alphaTab 播放器配置（官方 1.8.4 有效属性） */
export function createScoreSettings(): Settings {
  const s = new Settings();
  s.core.scriptFile = '/alphaTab.js';
  s.core.fontDirectory = '/font/';
  s.core.useWorkers = false;
  s.core.enableLazyLoading = false; // chart strip above scroll container changes viewport; lazy loading leaves partials unrendered
  s.importer.beatTextAsLyrics = true;
  s.notation.rhythmMode = TabRhythmMode.ShowWithBars;
  s.notation.rhythmHeight = 25;
  // 与目标站一致：和弦名按拍/按 system 渲染（EffectChordNames），不渲染顶部和弦图列表容器（ChordDiagrams）。
  // 实测参考站每个 system 上方都有一行与拍对齐的和弦名，无独立和弦图区；本地此前用 ChordDiagrams=true
  // 会把所有唯一和弦集中渲染到第一行上方（用户反馈「和弦统一放到上方」的根因）。
  // 注意：notation.elements 是 Map，必须用 .set()；方括号赋值不会写入 Map 条目
  s.notation.elements.set(NotationElement.ChordDiagrams, false);
  s.notation.elements.set(NotationElement.EffectChordNames, true);
  // 段落标记（主歌/副歌等）与首拍和弦名在共享效果行内固定位置重叠，参考站用魔改 AlphaTab 规避；
  // 本地保持官方 1.8.4 不改源码，先隐藏标记以保证无文字重叠（已知取舍，见 DEV_LOG）
  s.notation.elements.set(NotationElement.EffectMarker, false);
  s.notation.elements.set(NotationElement.EffectLyrics, true);
  // 与参考站一致：隐藏谱面头部冗余信息（调弦名/轨名/圆括号连音/力度记号等，消除力度记号带来的不规则行距跳变）
  s.notation.elements.set(NotationElement.GuitarTuning, false);
  s.notation.elements.set(NotationElement.TrackNames, false);
  s.notation.elements.set(NotationElement.ParenthesisOnTiedBends, false);
  s.notation.elements.set(NotationElement.EffectCapo, false);
  s.notation.elements.set(NotationElement.EffectTempo, false);
  s.notation.elements.set(NotationElement.EffectDynamics, false);
  s.notation.elements.set(NotationElement.EffectCrescendo, false);
  s.notation.elements.set(NotationElement.ScoreWords, false);
  s.notation.elements.set(NotationElement.ScoreMusic, false);
  s.notation.elements.set(NotationElement.ScoreWordsAndMusic, false);
  s.notation.elements.set(NotationElement.ScoreAlbum, false);
  s.display.scale = 0.84;
  s.display.stretchForce = 0.66;
  s.display.staveProfile = StaveProfile.Default;
  s.display.layoutMode = LayoutMode.Page;
  s.display.padding = [20, 36, 20, 36]; // [left, top, right, bottom]：顶部加大给谱面标题，底部留足间隙避免歌词被乐谱遮挡
  // 歌词多段（Verse 1 / Verse 2）行距：经 0.84 scale 补偿，设为 18 保证多段歌词从容舒展
  s.display.lyricLinesPaddingBetween = 18;
  // 谱面垂直间距：给头部标题、和弦名/指法图、简谱数字、多段歌词留出通透舒适的呼吸空间（充分考虑 scale 缩放）
  s.display.firstSystemPaddingTop = 22;
  s.display.systemPaddingTop = 20;
  s.display.systemPaddingBottom = 24;
  s.display.lastSystemPaddingBottom = 16;
  s.display.firstNotationStaffPaddingTop = 6;
  s.display.notationStaffPaddingTop = 48; // 次级谱表（简谱）与上方六线谱（TAB）之间的垂直间隙（充分拉开乐谱与简谱距离，彻底消除拥挤）
  s.display.notationStaffPaddingBottom = 30; // 六线谱底侧留白
  s.display.lastNotationStaffPaddingBottom = 60; // 简谱旋律线与下方歌词文字之间的垂直留白（彻底避免歌词字头与数字/连音线碰撞）
  s.display.effectBandPaddingBottom = 50; // 各 effect 带（和弦名/简谱/歌词）之间的垂直间距（宽松自然，避免歌词被乐谱遮挡）
  installScoreLayoutFixes();
  alignRenderingResources(s);
  s.player.enablePlayer = true;
  s.player.playerMode = PlayerMode.EnabledSynthesizer;
  // Keep the output path deterministic across HTTP/HTTPS. AlphaTab's
  // AudioWorklet path initializes asynchronously and can race pause/replay;
  // the ScriptProcessor path is also the one covered by our guarded output
  // implementation in ScorePlayer.
  s.player.outputMode = PlayerOutputMode.WebAudioScriptProcessor;
  s.player.bufferTimeInMilliseconds = 1000;
  s.player.enableCursor = true;
  s.player.enableAnimatedBeatCursor = true; // 启用 AlphaTab 官方单线毫秒级平滑跟随
  s.player.enableElementHighlighting = true; // 启用当前播放音符/小节实时高亮显示
  s.player.enableUserInteraction = true;
  s.player.scrollOffsetY = -40;
  // 离屏模式：仅当光标进入下一系统时才滚动，系统静止在视口内直至演奏完毕，避免连续滚动出现"半截系统"的残缺感
  s.player.scrollMode = ScrollMode.OffScreen;
  // 250ms 平滑滚动，给 AlphaTab 内部动画足够帧数（~15 帧）消除逐帧跳跃感
  s.player.scrollSpeed = 250;
  // 禁用原生平滑滚动，启用 AlphaTab 内部动画循环，使 scrollSpeed 生效
  s.player.nativeBrowserSmoothScroll = false;
  s.player.scrollElement = '#score-scroll';
  return s;
}
