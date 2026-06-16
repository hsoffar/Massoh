# 12 — Expansion-ready architecture (portable principle)

**Today's wedge is a focus, not a permanent constraint.** Whatever narrow choice makes the MVP
sharp — a single region, language, locale, segment, platform, or domain — should be a *parameter*,
not a hard-coded assumption baked through the code.

## The rule
- Pick a wedge to ship fast. **Name it** in `agent-project/CHARTER.md` as the current focus.
- Architect data, prompts, config, and copy so the wedge is selectable
  (`region` / `locale` / `segment` / `profile`-style concepts), **without building the general
  platform now**.
- Agents **flag** any change that hard-codes the wedge where a parameter would do — but do **not**
  over-engineer a multi-everything platform before there's a second case. (YAGNI both ways: don't
  hard-code it, don't gold-plate it.)

## Examples of "parameter, not assumption"
- copy/strings → a localization layer keyed by locale, even if only one locale exists today;
- domain rules → a profile/config the wedge selects, not `if country == X` sprinkled in logic;
- data model → a `locale`/`region` column from day one, defaulted, even if single-valued now.

## Project fills in
The current wedge (the exact region/locale/segment/platform/domain) + which parts are deliberately
single-valued for now, in `CHARTER.md`. The reviewer + architecture-safety agents enforce this
against touched code.
