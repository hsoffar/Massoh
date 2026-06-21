/* Massoh pitch deck — native vector UML + sequence diagrams. */
const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.333 x 7.5
pres.author = "Massoh";
pres.title = "Massoh — an agent operating system for Claude Code";

const W = 13.333, H = 7.5;

// ---- palette ----
const INK="141B34", INK2="1E2A4A", PRIMARY="3D4CB8", PRIMARY_D="2A3690",
      ACCENT="12B5A0", ACCENT_D="0E9384", WARN="E8A33D", DANGER="E05656",
      BG="F5F6FA", CARD="FFFFFF", MUTED="64748B", BORDER="DFE3EC", ICE="CADCFC", INKSOFT="3A4straw";
const HEAD="Georgia", BODY="Calibri", MONO="Consolas";
const RECT = pres.shapes.RECTANGLE, RR = pres.shapes.ROUNDED_RECTANGLE,
      LINE = pres.shapes.LINE, OVAL = pres.shapes.OVAL, DIAMOND = pres.shapes.DIAMOND || "diamond";

const sh = () => ({ type:"outer", color:"0B1020", blur:7, offset:3, angle:135, opacity:0.16 });

let pageNo = 0;
function newSlide(dark=false){
  const s = pres.addSlide();
  s.background = { color: dark ? INK : BG };
  return s;
}
function footer(s, dark=false){
  pageNo++;
  s.addText("MASSOH", { x:0.55, y:7.04, w:2, h:0.3, fontSize:9, bold:true, charSpacing:3,
    color: dark?ICE:MUTED, fontFace:BODY, margin:0 });
  s.addText(String(pageNo).padStart(2,"0"), { x:W-1.1, y:7.04, w:0.55, h:0.3, fontSize:9,
    color: dark?ICE:MUTED, align:"right", fontFace:MONO, margin:0 });
}
function head(s, kicker, title, sub){
  s.addText(kicker.toUpperCase(), { x:0.6, y:0.42, w:12, h:0.3, fontSize:11, bold:true,
    charSpacing:3, color:ACCENT_D, fontFace:MONO, margin:0 });
  s.addText(title, { x:0.58, y:0.7, w:12.1, h:0.7, fontSize:29, bold:true, color:INK,
    fontFace:HEAD, margin:0 });
  if(sub) s.addText(sub, { x:0.6, y:1.42, w:12.1, h:0.4, fontSize:13.5, italic:true,
    color:MUTED, fontFace:BODY, margin:0 });
}
function chip(s, x, y, w, text, fill, txtColor="FFFFFF", fs=10){
  s.addShape(RR, { x, y, w, h:0.34, rectRadius:0.06, fill:{color:fill}, line:{type:"none"} });
  s.addText(text, { x, y, w, h:0.34, align:"center", valign:"middle", fontSize:fs,
    bold:true, color:txtColor, fontFace:BODY, margin:0 });
}

// ============ SEQUENCE DIAGRAM ENGINE ============
function drawSequence(s, cfg){
  const { x, y, w, actors, messages, boxH=0.5, gap=0.6, startPad=0.5 } = cfg;
  const n = actors.length;
  const laneW = w / n;
  const laneX = actors.map((_,i)=> x + laneW*i + laneW/2);
  const lifelineTop = y + boxH;
  const msgTop = lifelineTop + startPad;
  let yCursor = msgTop;
  // measure total height
  let total = msgTop;
  messages.forEach(m => total += (m.type==="note" ? gap*1.05 : gap));
  const lifelineBottom = total + 0.1;
  // actor header + lifelines
  actors.forEach((a,i)=>{
    const bx = laneX[i]-laneW*0.43, bw = laneW*0.86;
    s.addShape(RR, { x:bx, y, w:bw, h:boxH, rectRadius:0.05, fill:{color:a.color||PRIMARY}, line:{type:"none"}, shadow: sh() });
    s.addText(a.name, { x:bx-0.05, y, w:bw+0.1, h:boxH, align:"center", valign:"middle",
      fontSize:11, bold:true, color:"FFFFFF", fontFace:BODY, margin:0 });
    s.addShape(LINE, { x:laneX[i], y:lifelineTop, w:0, h:lifelineBottom-lifelineTop,
      line:{ color:"C4CCDA", width:1, dashType:"dash" } });
  });
  // messages
  messages.forEach(m=>{
    if(m.type==="note"){
      const a = laneX[m.from], b = laneX[m.to!=null?m.to:m.from];
      const left = Math.min(a,b)-0.15, right = Math.max(a,b)+0.15;
      const nw = Math.max(right-left, 2.4);
      const cx = (a+b)/2 - nw/2;
      const col = m.color||WARN;
      s.addShape(RR, { x:cx, y:yCursor-0.04, w:nw, h:0.46, rectRadius:0.05,
        fill:{color:col, transparency:8}, line:{color:col, width:1} });
      s.addText(m.label, { x:cx, y:yCursor-0.04, w:nw, h:0.46, align:"center", valign:"middle",
        fontSize:9.5, bold:true, color: m.txt|| "5A3A00", fontFace:BODY, margin:0 });
      yCursor += gap*1.05;
      return;
    }
    const xa = laneX[m.from], xb = laneX[m.to];
    const left = Math.min(xa,xb), wlen = Math.abs(xb-xa);
    const lo = { x:left, y:yCursor, w:wlen, h:0, line:{ color:m.color||INK2, width:1.75,
      dashType: m.dash?"dash":"solid" } };
    if(xb>=xa) lo.line.endArrowType="triangle"; else lo.line.beginArrowType="triangle";
    s.addShape(LINE, lo);
    s.addText(m.label, { x:left-0.1, y:yCursor-0.31, w:wlen+0.2, h:0.28, align:"center",
      fontSize:10, bold:!!m.bold, color:m.labelColor||INK, fontFace:BODY, margin:0 });
    if(m.artifact) s.addText(m.artifact, { x:left-0.1, y:yCursor+0.015, w:wlen+0.2, h:0.22,
      align:"center", fontSize:8.5, color:ACCENT_D, fontFace:MONO, margin:0 });
    yCursor += gap;
  });
  return lifelineBottom;
}

// box + arrow helpers for activity / component diagrams
function node(s, x, y, w, h, text, fill, txt="FFFFFF", fs=11.5, sub){
  s.addShape(RR, { x, y, w, h, rectRadius:0.08, fill:{color:fill}, line:{type:"none"}, shadow: sh() });
  if(sub){
    s.addText([{text:text, options:{bold:true, fontSize:fs, breakLine:true}},
               {text:sub, options:{fontSize:9, color: txt==="FFFFFF"?ICE:MUTED}}],
      { x, y, w, h, align:"center", valign:"middle", color:txt, fontFace:BODY, margin:2 });
  } else {
    s.addText(text, { x, y, w, h, align:"center", valign:"middle", fontSize:fs, bold:true,
      color:txt, fontFace:BODY, margin:2 });
  }
}
function arrow(s, x, y, w, h, color=PRIMARY, dash=false){
  s.addShape(LINE, { x, y, w, h, line:{ color, width:2, endArrowType:"triangle",
    dashType: dash?"dash":"solid" } });
}

// ===================================================================
// SLIDE 1 — TITLE (dark)
// ===================================================================
(function(){
  const s = newSlide(true);
  // motif: faint sequence lifelines + arrows top-right
  for(let i=0;i<5;i++){
    const lx = 8.6 + i*0.95;
    s.addShape(LINE, { x:lx, y:0.0, w:0, h:7.5, line:{color:"24345E", width:1, dashType:"dash"} });
  }
  [[8.6,1.5,0.95],[9.55,2.3,1.9],[11.45,3.1,-0.95],[8.6,3.9,2.85],[10.5,4.7,0.95]].forEach((m,i)=>{
    const lo={ x:Math.min(m[0],m[0]+m[2]), y:m[1], w:Math.abs(m[2]), h:0,
      line:{color: i%2? ACCENT : "4659C4", width:2 } };
    if(m[2]>=0) lo.line.endArrowType="triangle"; else lo.line.beginArrowType="triangle";
    s.addShape(LINE, lo);
  });
  s.addShape(RR, { x:0.85, y:1.05, w:2.55, h:0.5, rectRadius:0.25, fill:{color:"1E2A4A"},
    line:{color:ACCENT, width:1} });
  s.addText("AGENT OPERATING SYSTEM", { x:0.85, y:1.05, w:2.55, h:0.5, align:"center",
    valign:"middle", fontSize:9.5, bold:true, color:ACCENT, charSpacing:1, fontFace:MONO, margin:0 });

  s.addText("Massoh", { x:0.8, y:1.95, w:9, h:1.4, fontSize:74, bold:true, color:"FFFFFF",
    fontFace:HEAD, margin:0 });
  s.addText("A portable agent operating system for Claude Code.", { x:0.85, y:3.45, w:9.5, h:0.6,
    fontSize:23, color:ICE, fontFace:BODY, margin:0 });
  s.addText("A small, disciplined software team of AI agents — running any repo through a gated,\nauditable workflow with hard safety gates, self-measurement, and an optional autonomous mode.",
    { x:0.85, y:4.2, w:11, h:0.9, fontSize:13.5, color:"AEB9D6", fontFace:BODY, margin:0, lineSpacingMultiple:1.15 });

  s.addShape(LINE, { x:0.88, y:5.55, w:0, h:0.85, line:{color:ACCENT, width:3} });
  s.addText("“Agile’s discipline without agile’s meetings —\nenforced, auditable, for AI agents.”",
    { x:1.1, y:5.5, w:9, h:0.95, fontSize:15, italic:true, bold:true, color:"FFFFFF",
      fontFace:HEAD, margin:0, lineSpacingMultiple:1.1 });
  footer(s, true);
})();

// ===================================================================
// SLIDE 2 — THE PROBLEM
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "Why this exists", "AI agents are fast, cheap — and ungoverned",
    "The same speed that ships a feature in minutes ships an irreversible mistake in seconds.");
  const cards = [
    ["Scope creep","A one-line ask becomes a refactor of three modules. No one decided that.", DANGER],
    ["Lost context","Each session starts cold. Decisions, constraints, and history evaporate.", WARN],
    ["No paper trail","Why was this built? Who approved it? Where is the test? — nobody knows.", PRIMARY],
    ["Cheap blast radius","An agent can delete data, rewrite history, or deploy in one tool call.", DANGER],
  ];
  const cw=2.78, gap=0.27, x0=0.6, y0=2.05, ch=2.05;
  cards.forEach((c,i)=>{
    const x = x0 + i*(cw+gap);
    s.addShape(RR, { x, y:y0, w:cw, h:ch, rectRadius:0.1, fill:{color:CARD}, line:{color:BORDER,width:1}, shadow:sh() });
    s.addShape(RECT, { x, y:y0, w:cw, h:0.12, fill:{color:c[2]}, line:{type:"none"} });
    s.addText(c[0], { x:x+0.22, y:y0+0.32, w:cw-0.4, h:0.5, fontSize:16, bold:true, color:INK, fontFace:HEAD, margin:0 });
    s.addText(c[1], { x:x+0.22, y:y0+0.92, w:cw-0.42, h:1.0, fontSize:12, color:"45506B", fontFace:BODY, margin:0, lineSpacingMultiple:1.12 });
  });
  // bottom band
  s.addShape(RR, { x:0.6, y:4.5, w:12.13, h:1.95, rectRadius:0.1, fill:{color:INK}, line:{type:"none"}, shadow:sh() });
  s.addText("The gap nobody fills", { x:0.95, y:4.75, w:6, h:0.4, fontSize:13, bold:true, color:ACCENT, fontFace:MONO, margin:0, charSpacing:1 });
  s.addText([
    {text:"Raw agents", options:{bold:true, color:"FFFFFF", breakLine:true, fontSize:14}},
    {text:"all gas, no brakes — speed without process", options:{color:"AEB9D6", fontSize:11.5}},
  ], { x:0.95, y:5.2, w:3.6, h:1.0, fontFace:BODY, margin:0, valign:"top" });
  s.addText([
    {text:"Agile / Scrum", options:{bold:true, color:"FFFFFF", breakLine:true, fontSize:14}},
    {text:"all process, built for humans — sprints, standups, story points", options:{color:"AEB9D6", fontSize:11.5}},
  ], { x:5.0, y:5.2, w:3.7, h:1.0, fontFace:BODY, margin:0, valign:"top" });
  s.addText([
    {text:"Massoh", options:{bold:true, color:ACCENT, breakLine:true, fontSize:14}},
    {text:"agile’s empirical discipline, the meetings removed, hard gates added", options:{color:"E6ECFA", fontSize:11.5}},
  ], { x:9.1, y:5.2, w:3.4, h:1.0, fontFace:BODY, margin:0, valign:"top" });
  footer(s);
})();

// ===================================================================
// SLIDE 3 — THE CORE IDEA
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "The thesis", "Post-agile for agents", "Keep what works empirically. Drop the human coordination tax. Add the gates agile leaves implicit.");
  // three columns
  const cols = [
    ["KEEP", ACCENT_D, ["Iterate in small increments","Test against reality","Inspect & adapt from data"]],
    ["DROP", MUTED, ["Sprints & story points","Standups for humans","Hand-offs as meetings — agents sync through files, instantly"]],
    ["ADD", PRIMARY, ["No code without a license","Owner sign-off on safety-critical change","A real test, every time — a stub never counts"]],
  ];
  const cw=3.85, gap=0.28, x0=0.6, y0=2.1, ch=3.7;
  cols.forEach((c,i)=>{
    const x=x0+i*(cw+gap);
    s.addShape(RR, { x, y:y0, w:cw, h:ch, rectRadius:0.1, fill:{color:CARD}, line:{color:BORDER,width:1}, shadow:sh() });
    s.addShape(RR, { x:x+0.25, y:y0+0.28, w:1.5, h:0.5, rectRadius:0.25, fill:{color:c[1]}, line:{type:"none"} });
    s.addText(c[0], { x:x+0.25, y:y0+0.28, w:1.5, h:0.5, align:"center", valign:"middle", fontSize:14, bold:true, color:"FFFFFF", fontFace:BODY, margin:0, charSpacing:1 });
    s.addText(c[2].map((t,j)=>({text:t, options:{bullet:{indent:14}, breakLine:true, paraSpaceAfter:9, fontSize:12.5, color:"3A4straw"==="x"?INK:"33405C"}})),
      { x:x+0.28, y:y0+1.0, w:cw-0.5, h:ch-1.2, fontFace:BODY, margin:0, valign:"top", lineSpacingMultiple:1.05 });
  });
  footer(s);
})();

// ===================================================================
// SLIDE 4 — COMPONENT / DEPLOYMENT DIAGRAM (3 planes)
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "Architecture · UML component view", "Install once, globally. Opt in per repo.",
    "Pure-bash CLI + a machine-readable boundary (manifest.yml). No runtime service.");
  const y0=2.0, ch=4.3, cw=3.57, gap=0.70, x0=0.6;
  const planes = [
    ["«source»  This repo", PRIMARY_D, ["bin/massoh  ·  manifest.yml","claude/agents/  ·  skills/","agent-os/ engine  ·  templates/"]],
    ["«global»  ~/.claude", ACCENT_D, ["massoh-* agents (namespaced)","agent-os/ policies + skills","marker-gated CLAUDE.md block"]],
    ["«host»  your project repo", "5A4FB0", ["agent-project/  ·  AGENT_SYNC.md","AGENT_BACKLOG.md  ·  memory/",".massoh marker  ·  .agent_tasks/"]],
  ];
  planes.forEach((p,i)=>{
    const x=x0+i*(cw+gap);
    s.addShape(RR, { x, y:y0, w:cw, h:ch, rectRadius:0.08, fill:{color:CARD}, line:{color:p[1],width:1.5}, shadow:sh() });
    s.addShape(RECT, { x, y:y0, w:cw, h:0.62, fill:{color:p[1]}, line:{type:"none"} });
    s.addText(p[0], { x:x+0.2, y:y0, w:cw-0.4, h:0.62, valign:"middle", fontSize:13.5, bold:true, color:"FFFFFF", fontFace:BODY, margin:0 });
    p[2].forEach((t,j)=>{
      s.addShape(RR, { x:x+0.25, y:y0+0.92+j*1.05, w:cw-0.5, h:0.82, rectRadius:0.06, fill:{color:BG}, line:{color:BORDER,width:1} });
      s.addText(t, { x:x+0.4, y:y0+0.92+j*1.05, w:cw-0.75, h:0.82, valign:"middle", fontSize:10.5, color:INK, fontFace:MONO, margin:0 });
    });
  });
  // connectors with stereotype labels
  const midY = y0+ch/2;
  arrow(s, x0+cw+0.06, midY-0.15, gap-0.12, 0, ACCENT_D);
  s.addText("install", { x:x0+cw, y:midY-0.62, w:gap, h:0.3, align:"center", fontSize:10, bold:true, color:ACCENT_D, fontFace:MONO, margin:0 });
  s.addText("backup", { x:x0+cw, y:midY+0.05, w:gap, h:0.3, align:"center", fontSize:8.5, color:MUTED, fontFace:BODY, margin:0 });
  const x2 = x0+2*(cw+gap)-gap;
  arrow(s, x2+0.06, midY-0.15, gap-0.12, 0, "5A4FB0");
  s.addText("massoh on", { x:x2, y:midY-0.62, w:gap, h:0.3, align:"center", fontSize:10, bold:true, color:"5A4FB0", fontFace:MONO, margin:0 });
  s.addText("scaffold", { x:x2, y:midY+0.05, w:gap, h:0.3, align:"center", fontSize:8.5, color:MUTED, fontFace:BODY, margin:0 });
  s.addText("manifest.yml ⇄ bin/massoh is the contract seam — doctor checks the live install against it.",
    { x:0.6, y:6.45, w:12.1, h:0.3, fontSize:11, italic:true, color:MUTED, fontFace:BODY, margin:0 });
  footer(s);
})();

// ===================================================================
// SLIDE 5 — THE TEAM (7 roles)
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "The team · claude/agents/massoh-*", "Seven roles. One owner. Clear authority.",
    "Each role decides exactly one class of thing — and only the implementer touches code.");
  const roles = [
    ["product-scope","build / defer / kill · scope · metric","no", MUTED],
    ["architecture-safety","readiness-to-build · risk (a gate)","gate", DANGER],
    ["implementer","executes approved scope","yes", ACCENT_D],
    ["reviewer-qa","approve / changes / reject","no", MUTED],
    ["system-architect","unblock · sequence · arch calls","seams", WARN],
    ["history-maintainer","keep / merge / archive docs","no", MUTED],
    ["meta-engineer","bottlenecks · propose engine upgrades","propose", PRIMARY],
  ];
  const cw=2.94, chh=1.55, gx=0.18, gy=0.22, x0=0.6;
  function pill(label){ // edits-code badge
    if(label==="yes") return ["edits code","FFFFFF",ACCENT_D];
    if(label==="gate") return ["read-only · GATE","FFFFFF",DANGER];
    if(label==="seams") return ["small safe seams","5A3A00",WARN];
    if(label==="propose") return ["PROPOSE-ONLY","FFFFFF",PRIMARY];
    return ["no code","FFFFFF","8893A8"];
  }
  roles.forEach((r,i)=>{
    const col=i%4, row=Math.floor(i/4);
    const x=x0+col*(cw+gx), y=2.0+row*(chh+gy);
    s.addShape(RR, { x, y, w:cw, h:chh, rectRadius:0.09, fill:{color:CARD}, line:{color:BORDER,width:1}, shadow:sh() });
    s.addShape(RECT, { x, y, w:0.1, h:chh, fill:{color:r[3]}, line:{type:"none"} });
    s.addText("massoh-"+r[0], { x:x+0.25, y:y+0.18, w:cw-0.4, h:0.4, fontSize:13, bold:true, color:INK, fontFace:HEAD, margin:0 });
    s.addText(r[1], { x:x+0.25, y:y+0.62, w:cw-0.42, h:0.55, fontSize:10.5, color:"45506B", fontFace:BODY, margin:0, lineSpacingMultiple:1.05 });
    const p=pill(r[2]);
    chip(s, x+0.25, y+chh-0.42, 1.85, p[0], p[2], p[1], 9);
  });
  // 8th cell: owner
  const x=x0+3*(cw+gx), y=2.0+1*(chh+gy);
  s.addShape(RR, { x, y, w:cw, h:chh, rectRadius:0.09, fill:{color:INK}, line:{type:"none"}, shadow:sh() });
  s.addText("Owner (you)", { x:x+0.25, y:y+0.18, w:cw-0.4, h:0.4, fontSize:13, bold:true, color:"FFFFFF", fontFace:HEAD, margin:0 });
  s.addText("signs off · merges · sets the goal", { x:x+0.25, y:y+0.62, w:cw-0.42, h:0.55, fontSize:10.5, color:ICE, fontFace:BODY, margin:0 });
  chip(s, x+0.25, y+chh-0.42, 1.85, "the only human", "FFFFFF", ACCENT_D, 9);
  footer(s);
})();

// ===================================================================
// SLIDE 6 — THE GATED WORKFLOW (UML activity diagram)
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "UML activity view", "The gated workflow", "Every task crosses the same stages; each leaves a markdown artifact in .agent_tasks/TASK-*/");
  // start node
  const y=2.35, h=0.92;
  s.addShape(OVAL, { x:0.6, y:y+0.15, w:0.62, h:0.62, fill:{color:INK}, line:{type:"none"} });
  s.addText("idea", { x:0.5, y:y+0.15, w:0.82, h:0.62, align:"center", valign:"middle", fontSize:9, bold:true, color:"FFFFFF", fontFace:BODY, margin:0 });
  const stages = [
    ["Product\nScope","00·01", MUTED],
    ["Arch /\nSafety","03", DANGER],
    ["License\nto code","04", PRIMARY],
    ["Implementer","05", ACCENT_D],
    ["Reviewer\nQA","06", "5A4FB0"],
  ];
  let x=1.5; const wbox=1.95, gapx=0.42;
  stages.forEach((st,i)=>{
    node(s, x, y, wbox, h, st[0].replace("\n"," "), st[2], "FFFFFF", 12, "→ "+st[1]);
    if(i<stages.length-1) arrow(s, x+wbox+0.04, y+h/2, gapx-0.08, 0, INK2);
    x += wbox+gapx;
  });
  // end node
  arrow(s, x+0.0, y+h/2, 0.4, 0, INK2);
  s.addShape(OVAL, { x:x+0.45, y:y+0.15, w:0.62, h:0.62, fill:{color:ACCENT_D}, line:{color:INK,width:2} });
  s.addText("merge", { x:x+0.3, y:y+0.15, w:0.92, h:0.62, align:"center", valign:"middle", fontSize:8.5, bold:true, color:"FFFFFF", fontFace:BODY, margin:0 });

  // GATE decision diamond under Arch/Safety
  const dx=3.87+0.0; // approx under arch box
  // draw guard note for the hard gate
  s.addShape(RR, { x:3.45, y:3.9, w:2.4, h:0.95, rectRadius:0.08, fill:{color:DANGER}, line:{type:"none"}, shadow: sh() });
  s.addText([{text:"HARD GATE", options:{bold:true, fontSize:12.5, color:"FFFFFF", breakLine:true}},
             {text:"safety-critical change → owner sign-off", options:{fontSize:9.5, color:"FFE3E3"}}],
    { x:3.55, y:3.9, w:2.2, h:0.95, align:"center", valign:"middle", fontFace:BODY, margin:2, lineSpacingMultiple:1.05 });
  arrow(s, 4.65, 3.27, 0, 0.6, DANGER, true);

  // license note under license box
  s.addShape(RR, { x:6.1, y:3.9, w:2.3, h:0.95, rectRadius:0.08, fill:{color:PRIMARY}, line:{type:"none"}, shadow: sh() });
  s.addText([{text:"04 = the license", options:{bold:true, fontSize:12.5, color:"FFFFFF", breakLine:true}},
             {text:"no product code without it", options:{fontSize:9.5, color:"D9DEFF"}}],
    { x:6.2, y:3.9, w:2.1, h:0.95, align:"center", valign:"middle", fontFace:BODY, margin:2, lineSpacingMultiple:1.05 });
  arrow(s, 7.2, 3.27, 0, 0.6, PRIMARY, true);

  // shortcut note
  s.addShape(RR, { x:0.6, y:5.25, w:12.13, h:1.15, rectRadius:0.09, fill:{color:CARD}, line:{color:BORDER,width:1}, shadow:sh() });
  s.addText([
    {text:"Not every task runs every stage — ", options:{bold:true, color:INK, fontSize:12.5}},
    {text:"but every shortcut is explicit and recorded in 00_request.md.  ", options:{color:"45506B", fontSize:12.5, breakLine:true}},
    {text:"  bug fix → arch→impl→review    ·    copy → ux→impl→review    ·    strategy → product-scope only    ·    sync → dashboard only",
      options:{color:MUTED, fontSize:11, fontFace:MONO}},
  ], { x:0.95, y:5.45, w:11.5, h:0.8, fontFace:BODY, margin:0, valign:"middle", lineSpacingMultiple:1.2 });
  footer(s);
})();

// ===================================================================
// SLIDE 7 — SEQUENCE #1: a feature through the gate (real)
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "UML sequence · case study", "A feature, gate to merge",
    "Real run: TASK-2026-06-19-license-gate — making the “no code without a license” rule mechanical.");
  drawSequence(s, {
    x:0.7, y:1.95, w:11.9,
    actors:[
      {name:"Owner", color:INK},
      {name:"Product-Scope", color:MUTED},
      {name:"Arch / Safety", color:DANGER},
      {name:"Implementer", color:ACCENT_D},
      {name:"Reviewer-QA", color:"5A4FB0"},
    ],
    gap:0.5, startPad:0.42,
    messages:[
      {from:0,to:1,label:"idea: enforce the license gate", artifact:"00_request.md"},
      {from:1,to:0,label:"BUILD · minimal scope + acceptance criteria", dash:true, artifact:"01_product_scope.md"},
      {from:0,to:2,label:"assess impact & risk"},
      {from:2,to:0,label:"CONDITIONAL YES · 14 conditions · 18 tests", dash:true, artifact:"03_architecture_safety.md", color:DANGER, labelColor:DANGER},
      {from:0,to:3,label:"license to code — owner signed off (safety-critical)", bold:true, artifact:"04_implementation_packet.md", color:PRIMARY, labelColor:PRIMARY},
      {from:3,to:4,label:"code + 18 tests on feat/ branch", artifact:"05_implementation_handoff.md"},
      {from:4,to:0,label:"APPROVE / request-changes / reject", dash:true, artifact:"06_review_result.md"},
    ],
  });
  footer(s);
})();

// ===================================================================
// SLIDE 8 — SEQUENCE #2: the hard gate (owner-gated stop)
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "UML sequence · the one hard gate", "When an agent must stop and ask",
    "Guardrails force a halt for safety-critical files, irreversible ops, deploys, and real cost.");
  drawSequence(s, {
    x:1.6, y:2.1, w:9.9,
    actors:[ {name:"Agent", color:ACCENT_D}, {name:"Guardrails", color:DANGER}, {name:"Owner", color:INK} ],
    gap:0.66,
    messages:[
      {from:0,to:1,label:"intends to edit bin/massoh"},
      {from:1,to:0,label:"STOP — designated safety-critical (NON_NEGOTIABLES)", dash:true, color:DANGER, labelColor:DANGER, bold:true},
      {from:0,to:2,label:"request sign-off: risks, 14 conditions, rollback"},
      {type:"note", from:0, to:2, label:"Owner reviews · decision recorded in AGENT_SYNC.md decision log"},
      {from:2,to:0,label:"SIGNED OFF", dash:true, color:ACCENT_D, labelColor:ACCENT_D, bold:true},
      {from:0,to:1,label:"proceed — now licensed"},
    ],
  });
  // side rule
  s.addShape(RR, { x:11.0, y:2.5, w:1.9, h:3.3, rectRadius:0.1, fill:{color:INK}, line:{type:"none"}, shadow:sh() });
  s.addText([
    {text:"Default", options:{bold:true, color:ACCENT, fontSize:12, breakLine:true}},
    {text:"if it’s reversible / flag-dark — take the safe option and proceed.", options:{color:ICE, fontSize:10.5, breakLine:true, paraSpaceAfter:10}},
    {text:"Stop only for", options:{bold:true, color:WARN, fontSize:12, breakLine:true}},
    {text:"safety-critical · irreversible · deploy · paid spend", options:{color:ICE, fontSize:10.5}},
  ], { x:11.2, y:2.7, w:1.55, h:3.0, fontFace:BODY, margin:0, valign:"top", lineSpacingMultiple:1.05 });
  footer(s);
})();

// ===================================================================
// SLIDE 9 — SEQUENCE #3: autonomous cron tick
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "UML sequence · optional autonomy", "Let it work while you’re away",
    "massoh cron once — idleness-gated, isolated worktrees, safe by default.");
  drawSequence(s, {
    x:0.7, y:2.1, w:11.9,
    actors:[
      {name:"Cron tick", color:INK},
      {name:"Backlog", color:MUTED},
      {name:"Git worktree", color:ACCENT_D},
      {name:"Cadence", color:"5A4FB0"},
      {name:"Owner", color:PRIMARY_D},
    ],
    gap:0.62,
    messages:[
      {from:0,to:1,label:"idle? pull top TODO(s)"},
      {from:1,to:0,label:"TASK-… (acceptance criteria)", dash:true},
      {from:0,to:2,label:"run task in an isolated worktree (--parallel N)"},
      {from:2,to:0,label:"branch + PR  ·  dry-run unless --run", dash:true, color:ACCENT_D, labelColor:ACCENT_D},
      {from:0,to:3,label:"run ceremonies: standup · review · plan"},
      {from:3,to:4,label:"KPIs + surfaced decisions", dash:true, artifact:"METRICS.md"},
      {type:"note", from:0, to:4, label:"Safe by default: dry-run · auto-merge OFF · paid spend = explicit owner opt-in"},
    ],
  });
  footer(s);
})();

// ===================================================================
// SLIDE 10 — GUARDRAILS
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "policies/09_GUARDRAILS.md", "The rules every agent enforces",
    "Not suggestions — the agents refuse to cross these.");
  const items = [
    ["No code without a license","an approved 04 packet, or an issue with acceptance criteria"],
    ["Branch + PR per feature","never commit a feature straight to main"],
    ["Keep older data","append-only / soft-delete — never hard-delete or overwrite history"],
    ["A real test, every time","a stub does not count; the suite must be green before review"],
    ["No broad refactors","unless explicitly requested and scoped"],
    ["No secrets in git","and honest reporting — failures reported as failures"],
  ];
  const cw=5.95, chh=0.92, gx=0.23, gy=0.22, x0=0.6, y0=2.0;
  items.forEach((it,i)=>{
    const col=i%2, row=Math.floor(i/2);
    const x=x0+col*(cw+gx), y=y0+row*(chh+gy);
    s.addShape(RR, { x, y, w:cw, h:chh, rectRadius:0.08, fill:{color:CARD}, line:{color:BORDER,width:1}, shadow:sh() });
    s.addShape(OVAL, { x:x+0.22, y:y+0.27, w:0.4, h:0.4, fill:{color:ACCENT_D}, line:{type:"none"} });
    s.addText("✓", { x:x+0.22, y:y+0.27, w:0.4, h:0.4, align:"center", valign:"middle", fontSize:13, bold:true, color:"FFFFFF", fontFace:BODY, margin:0 });
    s.addText([{text:it[0], options:{bold:true, color:INK, fontSize:13, breakLine:true}},
               {text:it[1], options:{color:MUTED, fontSize:10.5}}],
      { x:x+0.8, y:y+0.12, w:cw-1.0, h:chh-0.2, valign:"middle", fontFace:BODY, margin:0, lineSpacingMultiple:1.0 });
  });
  s.addShape(RR, { x:0.6, y:5.65, w:12.13, h:0.85, rectRadius:0.08, fill:{color:WARN, transparency:12}, line:{color:WARN,width:1.5} });
  s.addText([{text:"Owner-gated stops  ", options:{bold:true, color:"7A5200", fontSize:13}},
    {text:"an autonomous agent halts for: a safety-critical change · an irreversible op · a production deploy · real API spend.",
      options:{color:"6B4E10", fontSize:12}}],
    { x:0.95, y:5.65, w:11.4, h:0.85, valign:"middle", fontFace:BODY, margin:0 });
  footer(s);
})();

// ===================================================================
// SLIDE 11 — UML CLASS DIAGRAM: the task packet
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "UML class view", "The artifact of record: a task packet",
    "Every meaningful task is one folder. The packet is the detailed history; AGENT_SYNC.md is just the dashboard.");
  // class box
  const x=0.9, y=2.0, w=5.4;
  s.addShape(RECT, { x, y, w, h:0.55, fill:{color:INK}, line:{color:INK,width:1} });
  s.addText("«artifact»  TASK-YYYY-MM-DD-slug /", { x:x+0.2, y, w:w-0.3, h:0.55, valign:"middle", fontSize:13, bold:true, color:"FFFFFF", fontFace:MONO, margin:0 });
  const rows = [
    ["00_request.md","/start-task","verbatim ask · classification"],
    ["01_product_scope.md","product-scope","build/defer/kill · metric · criteria"],
    ["02_ux_review.md","ux (if needed)","flow · copy · invariants"],
    ["03_architecture_safety.md","arch-safety","impact · risk · approved?"],
    ["04_implementation_packet.md","after approvals","THE LICENSE — scope · tests · rollback"],
    ["05_implementation_handoff.md","implementer","files · tests run · risks"],
    ["06_review_result.md","reviewer","approve / changes / reject"],
  ];
  const rh=0.52;
  rows.forEach((r,i)=>{
    const ry=y+0.55+i*rh;
    const lic = r[0].startsWith("04");
    s.addShape(RECT, { x, y:ry, w, h:rh, fill:{color: lic?"EEF0FF":CARD}, line:{color:BORDER,width:1} });
    s.addText("+ "+r[0], { x:x+0.2, y:ry, w:3.05, h:rh, valign:"middle", fontSize:10.5, bold:lic, color: lic?PRIMARY:INK, fontFace:MONO, margin:0 });
    s.addText(r[1], { x:x+3.25, y:ry, w:2.0, h:rh, valign:"middle", fontSize:9.5, italic:true, color: lic?PRIMARY:MUTED, fontFace:BODY, margin:0 });
  });
  // right: stereotype notes
  const nx=6.7;
  [["00→06 is the spine","every standard build follows it in order", PRIMARY],
   ["append-only","a packet is never deleted — noisy ones move to .agent_tasks/archive/", ACCENT_D],
   ["not closable without 06","a code task can’t close until the reviewer has written a verdict", DANGER]
  ].forEach((nrow,i)=>{
    const ny=2.05+i*1.35;
    s.addShape(RR, { x:nx, y:ny, w:5.95, h:1.18, rectRadius:0.09, fill:{color:CARD}, line:{color:nrow[2],width:1.5}, shadow:sh() });
    s.addShape(RECT, { x:nx, y:ny, w:0.1, h:1.18, fill:{color:nrow[2]}, line:{type:"none"} });
    s.addText(nrow[0], { x:nx+0.3, y:ny+0.16, w:5.5, h:0.4, fontSize:13.5, bold:true, color:INK, fontFace:HEAD, margin:0 });
    s.addText(nrow[1], { x:nx+0.3, y:ny+0.58, w:5.5, h:0.5, fontSize:11.5, color:"45506B", fontFace:BODY, margin:0, lineSpacingMultiple:1.05 });
  });
  footer(s);
})();

// ===================================================================
// SLIDE 12 — SELF-MEASUREMENT (ledger + meta) with chart
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "Reuse the harness · don’t re-measure", "It watches its own work",
    "Massoh records what each stage costs, then mines that record for bottlenecks — zero extra LLM spend.");
  // left: ledger chart (token cost by stage, from the real ledger.tsv)
  s.addText("massoh ledger — tokens per stage (TASK-massoh-ledger)", { x:0.7, y:1.95, w:6, h:0.35, fontSize:12, bold:true, color:INK, fontFace:BODY, margin:0 });
  s.addChart(pres.charts.BAR, [{
    name:"tokens", labels:["product-scope","arch-safety","implementer","reviewer-qa"],
    values:[52922, 56234, 85819, 89670]
  }], {
    x:0.6, y:2.4, w:6.3, h:4.0, barDir:"bar",
    chartColors:[PRIMARY], chartColorsOpacity:[90],
    chartArea:{ fill:{color:"FFFFFF"} },
    catAxisLabelColor:MUTED, valAxisLabelColor:MUTED, catAxisLabelFontSize:10, valAxisLabelFontSize:9,
    valGridLine:{ color:BORDER, size:0.5 }, catGridLine:{ style:"none" },
    showValue:true, dataLabelPosition:"outEnd", dataLabelColor:INK, dataLabelFontSize:9,
    showLegend:false, showTitle:false, valAxisHidden:false,
  });
  // right: what meta surfaces
  const nx=7.4;
  s.addText("massoh meta — ranked bottleneck report", { x:nx, y:1.95, w:5.4, h:0.35, fontSize:12, bold:true, color:INK, fontFace:BODY, margin:0 });
  const metas = [
    ["Cost outliers","stages burning > 2× the median token spend", PRIMARY],
    ["Rework rate","how often review sends a task back before approve", DANGER],
    ["Backlog drift","items aging in NEXT without movement", WARN],
    ["Repeated findings","the same review note ≥ 3 times → a standards gap", ACCENT_D],
  ];
  metas.forEach((m,i)=>{
    const y=2.45+i*1.0;
    s.addShape(RR, { x:nx, y, w:5.35, h:0.85, rectRadius:0.08, fill:{color:CARD}, line:{color:BORDER,width:1}, shadow:sh() });
    s.addShape(OVAL, { x:nx+0.2, y:y+0.22, w:0.42, h:0.42, fill:{color:m[2]}, line:{type:"none"} });
    s.addText(String(i+1), { x:nx+0.2, y:y+0.22, w:0.42, h:0.42, align:"center", valign:"middle", fontSize:12, bold:true, color:"FFFFFF", fontFace:BODY, margin:0 });
    s.addText([{text:m[0]+"  ", options:{bold:true, color:INK, fontSize:12.5}},
      {text:m[1], options:{color:MUTED, fontSize:10.5}}],
      { x:nx+0.8, y:y, w:4.4, h:0.85, valign:"middle", fontFace:BODY, margin:0, lineSpacingMultiple:1.0 });
  });
  s.addText("Output → META.proposed.md (labeled [meta]); the meta-engineer proposes engine upgrades — it never auto-merges them.",
    { x:0.6, y:6.6, w:12.1, h:0.3, fontSize:10.5, italic:true, color:MUTED, fontFace:BODY, margin:0 });
  footer(s);
})();

// ===================================================================
// SLIDE 13 — THE LEARNING LOOP (sequence-ish flow)
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "massoh learn · the learning loop", "It gets better from its own history",
    "Mine finished packets, the decision log, and git reverts/fixups → lessons → promotable proposals.");
  const steps = [
    ["Sources","completed packets · review findings · decision log · git reverts & fixups", MUTED],
    ["Mine (read-only)","heuristics — zero LLM spend, no network", PRIMARY],
    ["Lessons report","recurring risks, defects, and standards gaps, ranked", ACCENT_D],
    ["Proposals","drafts into LEARNINGS.proposed.md — STANDARDS / memory / ADR", WARN],
    ["You promote","through the gate — nothing self-applies", INK],
  ];
  const wbox=2.18, gapx=0.42, y=2.6, h=1.7, x0=0.6;
  steps.forEach((st,i)=>{
    const x=x0+i*(wbox+gapx);
    s.addShape(RR, { x, y, w:wbox, h, rectRadius:0.1, fill:{color:CARD}, line:{color:st[2],width:1.5}, shadow:sh() });
    s.addShape(RECT, { x, y, w:wbox, h:0.5, fill:{color:st[2]}, line:{type:"none"} });
    s.addText(st[0], { x, y, w:wbox, h:0.5, align:"center", valign:"middle", fontSize:12.5, bold:true, color:"FFFFFF", fontFace:BODY, margin:0 });
    s.addText(st[1], { x:x+0.2, y:y+0.62, w:wbox-0.4, h:h-0.75, fontSize:10.5, color:"3A4straw"==="z"?INK:"40496B", fontFace:BODY, margin:0, valign:"top", lineSpacingMultiple:1.08 });
    if(i<steps.length-1) arrow(s, x+wbox+0.04, y+h/2, gapx-0.08, 0, INK2);
  });
  s.addShape(RR, { x:0.6, y:4.95, w:12.13, h:1.45, rectRadius:0.1, fill:{color:INK}, line:{type:"none"}, shadow:sh() });
  s.addText("Proven on day one", { x:0.95, y:5.12, w:6, h:0.4, fontSize:13, bold:true, color:ACCENT, fontFace:MONO, charSpacing:1, margin:0 });
  s.addText("The first real massoh learn run surfaced two of Massoh’s own defects — before a human noticed them.\nThe reviewer role has already caught a real bug and sent a task back before merge. The loop is not theoretical.",
    { x:0.95, y:5.55, w:11.4, h:0.8, fontSize:13, color:"E6ECFA", fontFace:BODY, margin:0, lineSpacingMultiple:1.15 });
  footer(s);
})();

// ===================================================================
// SLIDE 14 — CADENCE CEREMONIES
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "Agent-native ceremonies · no humans, no spend", "A sense of time, without the meetings",
    "cron does the work; cadence reviews and decides. Read-only, deterministic.");
  const cer = [
    ["massoh standup","progress delta","commits since last · DOING + BLOCKED · in-flight packets", ACCENT_D],
    ["massoh review","KPI snapshot","packets open/reviewed · backlog counts · PRs · reverts → METRICS.md", PRIMARY],
    ["massoh plan","prioritize & surface","the ranked queue · open owner decisions · what’s BLOCKED", "5A4FB0"],
  ];
  const cw=3.95, gx=0.24, x0=0.6, y0=2.15, ch=3.6;
  cer.forEach((c,i)=>{
    const x=x0+i*(cw+gx);
    s.addShape(RR, { x, y:y0, w:cw, h:ch, rectRadius:0.1, fill:{color:CARD}, line:{color:BORDER,width:1}, shadow:sh() });
    s.addShape(RECT, { x, y:y0, w:cw, h:0.7, fill:{color:c[3]}, line:{type:"none"} });
    s.addText(c[0], { x:x+0.25, y:y0, w:cw-0.4, h:0.7, valign:"middle", fontSize:15, bold:true, color:"FFFFFF", fontFace:MONO, margin:0 });
    s.addText(c[1].toUpperCase(), { x:x+0.25, y:y0+0.9, w:cw-0.5, h:0.3, fontSize:11, bold:true, color:c[3], charSpacing:1, fontFace:BODY, margin:0 });
    s.addText(c[2], { x:x+0.25, y:y0+1.35, w:cw-0.5, h:1.8, fontSize:13, color:"3A4466", fontFace:BODY, margin:0, valign:"top", lineSpacingMultiple:1.2 });
  });
  s.addText("Driven by the cron cadence — period boundaries trigger them automatically. No story points. No retro that nobody reads.",
    { x:0.6, y:6.05, w:12.1, h:0.4, fontSize:11.5, italic:true, color:MUTED, fontFace:BODY, margin:0 });
  footer(s);
})();

// ===================================================================
// SLIDE 15 — THE CLI SURFACE
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "One binary · pure bash · idempotent", "The massoh CLI",
    "No service to run. No daemon. Verbs you can read end-to-end.");
  const groups = [
    ["LIFECYCLE", PRIMARY, ["install · update","on · off","enable · disable","status · doctor · version","work · uninstall"]],
    ["KNOWLEDGE", ACCENT_D, ["discover","learn","meta"]],
    ["CADENCE", "5A4FB0", ["standup","review","plan"]],
    ["AUTONOMY", WARN, ["cron once","cron install","--run · --parallel N","--auto-merge (opt-in)"]],
  ];
  const cw=2.95, gx=0.18, x0=0.6, y0=2.05, ch=4.0;
  groups.forEach((g,i)=>{
    const x=x0+i*(cw+gx);
    s.addShape(RR, { x, y:y0, w:cw, h:ch, rectRadius:0.1, fill:{color:CARD}, line:{color:BORDER,width:1}, shadow:sh() });
    s.addShape(RR, { x:x+0.25, y:y0+0.25, w:cw-0.5, h:0.5, rectRadius:0.06, fill:{color:g[1]}, line:{type:"none"} });
    s.addText(g[0], { x:x+0.25, y:y0+0.25, w:cw-0.5, h:0.5, align:"center", valign:"middle", fontSize:12.5, bold:true, color:"FFFFFF", charSpacing:1, fontFace:BODY, margin:0 });
    g[2].forEach((v,j)=>{
      s.addText("massoh "+v, { x:x+0.3, y:y0+0.95+j*0.58, w:cw-0.55, h:0.5, valign:"middle", fontSize:11, color:INK, fontFace:MONO, margin:0 });
      if(j<g[2].length-1) s.addShape(LINE, { x:x+0.3, y:y0+0.95+(j+1)*0.58-0.04, w:cw-0.6, h:0, line:{color:"EEF0F5", width:0.75} });
    });
  });
  s.addText("Knowledge + cadence verbs are read-only and spend nothing. Autonomy is dry-run unless you opt in. install backs up first.",
    { x:0.6, y:6.25, w:12.1, h:0.4, fontSize:11, italic:true, color:MUTED, fontFace:BODY, margin:0 });
  footer(s);
})();

// ===================================================================
// SLIDE 16 — PROVEN ON ITSELF (metrics)
// ===================================================================
(function(){
  const s = newSlide(true);
  s.addText("PROOF · DOGFOODED", { x:0.6, y:0.5, w:8, h:0.3, fontSize:11, bold:true, charSpacing:3, color:ACCENT, fontFace:MONO, margin:0 });
  s.addText("Massoh is its own first project", { x:0.58, y:0.82, w:12, h:0.7, fontSize:29, bold:true, color:"FFFFFF", fontFace:HEAD, margin:0 });
  s.addText("Every version below was built by the massoh-* team, on Massoh, through Massoh’s own gate.",
    { x:0.6, y:1.55, w:12, h:0.4, fontSize:13.5, italic:true, color:ICE, fontFace:BODY, margin:0 });
  const stats = [
    ["0.1 → 0.9","versions shipped through the gate", ACCENT],
    ["7","specialised roles, one owner", ICE],
    ["204 → 222","tests — green before every merge", ACCENT],
    ["100%","of changes carry a packet trail", ICE],
  ];
  const cw=2.94, gx=0.18, x0=0.6, y0=2.25, ch=1.7;
  stats.forEach((st,i)=>{
    const x=x0+i*(cw+gx);
    s.addShape(RR, { x, y:y0, w:cw, h:ch, rectRadius:0.1, fill:{color:INK2}, line:{color:"2C3A60",width:1} });
    s.addText(st[0], { x, y:y0+0.22, w:cw, h:0.8, align:"center", fontSize:33, bold:true, color:st[2], fontFace:HEAD, margin:0 });
    s.addText(st[1], { x:x+0.2, y:y0+1.05, w:cw-0.4, h:0.55, align:"center", fontSize:10.5, color:"AEB9D6", fontFace:BODY, margin:0, lineSpacingMultiple:1.0 });
  });
  // timeline of real PRs
  s.addText("The trail (real merges)", { x:0.6, y:4.25, w:8, h:0.35, fontSize:13, bold:true, color:ACCENT, fontFace:MONO, charSpacing:1, margin:0 });
  const prs = ["#8 cadence","#9 learn","#12 efficiency-v2","#14 ledger","#15 meta","→ license-gate"];
  const tw=(12.13-0.0)/prs.length, ty=4.95;
  s.addShape(LINE, { x:0.85, y:ty+0.25, w:11.6, h:0, line:{color:"3A4straw"==="q"?ACCENT:"34406A", width:2} });
  prs.forEach((p,i)=>{
    const cx=0.85+i*(11.6/(prs.length-1));
    const live = p.startsWith("→");
    s.addShape(OVAL, { x:cx-0.1, y:ty+0.15, w:0.2, h:0.2, fill:{color: live?WARN:ACCENT}, line:{type:"none"} });
    s.addText(p, { x:cx-1.0, y: i%2? ty+0.45 : ty-0.45, w:2.0, h:0.35, align:"center", fontSize:10, bold:live, color: live?WARN:"E6ECFA", fontFace:i%2?BODY:BODY, margin:0 });
  });
  s.addText("Including a feature where the reviewer caught a real bug and sent it back before merge — and a massoh learn run that found two defects on day one.",
    { x:0.6, y:6.35, w:12.1, h:0.5, fontSize:11.5, italic:true, color:"AEB9D6", fontFace:BODY, margin:0, lineSpacingMultiple:1.1 });
  footer(s, true);
})();

// ===================================================================
// SLIDE 17 — OBJECTIONS / WHY DIFFERENT
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "The honest comparison", "“Why not just…?”",
    "The objections an engineer actually raises.");
  const rows = [
    ["“…just prompt Claude Code better?”","Prompts are per-session and unenforced. Massoh makes the rule structural — the gate exists whether or not you remember to ask for it."],
    ["“…just use Scrum / Jira?”","Those coordinate humans across days. Agents sync through files in milliseconds. You want the discipline, not the calendar."],
    ["“…trust the model to be careful?”","Careful-on-average still deletes prod once. Guardrails make the dangerous classes of action require a human, every time."],
    ["“…it’ll slow me down.”","Read-only stages cost nothing and run in parallel. The only deliberate friction is one sign-off on safety-critical change."],
  ];
  const y0=2.05, rh=1.06, gy=0.16, x0=0.6;
  rows.forEach((r,i)=>{
    const y=y0+i*(rh+gy);
    s.addShape(RR, { x:x0, y, w:12.13, h:rh, rectRadius:0.08, fill:{color:CARD}, line:{color:BORDER,width:1}, shadow:sh() });
    s.addShape(RECT, { x:x0, y, w:4.5, h:rh, fill:{color:INK}, line:{type:"none"} });
    s.addText(r[0], { x:x0+0.28, y, w:4.0, h:rh, valign:"middle", fontSize:13.5, bold:true, italic:true, color:"FFFFFF", fontFace:HEAD, margin:0, lineSpacingMultiple:1.0 });
    s.addShape(OVAL, { x:x0+4.75, y:y+rh/2-0.16, w:0.32, h:0.32, fill:{color:ACCENT_D}, line:{type:"none"} });
    s.addText("→", { x:x0+4.75, y:y+rh/2-0.16, w:0.32, h:0.32, align:"center", valign:"middle", fontSize:12, bold:true, color:"FFFFFF", fontFace:BODY, margin:0 });
    s.addText(r[1], { x:x0+5.25, y, w:6.7, h:rh, valign:"middle", fontSize:11.5, color:"3A4466", fontFace:BODY, margin:0, lineSpacingMultiple:1.08 });
  });
  footer(s);
})();

// ===================================================================
// SLIDE 18 — THE BOUNDARY / ZERO FOOTPRINT
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "Out of the way until you opt in", "Zero footprint by design",
    "Install globally once; every other repo behaves like normal Claude Code.");
  const cols = [
    ["PORTABLE","the engine — roles, skills, workflow, policies, templates","~/.claude/ (installed once)", PRIMARY],
    ["PROJECT","charter, non-negotiables, strategy, standards, ADRs","the host repo (agent-project/, root)", ACCENT_D],
    ["MEMORY","accreted, project-specific learnings","the host repo only — Massoh ships only the schema", "5A4FB0"],
  ];
  const cw=3.95, gx=0.24, x0=0.6, y0=2.1, ch=2.6;
  cols.forEach((c,i)=>{
    const x=x0+i*(cw+gx);
    s.addShape(RR, { x, y:y0, w:cw, h:ch, rectRadius:0.1, fill:{color:CARD}, line:{color:c[3],width:1.5}, shadow:sh() });
    s.addText(c[0], { x:x+0.25, y:y0+0.25, w:cw-0.5, h:0.45, fontSize:15, bold:true, color:c[3], fontFace:HEAD, margin:0 });
    s.addText(c[1], { x:x+0.25, y:y0+0.85, w:cw-0.5, h:1.0, fontSize:12.5, color:"33405C", fontFace:BODY, margin:0, valign:"top", lineSpacingMultiple:1.12 });
    s.addText(c[2], { x:x+0.25, y:y0+ch-0.75, w:cw-0.5, h:0.6, fontSize:10, color:MUTED, fontFace:MONO, margin:0, valign:"top", lineSpacingMultiple:1.05 });
  });
  s.addShape(RR, { x:0.6, y:5.05, w:12.13, h:1.35, rectRadius:0.1, fill:{color:INK}, line:{type:"none"}, shadow:sh() });
  s.addText("The only always-on surface", { x:0.95, y:5.2, w:6, h:0.35, fontSize:12.5, bold:true, color:ACCENT, fontFace:MONO, charSpacing:1, margin:0 });
  s.addText("…is a small, marker-gated block in ~/.claude/CLAUDE.md: engage the workflow only in an opted-in repo (agent-project/ or a .massoh marker); otherwise behave as normal Claude Code. Agents and skills are inert until invoked — zero cost when unused, clean uninstall after a backup.",
    { x:0.95, y:5.6, w:11.4, h:0.75, fontSize:12.5, color:"E6ECFA", fontFace:BODY, margin:0, lineSpacingMultiple:1.12 });
  footer(s);
})();

// ===================================================================
// SLIDE 19 — HOW TO ADOPT (quickstart)
// ===================================================================
(function(){
  const s = newSlide();
  head(s, "Five minutes to live", "Try it on one repo",
    "Reversible at every step. Back up, opt in, mine conventions, go.");
  const steps = [
    ["1","Install the team once","bin/massoh install   # backs up ~/.claude first, idempotent", PRIMARY],
    ["2","Opt a repo in","cd my-project && massoh on   # scaffolds, never overwrites", ACCENT_D],
    ["3","Mine its conventions","massoh discover   # → agent-project/STANDARDS.md", "5A4FB0"],
    ["4","Run a task through the gate","claude  →  /start-task \"add X\"   # product-scope decides first", WARN],
    ["5","Back out anytime","massoh off  ·  massoh uninstall   # files preserved", MUTED],
  ];
  const y0=2.05, rh=0.84, gy=0.16, x0=0.6;
  steps.forEach((st,i)=>{
    const y=y0+i*(rh+gy);
    s.addShape(RR, { x:x0, y, w:12.13, h:rh, rectRadius:0.08, fill:{color:CARD}, line:{color:BORDER,width:1}, shadow:sh() });
    s.addShape(OVAL, { x:x0+0.22, y:y+rh/2-0.3, w:0.6, h:0.6, fill:{color:st[3]}, line:{type:"none"} });
    s.addText(st[0], { x:x0+0.22, y:y+rh/2-0.3, w:0.6, h:0.6, align:"center", valign:"middle", fontSize:18, bold:true, color:"FFFFFF", fontFace:HEAD, margin:0 });
    s.addText(st[1], { x:x0+1.05, y, w:3.9, h:rh, valign:"middle", fontSize:14, bold:true, color:INK, fontFace:BODY, margin:0 });
    s.addShape(RR, { x:x0+5.0, y:y+0.17, w:6.9, h:rh-0.34, rectRadius:0.06, fill:{color:"0E1630"}, line:{type:"none"} });
    s.addText(st[2], { x:x0+5.25, y:y+0.17, w:6.5, h:rh-0.34, valign:"middle", fontSize:10.5, color:"9FE9DC", fontFace:MONO, margin:0 });
  });
  footer(s);
})();

// ===================================================================
// SLIDE 20 — CLOSE (dark)
// ===================================================================
(function(){
  const s = newSlide(true);
  for(let i=0;i<5;i++){
    const lx = 0.9 + i*0.8;
    s.addShape(LINE, { x:lx, y:0, w:0, h:7.5, line:{color:"1C2A4C", width:1, dashType:"dash"} });
  }
  s.addText("Massoh", { x:0.85, y:1.4, w:11, h:1.2, fontSize:60, bold:true, color:"FFFFFF", fontFace:HEAD, margin:0 });
  s.addShape(LINE, { x:0.92, y:2.85, w:0, h:1.0, line:{color:ACCENT, width:3} });
  s.addText("Governance, self-measurement, and autonomy — coupled.\nThat coupling is the moat.",
    { x:1.15, y:2.8, w:11, h:1.1, fontSize:22, bold:true, color:"FFFFFF", fontFace:HEAD, margin:0, lineSpacingMultiple:1.1 });
  s.addText("Point it at a product goal → a disciplined team of agents ships it autonomously,\ntime/token/cost-aware, learning from its own history, reusing the harness it already runs on.",
    { x:1.15, y:4.15, w:11, h:0.9, fontSize:14, color:"AEB9D6", fontFace:BODY, margin:0, lineSpacingMultiple:1.2 });
  // CTA row
  chip(s, 1.15, 5.35, 3.3, "github.com/hsoffar/Massoh", INK2, ICE, 12);
  chip(s, 4.65, 5.35, 2.4, "install · opt in · go", ACCENT_D, "FFFFFF", 12);
  s.addText("“Agile’s discipline without agile’s meetings — enforced, auditable, for AI agents.”",
    { x:1.15, y:6.35, w:11, h:0.5, fontSize:14, italic:true, color:ICE, fontFace:HEAD, margin:0 });
  footer(s, true);
})();

pres.writeFile({ fileName: "/home/hossam/dev/Massoh/deck/Massoh-pitch.pptx" })
  .then(f => console.log("WROTE", f))
  .catch(e => { console.error("ERR", e); process.exit(1); });
