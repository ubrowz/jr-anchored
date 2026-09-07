#!/usr/bin/env python3
"""
owner_check_poll.py — K-factor role poll results.

The poll lives at the top of kfactor_calculator.html: one question, one tap,
answered as a GoatCounter event. There is no form and no server, so these
counts are the only record of who is using the tool.

Two ways in:

  * `format_poll(all_time, last7, yest)` is pure formatting and takes the hit
    dicts owner_check_analytics.py has ALREADY fetched, so folding this into
    the daily report costs zero extra API calls.
  * running this file directly fetches its own data, for an on-demand look.

Requires GOATCOUNTER_API_TOKEN only in standalone mode (set as a Render
dashboard secret, sync: false).

Reading it honestly
-------------------
`count` is taps, not people: GoatCounter returns no count_unique for events.
The page's localStorage guard (one answer per browser, ever) is what makes
taps a reasonable proxy for people.

The verdict below applies thresholds agreed on 2026-09-05, BEFORE any data
existed, precisely so a result cannot be rationalised after the fact. Do not
loosen them to make a number say something.
"""

import os
import sys

# Slug -> label. Order is the display order, chosen to read as a hierarchy
# rather than by count, so the table looks the same from day to day.
ROLES = [
    ("kfactor-role-quality",       "Quality / QA"),
    ("kfactor-role-rnd",           "R&D / Design"),
    ("kfactor-role-regulatory",    "Regulatory"),
    ("kfactor-role-manufacturing", "Manufacturing"),
    ("kfactor-role-student",       "Student"),
    ("kfactor-role-other",         "Other"),
]
SKIP  = "kfactor-role-dismissed"
USED  = "kfactor-calc-used"

# Agreed 2026-09-05, before the data arrived. See the module docstring.
DOMINANT_ONE = 0.40   # one role above this share of answers = that is the audience
DOMINANT_TWO = 0.60   # top two combined above this = two audiences
FLAT_CEILING = 0.30   # nothing above this = no concentration, do not tell a story
MIN_ANSWERS  = 12     # below this, say so and refuse to call it


def _verdict(rows, answers):
    """One line saying what the numbers do and do not support."""
    if answers == 0:
        return "No answers yet."
    if answers < MIN_ANSWERS:
        return (f"Only {answers} answers so far: too few to read. "
                f"Wait for {MIN_ANSWERS}+.")
    ranked = sorted(rows, key=lambda r: -r[1])
    top_label, top_n = ranked[0][0], ranked[0][1]
    second_n = ranked[1][1] if len(ranked) > 1 else 0
    top_share = top_n / answers
    two_share = (top_n + second_n) / answers
    # A leader over 40% only means ONE audience if it is clearly ahead of the
    # runner-up. Without the second test a 42/38 split reports as "Quality is
    # the audience" when it plainly shows two, which is what the 42/38 test
    # case caught.
    if top_share > DOMINANT_ONE and top_n >= 2 * second_n:
        return (f"{top_label} is {top_share:.0%} of answers and well clear of "
                f"the rest: that is the audience. Build and pitch for them.")
    if two_share > DOMINANT_TWO:
        return (f"{top_label} + {ranked[1][0]} are {two_share:.0%} combined: "
                f"two audiences, and the site should address both.")
    if top_share <= FLAT_CEILING:
        return ("No role above 30%: general engineering audience, no "
                "concentration. Do not reach for a story.")
    return (f"{top_label} leads at {top_share:.0%}, short of the 40% bar. "
            f"Nothing decided yet.")


def format_poll(all_time, last7, yest):
    """Render the poll section, or None when the poll has recorded nothing.

    Each argument is a {path: count} dict as returned by
    owner_check_analytics._fetch_hits. Returns a plain-text block, or None so
    the caller can omit the section entirely rather than print an empty table.
    """
    rows = [(label, all_time.get(slug, 0), last7.get(slug, 0), yest.get(slug, 0))
            for slug, label in ROLES]
    answers  = sum(r[1] for r in rows)
    skipped  = all_time.get(SKIP, 0)
    used     = all_time.get(USED, 0)

    if answers == 0 and skipped == 0 and used == 0:
        return None                      # not deployed yet, or nothing recorded

    # Every label that appears in the first column, or the summary rows below
    # overflow their column and shove the numbers out of alignment.
    w = max(len(x) for x in
            ["ROLE", "ANSWERS", "Skipped", "Calculator used"] + [r[0] for r in rows])
    head = f"{'ROLE':<{w}}  {'ALL-TIME':>9}  {'SHARE':>6}  {'7-DAY':>7}  {'YESTERDAY':>9}"
    rule = "-" * len(head)

    lines = ["K-factor role poll", "", head, rule]
    for label, a, s7, y in sorted(rows, key=lambda r: -r[1]):
        share = f"{a / answers:.0%}" if answers else "-"
        lines.append(f"{label:<{w}}  {a:>9}  {share:>6}  {s7:>7}  {y:>9}")
    lines.append(rule)
    lines.append(f"{'ANSWERS':<{w}}  {answers:>9}  {'100%' if answers else '-':>6}"
                 f"  {sum(r[2] for r in rows):>7}  {sum(r[3] for r in rows):>9}")
    lines.append(f"{'Skipped':<{w}}  {skipped:>9}  {'':>6}"
                 f"  {last7.get(SKIP, 0):>7}  {yest.get(SKIP, 0):>9}")
    lines.append(f"{'Calculator used':<{w}}  {used:>9}  {'':>6}"
                 f"  {last7.get(USED, 0):>7}  {yest.get(USED, 0):>9}")
    lines.append("")

    if used:
        # Skips count as engagement with the question, so they belong in the
        # numerator: the point is what share of users responded at all.
        lines.append(f"Response rate: {(answers + skipped) / used:.0%} "
                     f"of {used} calculator uses ({answers} answered, "
                     f"{skipped} skipped)")
    else:
        lines.append("Response rate: not computable yet (no calculator uses "
                     "recorded)")
    lines.append(f"Verdict: {_verdict(rows, answers)}")
    lines.append("Counts are taps, not people (GoatCounter returns no "
                 "count_unique for events).")
    return "\n".join(lines)


def main() -> int:
    """Standalone run: fetch our own data and print the section."""
    print()
    print("JR Anchored — K-factor Role Poll")
    print("=" * 60)

    token = os.environ.get("GOATCOUNTER_API_TOKEN", "").strip()
    if not token:
        print("  GOATCOUNTER_API_TOKEN not set — skipping poll results.")
        print("  Create a token at dwylup.goatcounter.com -> Settings -> API")
        print("  and add it in the Render dashboard (secret env var).")
        return 0

    # Imported here, not at module level: owner_check_analytics imports
    # format_poll from this file, and a top-level import would be circular.
    from datetime import timedelta, timezone, datetime
    from owner_check_analytics import _fetch_hits, _iso, EPOCH

    now = datetime.now(timezone.utc)
    today0 = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end = _iso(today0)
    try:
        all_time = _fetch_hits(token, EPOCH, end)
        last7 = _fetch_hits(token, _iso(today0 - timedelta(days=7)), end)
        yest = _fetch_hits(token, _iso(today0 - timedelta(days=1)), end)
    except Exception as exc:  # noqa: BLE001 — informational, never fail the cron
        print(f"  ⚠️  Could not fetch GoatCounter stats: {exc}")
        return 0

    section = format_poll(all_time, last7, yest)
    if section is None:
        print("  Poll has recorded nothing yet.")
        return 0
    for line in section.split("\n"):
        print(f"  {line}")
    return 0


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    sys.exit(main())
