---
name: autoresearch
description: Use when optimizing any measurable metric through autonomous experimentation loops. Triggers on "autoresearch", "optimize", "experiment loop", "A/B test", "improve metric", "self-improving", "iterate autonomously", landing page copy, cold email optimization, product ranking, pricing optimization, SEO content, ad creative testing, conversion rate optimization, thumbnail testing, or any task with an objective metric and a changeable variable. DO NOT USE for one-shot tasks, subjective goals without metrics, or tasks without a feedback signal.
---

# Autoresearch: Autonomous Experimentation Loop

Inspired by [Karpathy's autoresearch](https://github.com/karpathy/autoresearch). Generalized from ML training to **any task with a measurable outcome**.

Core principle: **One metric. One variable. Infinite loop. Keep winners. Discard losers. Never stop.**

## When to Use

- Optimizing conversion rates, reply rates, CTR, revenue, scores
- A/B testing copy, pricing, product rankings, email sequences
- Any programming task with a benchmark (speed, size, coverage)
- Content optimization (titles, descriptions, thumbnails)
- Prompt/skill optimization with binary evals

## When NOT to Use

- Subjective goals ("make it feel better")
- No measurable metric exists
- One-shot tasks with no iteration
- Feedback loop longer than 30 days (signal too slow)

---

## Phase 1: Setup (Interactive — Do NOT Skip)

Ask the user for each item. Never assume. Confirm before proceeding.

### 1.1 Goal

> What are you trying to improve? Be specific.

Examples: conversion rate, reply rate, click-through rate, val_bpb, response time, revenue per session, eval score, ad ROAS, open rate.

### 1.2 Metric

> How do we measure it? I need:
> 1. **Source**: API call, database query, command, file, or manual input?
> 2. **Extraction**: How to get the number (grep, jq, SQL, API field)?
> 3. **Direction**: Lower is better or higher is better?

Record: `METRIC_SOURCE`, `METRIC_EXTRACTION`, `METRIC_DIRECTION`

**If no API exists**: Use browser automation, screenshots, manual CSV dumps, or scheduled scraping. Document the data collection method.

### 1.3 Variable (What Changes)

> What single thing are you changing between experiments?

Examples: email copy, product description, landing page headline, pricing, code file, prompt template, product ranking formula, ad creative.

Record: `MUTABLE_FILES` — files/assets the agent may edit.

### 1.4 Scope Boundary

> What is OFF LIMITS?

Record: `IMMUTABLE_FILES` — files that must never be modified.

### 1.5 Eval Criteria (Binary — No Vibes)

> Do you have binary (yes/no) eval criteria for scoring?

If YES: Record them. Each eval must be a yes/no question answerable by an agent.

If NO: Help the user create 3-6 binary evals. Follow these rules:
- Every eval is yes/no. Never scales (1-10). Never vibes.
- Each eval tests something distinct (no overlap).
- "Could two agents score the same output and agree?" — if no, rewrite.
- "Could the system game this without improving?" — if yes, broaden.

**Good evals:**
- "Does the headline state a specific outcome, not just a feature?"
- "Is the CTA an action verb + benefit (not just 'Get Started')?"
- "Does the first sentence contain a claim, story, or question?"
- "Is the copy under 150 words?"

**Bad evals:**
- "Is the writing good?" (vague)
- "Rate engagement 1-10" (scale = unreliable)
- "Does it sound professional?" (subjective)

Max score = number of evals. Record as `EVAL_CRITERIA`.

### 1.6 Constraints

> Any limits?
> - Time budget per experiment?
> - Dependencies/packages policy?
> - Must existing tests still pass?
> - Resource limits (VRAM, API rate limits, budget)?

Record as `CONSTRAINTS`.

### 1.7 Loop Frequency

> How often should experiments run?
> - Fast loop (minutes): code benchmarks, eval scoring, prompt testing
> - Medium loop (hours): cold email, ad testing with enough volume
> - Slow loop (days/weeks): landing pages, SEO, pricing (need traffic)

Record: `LOOP_FREQUENCY`

### 1.8 Experiment Budget

> How many experiments? A number (e.g., 20) or "unlimited" (run until interrupted)?

Record: `MAX_EXPERIMENTS`

### 1.9 Confirm Setup

Summarize ALL parameters in a table. Ask user to confirm. Do NOT proceed until confirmed.

| Parameter | Value |
|-----------|-------|
| Goal | ... |
| Metric source | ... |
| Metric extraction | ... |
| Direction | ... |
| Mutable files | ... |
| Immutable files | ... |
| Eval criteria | ... |
| Constraints | ... |
| Loop frequency | ... |
| Max experiments | ... |

---

## Phase 2: Branch & Baseline

1. **Create branch**: `git checkout -b autoresearch/<tag>` (propose tag from today's date).

2. **Read all mutable files** to build full context.

3. **Initialize tracking files** (add to `.git/info/exclude` so they stay untracked):

   **results.tsv** — Tab-separated experiment log:
   ```
   experiment	commit	metric	eval_score	status	description
   ```

   **learnings.md** — Accumulated knowledge (the most valuable artifact):
   ```markdown
   # Learnings
   ## What Works
   ## What Doesn't Work
   ## Patterns Discovered
   ## Current Best Configuration
   ```

4. **Run baseline**: Measure current state with no changes. Record as experiment `0`, status `baseline`.

5. **Report to user**:
   > Baseline: **[metric] = [value]**, eval score: **[X]/[max]**
   > Starting autonomous loop.

---

## Phase 3: Experiment Loop

**NEVER STOP.** Do not pause to ask "should I continue?" The user may be away. Run until `MAX_EXPERIMENTS` reached or manually interrupted. If stuck, think harder — reread learnings.md, combine near-misses, try radical changes.

### For Each Experiment:

```
LOOP FOREVER:

1. THINK    — Read learnings.md and results.tsv.
              What worked? What failed? What's untried?
              Form ONE hypothesis. Write it down.

2. EDIT     — Make ONE focused change to mutable files.
              Small, testable changes. Not full rewrites.

3. COMMIT   — git add + git commit -m "experiment: <description>"

4. RUN      — Execute the metric command.
              Redirect output: command > run.log 2>&1
              Do NOT let output flood context window.

5. MEASURE  — Extract metric from run.log or API response.
              If crash: read last 50 lines of run.log.

6. SCORE    — Run output through eval criteria (if applicable).
              Count binary pass/fail for each eval.

7. DECIDE   —
              IMPROVED (metric better):
                Keep commit. Update learnings.md "What Works".
                Log status = "keep"

              SAME OR WORSE:
                git reset --hard HEAD~1
                Update learnings.md "What Doesn't Work".
                Log status = "discard"

              CRASH:
                Attempt quick fix (typo, import, simple error).
                If unfixable after 2 attempts: revert, log "crash".

8. LOG      — Append row to results.tsv.

9. UPDATE   — Append insight to learnings.md.
              What did this experiment teach us?

10. CONTINUE — Go to step 1. Do NOT stop.
```

### Experiment Strategy (Priority Order)

1. **Low-hanging fruit** — Simple tweaks, obvious improvements
2. **Double down on winners** — If a direction worked, push further
3. **Combine winners** — If A and B each improved, try A+B
4. **Diversify after plateau** — 3-5 consecutive failures → try different axis entirely
5. **Simplification passes** — Remove complexity, check if metric holds
6. **Radical changes** — After exhausting incremental ideas, try big rewrites

### Simplicity Criterion

All else equal, simpler is better:
- Small improvement + ugly complexity = probably not worth it
- Same metric + less code = definitely keep
- Improvement from deleting code = best outcome

### Crash Handling

- **Dumb bug** (typo, import): Fix and rerun. Same experiment number.
- **Fundamentally broken idea**: Revert, log "crash", move on. Don't waste 3+ attempts.
- **Timeout** (exceeds 2x expected duration): Kill, treat as crash.

---

## Phase 4: Reporting

When loop ends (budget reached or user interrupts):

1. **Print results.tsv** as formatted table.
2. **Summary**:
   - Total experiments: X (kept: Y, discarded: Z, crashed: W)
   - Baseline metric → Final metric (X% improvement)
   - Top 3 most impactful changes
3. **Show git log**: `git log --oneline <start>..HEAD`
4. **Recommend next steps**: Ideas too risky/complex for this session.
5. **Highlight learnings.md**: This is the most valuable output. When a better model arrives, hand it this file and it continues where you left off.

---

## learnings.md: The Shared Brain

This file is **the most important artifact**. It compounds across sessions.

Every agent MUST:
- **Read learnings.md BEFORE starting any experiment**
- **Append to learnings.md AFTER every experiment** (win or lose)

Structure:
```markdown
# Learnings

## What Works
- [Date] Shorter headlines convert 12% better (exp #5, #8, #12)
- [Date] Urgency language in CTA increased clicks (exp #7)

## What Doesn't Work
- [Date] Question-style headlines underperform statements (exp #3, #9)
- [Date] Exclamation marks correlate with lower CTR (exp #4)

## Patterns Discovered
- Price sensitivity is highest in $30-50 range
- Morning sends outperform evening by 15%

## Current Best Configuration
- Headline: "How to [specific result] in [timeframe]"
- CTA: "[Action verb] + Free + [Benefit]"
- Price: $X.95 endings, 20% bundle discount
```

---

## Business Use Case Templates

### Cold Email Optimization
```
Goal: Increase positive reply rate
Metric: Reply count / sent count (from Instantly/Smartlead API)
Direction: Higher is better
Mutable: email_copy.md, subject_lines.md
Immutable: lead_list.csv, sending_config
Loop: Every 4 hours (harvest → generate challenger → deploy)
Evals:
  1. Is the email under 75 words?
  2. Does it open with relevance to the recipient's business?
  3. Does it contain a specific, time-bound CTA?
  4. Is it free of "salesy" words (revolutionary, game-changing, excited)?
  5. Does it include a risk-reversal (free, no commitment, guarantee)?
```

### Landing Page Copy
```
Goal: Increase signup/purchase conversion rate
Metric: Conversions / sessions (from analytics API)
Direction: Higher is better
Mutable: hero section, feature bullets, CTA text, meta description
Immutable: layout, images, pricing logic
Loop: Weekly (need 250+ conversion events for stable signal)
Evals:
  1. Does headline state a specific outcome, not just a feature?
  2. Is there social proof within first scroll?
  3. Does CTA use action verb + benefit?
  4. Does copy address the #1 switching objection?
  5. Is there a risk-reversal (free trial, money-back)?
  6. Would a visitor scanning for 5 seconds understand the value?
```

### Product Ranking (Dropshipping)
```
Goal: Maximize revenue per collection page view
Metric: Revenue / page_views (from database)
Direction: Higher is better
Mutable: scoring_formula.ts, rank weights
Immutable: product data, frontend display, Trendsi sync
Loop: Weekly (after enough order data)
Evals:
  1. Do top-10 products have >80% variant availability?
  2. Are top-ranked products priced within the collection average?
  3. Does scoring formula use at least 3 signals?
  4. Are out-of-stock products excluded from top positions?
```

### SEO Content
```
Goal: Increase organic clicks
Metric: Clicks from Google Search Console API
Direction: Higher is better
Mutable: blog posts, product descriptions, meta tags
Immutable: site structure, URLs, images
Loop: Bi-weekly (SEO feedback is slow)
Evals:
  1. Does title contain primary keyword in first 60 chars?
  2. Does meta description contain a specific benefit?
  3. Is the article over 800 words?
  4. Does it include at least one comparison with a named competitor?
  5. Does it contain a clear CTA to the product?
```

### Pricing Optimization
```
Goal: Maximize revenue per visitor (NOT just conversion rate)
Metric: Total revenue / total sessions
Direction: Higher is better
Mutable: price points, tier structure, discount percentages
Immutable: product catalog, payment flow
Loop: Weekly (need volume for stable signal)
Note: Revenue per visitor matters because $79 × 3% conversion
      beats $49 × 4% conversion ($2.37 vs $1.96 per visitor)
```

### Prompt/Skill Optimization
```
Goal: Increase eval pass rate
Metric: Pass count / (eval_count × runs_per_experiment)
Direction: Higher is better
Mutable: SKILL.md or prompt template
Immutable: eval criteria, test inputs
Loop: Fast (minutes — generate, score, mutate, repeat)
Good mutations:
  - Add specific instruction for most common failure
  - Reword ambiguous instruction
  - Add anti-pattern for recurring mistake
  - Move buried instruction higher (position = priority)
Bad mutations:
  - Rewrite from scratch
  - Add 10 rules at once
  - Vague ("make it better")
```

---

## Multi-Project Operation

Run multiple autoresearch loops from one machine using tmux or separate terminals:

```
Terminal 1: Your normal dev work
Terminal 2: cd ~/autoresearch/project-a && claude -p "$(cat program.md)"
Terminal 3: cd ~/autoresearch/project-b && claude -p "$(cat program.md)"
```

Each project gets its own:
- `program.md` (project-specific instructions)
- `learnings.md` (project-specific knowledge)
- `results.tsv` (project-specific experiment log)

Cross-project learnings: Manually copy insights between learnings.md files when patterns transfer (e.g., copy patterns that work for email also work for landing pages).

---

## Key Principles

1. **Measure everything** — No experiment without a measurement.
2. **Binary evals only** — No scales, no vibes. Yes/no.
3. **Revert failures** — Branch only advances on improvements.
4. **Never stop** — Think harder if stuck. Reread learnings. Combine near-misses.
5. **Log everything** — results.tsv + learnings.md are the research journal.
6. **Simplicity wins** — Complexity is a cost. Weigh against gains.
7. **The log is the asset** — When better models arrive, hand them learnings.md.
8. **One change per experiment** — Isolate variables. Know what caused improvement.
9. **Accumulate knowledge** — Read learnings.md before every experiment, write after every experiment.
10. **Fast loops beat slow loops** — Tighter feedback = faster improvement. Design for speed.
