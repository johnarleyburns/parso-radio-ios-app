<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lorewave — Five Player Surfaces</title>
<style>
  :root{
    --bg:#faf9f5; --card:#ffffff; --bg2:#f1efe8; --bg3:#e9e7df;
    --text:#1f1f1d; --text2:#6b6a64; --text3:#9b9a92;
    --border:#e3e1d8; --border2:#cfcdc4; --info:#185fa5; --accent:#2f6fd0;
  }
  @media (prefers-color-scheme: dark){
    :root{
      --bg:#191917; --card:#222220; --bg2:#2b2a25; --bg3:#34332c;
      --text:#e9e8e0; --text2:#a8a79e; --text3:#76756d;
      --border:#3a392f; --border2:#4a4940; --info:#85b7eb; --accent:#3f82e0;
    }
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--text);
       font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
       line-height:1.5;padding:24px 16px}
  .page{max-width:680px;margin:0 auto}
  h1{font-size:20px;font-weight:600;margin:0 0 4px}
  .sub{font-size:13px;color:var(--text2);margin:0 0 18px}
  .ic{width:1em;height:1em;vertical-align:-0.125em;fill:none;stroke:currentColor;
      stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
  .ic.fill{fill:currentColor;stroke:none}
  .legend{display:flex;flex-wrap:wrap;gap:18px;padding:14px;background:var(--bg2);
          border-radius:12px;margin-bottom:16px}
  .lchip{display:flex;align-items:center;gap:8px;font-size:12.5px;color:var(--text2)}
  .sw{width:32px;height:32px;border-radius:8px;display:flex;align-items:center;
      justify-content:center;border:0.5px solid var(--border);background:var(--card);font-size:17px}
  .card{background:var(--card);border:0.5px solid var(--border);border-radius:14px;
        padding:14px 16px;margin-bottom:12px}
  .head{display:flex;align-items:baseline;gap:10px;margin-bottom:10px}
  .kname{font-size:16px;font-weight:600}
  .desc{font-size:12px;color:var(--text2)}
  .scrub{height:4px;border-radius:2px;background:var(--border2);position:relative;margin:6px 0 6px}
  .fill{position:absolute;left:0;top:0;bottom:0;border-radius:2px;background:var(--info)}
  .knob{position:absolute;top:50%;width:11px;height:11px;border-radius:50%;background:var(--info);
        transform:translate(-50%,-50%)}
  .times{display:flex;justify-content:space-between;font-size:11px;color:var(--text2)}
  .transport{display:flex;align-items:center;justify-content:center;gap:18px;margin:12px 0}
  .tbtn{width:46px;height:46px;border-radius:50%;border:0.5px solid var(--border2);
        display:flex;align-items:center;justify-content:center;background:var(--card);
        color:var(--info);font-size:20px}
  .tbtn .n{font-size:11px;font-weight:600;margin-left:1px}
  .tbtn.sm{width:38px;height:38px;color:var(--text2);font-size:17px}
  .tbtn.play{width:62px;height:62px;border:none;background:var(--accent);color:#fff;font-size:24px}
  .tbtn.play.big{width:74px;height:74px;font-size:28px}
  .sec{display:flex;gap:8px;padding:10px;background:var(--bg2);border-radius:12px;margin-top:6px}
  .scell{flex:1;min-width:0;display:flex;flex-direction:column;align-items:center;gap:5px;
         font-size:11px;color:var(--text2)}
  .scell .ci{font-size:18px;color:var(--text)}
  .scell.hl,.scell.hl .ci{color:var(--info)}
  .cap{font-size:12.5px;color:var(--text2);margin-top:10px}
  .cap b{color:var(--text);font-weight:600}
  .scene{height:48px;border-radius:10px;background:var(--bg3);display:flex;align-items:center;
         justify-content:center;color:var(--text3);font-size:12px;gap:6px}
  .pill{display:inline-flex;align-items:center;gap:6px;padding:7px 14px;border-radius:999px;
        border:0.5px solid var(--border2);font-size:12.5px;color:var(--text2)}
  .hi{color:var(--info)}
</style>
</head>
<body>
<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>
  <symbol id="play" viewBox="0 0 24 24"><path class="fill" d="M8 5v14l11-7z"/></symbol>
  <symbol id="pause" viewBox="0 0 24 24"><path d="M9 5v14M16 5v14"/></symbol>
  <symbol id="sback" viewBox="0 0 24 24"><path d="M7 6v12"/><path class="fill" d="M20 6 9 12l11 6z" stroke="none"/></symbol>
  <symbol id="sfwd" viewBox="0 0 24 24"><path d="M17 6v12"/><path class="fill" d="M4 6l11 6-11 6z" stroke="none"/></symbol>
  <symbol id="jback" viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-2.3-5.6"/><path d="M20 4v4h-4"/></symbol>
  <symbol id="jfwd" viewBox="0 0 24 24"><path d="M4 12a8 8 0 1 0 2.3-5.6"/><path d="M4 4v4h4"/></symbol>
  <symbol id="list" viewBox="0 0 24 24"><path d="M5 7h14M5 12h14M5 17h14"/></symbol>
  <symbol id="bookmark" viewBox="0 0 24 24"><path d="M7 4h10v16l-5-4-5 4z"/></symbol>
  <symbol id="moon" viewBox="0 0 24 24"><path d="M16 3a8 8 0 1 0 5.4 13.4A7 7 0 0 1 16 3z"/></symbol>
  <symbol id="gauge" viewBox="0 0 24 24"><path d="M5 17a7 7 0 1 1 14 0"/><path d="M12 17l4-4"/></symbol>
  <symbol id="shuffle" viewBox="0 0 24 24"><path d="M4 7h4l9 10h3M17 17l2 2 2-2M4 17h4l3-3.3M14 9.3 17 7l2-2 2 2M17 7h-1"/></symbol>
  <symbol id="repeat" viewBox="0 0 24 24"><path d="M4 9V8a3 3 0 0 1 3-3h11M15 2l3 3-3 3M20 15v1a3 3 0 0 1-3 3H6M9 22l-3-3 3-3"/></symbol>
  <symbol id="cast" viewBox="0 0 24 24"><path class="fill" d="M6 18h12l-6-7z" stroke="none"/></symbol>
  <symbol id="wind" viewBox="0 0 24 24"><path d="M3 8h12a2.5 2.5 0 1 0-2.5-2.5M3 16h15a2.5 2.5 0 1 1-2.5 2.5M3 12h9"/></symbol>
</defs></svg>

<div class="page">
  <h1>Five player surfaces</h1>
  <p class="sub">Each kind shows only its common controls. The back/forward buttons mean different things by kind — and never two things at once on one screen.</p>

  <div class="legend">
    <div class="lchip"><span class="sw hi"><svg class="ic"><use href="#jback"/></svg></span>Jog <b style="color:var(--text)">within</b> (±15/30s)</div>
    <div class="lchip"><span class="sw hi"><svg class="ic"><use href="#sback"/></svg></span>Whole <b style="color:var(--text)">track</b> (music only)</div>
    <div class="lchip"><span class="sw"><svg class="ic"><use href="#list"/></svg></span>Chapters · episodes · books → list or ⋯ menu</div>
  </div>

  <div class="card">
    <div class="head"><span class="kname">Music</span><span class="desc">radio-style shuffle pool</span></div>
    <div class="transport">
      <span class="tbtn sm"><svg class="ic"><use href="#shuffle"/></svg></span>
      <span class="tbtn"><svg class="ic"><use href="#sback"/></svg></span>
      <span class="tbtn play"><svg class="ic"><use href="#play"/></svg></span>
      <span class="tbtn"><svg class="ic"><use href="#sfwd"/></svg></span>
      <span class="tbtn sm"><svg class="ic"><use href="#repeat"/></svg></span>
    </div>
    <div class="cap">No scrub, no jog. <b>‹‹ / ›› = previous / next track.</b> Unambiguous because there's nothing to jog within.</div>
  </div>

  <div class="card">
    <div class="head"><span class="kname">Audiobook</span><span class="desc">sequential work · chapters</span></div>
    <div class="scrub"><div class="fill" style="width:38%"></div><div class="knob" style="left:38%"></div></div>
    <div class="times"><span>0:42</span><span>Book 5h 12m left</span><span>-12:30</span></div>
    <div class="transport">
      <span class="tbtn"><svg class="ic"><use href="#jback"/></svg><span class="n">15</span></span>
      <span class="tbtn play"><svg class="ic"><use href="#pause"/></svg></span>
      <span class="tbtn"><svg class="ic"><use href="#jfwd"/></svg><span class="n">30</span></span>
    </div>
    <div class="sec">
      <div class="scell"><svg class="ic ci"><use href="#gauge"/></svg>Speed</div>
      <div class="scell hl"><svg class="ic ci"><use href="#list"/></svg>Chapters</div>
      <div class="scell"><svg class="ic ci"><use href="#bookmark"/></svg>Bookmark</div>
      <div class="scell"><svg class="ic ci"><use href="#moon"/></svg>Sleep</div>
    </div>
    <div class="cap"><b>‹‹ / ›› = back 15s / forward 30s only.</b> Chapter jumps live in the Chapters list; prev/next book in the ⋯ menu.</div>
  </div>

  <div class="card">
    <div class="head"><span class="kname">Lecture</span><span class="desc">same as audiobook · relabeled</span></div>
    <div class="scrub"><div class="fill" style="width:55%"></div><div class="knob" style="left:55%"></div></div>
    <div class="times"><span>22:18</span><span class="hi">Series 2h 40m left</span><span>-18:02</span></div>
    <div class="transport">
      <span class="tbtn"><svg class="ic"><use href="#jback"/></svg><span class="n">15</span></span>
      <span class="tbtn play"><svg class="ic"><use href="#play"/></svg></span>
      <span class="tbtn"><svg class="ic"><use href="#jfwd"/></svg><span class="n">30</span></span>
    </div>
    <div class="sec">
      <div class="scell"><svg class="ic ci"><use href="#gauge"/></svg>Speed</div>
      <div class="scell hl"><svg class="ic ci"><use href="#list"/></svg>Lectures</div>
      <div class="scell"><svg class="ic ci"><use href="#bookmark"/></svg>Bookmark</div>
      <div class="scell"><svg class="ic ci"><use href="#moon"/></svg>Sleep</div>
    </div>
    <div class="cap">Identical layout — only the highlighted labels differ: <b>“Lectures”</b> and <b>“Series … left.”</b> One shared <code>SpokenControls</code> view drives both.</div>
  </div>

  <div class="card">
    <div class="head"><span class="kname">Podcast</span><span class="desc">sequential episodes · no chapters</span></div>
    <div class="scrub"><div class="fill" style="width:18%"></div><div class="knob" style="left:18%"></div></div>
    <div class="times"><span>3:10</span><span>-28:05</span></div>
    <div class="transport">
      <span class="tbtn"><svg class="ic"><use href="#jback"/></svg><span class="n">15</span></span>
      <span class="tbtn play"><svg class="ic"><use href="#play"/></svg></span>
      <span class="tbtn"><svg class="ic"><use href="#jfwd"/></svg><span class="n">30</span></span>
    </div>
    <div class="sec">
      <div class="scell"><svg class="ic ci"><use href="#gauge"/></svg>Speed</div>
      <div class="scell"><svg class="ic ci"><use href="#bookmark"/></svg>Bookmark</div>
      <div class="scell"><svg class="ic ci"><use href="#moon"/></svg>Sleep</div>
      <div class="scell"><svg class="ic ci"><use href="#cast"/></svg>AirPlay</div>
    </div>
    <div class="cap"><b>‹‹ / ›› = back 15s / forward 30s</b> (re-hear vs. skip ads). Episodes are chosen from the list, not the player.</div>
  </div>

  <div class="card">
    <div class="head"><span class="kname">Ambient</span><span class="desc">single looping soundscape</span></div>
    <div class="scene"><svg class="ic"><use href="#wind"/></svg>looping visual</div>
    <div class="transport">
      <span class="tbtn play big"><svg class="ic"><use href="#play"/></svg></span>
    </div>
    <div class="transport" style="margin-top:0;gap:14px">
      <span class="pill"><svg class="ic"><use href="#moon"/></svg>Sleep timer</span>
      <span class="pill"><svg class="ic"><use href="#cast"/></svg>AirPlay</span>
    </div>
    <div class="cap">It loops endlessly: <b>no scrub, no skip, no speed.</b> Just play/pause and a prominent sleep timer.</div>
  </div>

</div>
</body>
</html>