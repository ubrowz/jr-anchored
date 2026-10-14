#!/usr/bin/env python3
"""
owner_check_price_poll.py — SSJ demand test: the K-factor price poll.

The POLL box on kfactor_calculator.html asks whether a tool that writes the
sample size justification would be worth buying, in price bands. Each answer
is a GoatCounter event; there is no form and no server, so these counts are
the only record.

Two ways in, as owner_check_poll.py:

  * `format_price_poll(window, last7, yest)` is pure formatting. `window` is
    the {path: count} dict for the test window (TEST_START to today), which
    owner_check_analytics.py fetches once; last7/yest are the dicts it
    already has.
  * running this file directly fetches its own data, for an on-demand look.

Reading it honestly
-------------------
`count` is taps, not people (GoatCounter returns no count_unique for
events); the page's localStorage guard (one answer per browser) makes taps a
reasonable proxy. Interest EMAILS are not in GoatCounter: count them in the
inbox. `ssj-preview-mail` only counts clicks on the mailto link.

The decision rule was fixed on 2026-10-13, before the test went live (SSJ
owner's manual, section 3). Do not loosen it to make a number say something.
"mostly" is read as "more than half of the answers", and no verdict is
given below MIN_ANSWERS (one "No" is not a STOP).
"""

import os
import sys
from datetime import date

TEST_START = "2026-10-13"
TEST_READ  = date(2026, 12, 8)      # 8 weeks after upload

# Slug -> label, in price order so the table reads the same every day.
ANSWERS = [
    ("kfactor-price-upto500",   "Yes, up to EUR 500"),
    ("kfactor-price-500-1500",  "Yes, EUR 500-1,500"),
    ("kfactor-price-over1500",  "Yes, over EUR 1,500"),
    ("kfactor-price-no",        "No"),
]
ABOVE_500 = {"kfactor-price-500-1500", "kfactor-price-over1500"}
SKIP  = "kfactor-price-dismissed"
MORE  = "kfactor-price-more"
MAIL  = "ssj-preview-mail"
USED  = "kfactor-calc-used"

# Fixed 2026-10-13 (owner's manual sec. 3).
MIN_ANSWERS = 15
MIN_EMAILS  = 3          # counted by hand, not here


def _page_visits(hits):
    """K-factor page visits: every path of the page itself, not its events."""
    return sum(c for p, c in hits.items()
               if "kfactor_calculator" in p and not p.startswith("kfactor-"))


def _verdict(counts, answers, today=None):
    """One line applying the fixed rule to the GoatCounter part of it."""
    today = today or date.today()
    when = "FINAL" if today >= TEST_READ else f"interim, read on {TEST_READ}"
    if answers == 0:
        return f"No answers yet ({when})."
    if answers < MIN_ANSWERS:
        # Too few to read either way: one "No" is not a STOP.
        return (f"Only {answers} answers: too few to read, the rule needs "
                f"{MIN_ANSWERS}+ ({when}).")
    above = sum(counts[s] for s in ABOVE_500)
    if above * 2 >= answers:
        return (f"GO ({when}): {answers} answers, {above} ({above / answers:.0%}) "
                f"yes above EUR 500.")
    if counts["kfactor-price-no"] * 2 > answers:
        return f"STOP or rethink ({when}): mostly No."
    if counts["kfactor-price-upto500"] * 2 > answers:
        return f"RETHINK price or pitch ({when}): mostly yes up to EUR 500."
    return f"No rule triggered ({when}): mixed answers, judge with the emails."


def format_price_poll(window, last7, yest, today=None):
    """Render the price poll section, or None when nothing is recorded."""
    counts = {s: window.get(s, 0) for s, _ in ANSWERS}
    answers = sum(counts.values())
    skipped = window.get(SKIP, 0)
    used = window.get(USED, 0)
    visits = _page_visits(window)
    if answers == 0 and skipped == 0 and window.get(MORE, 0) == 0:
        return None

    labels = [l for _, l in ANSWERS] + ["ANSWERS", "Skipped", "More about the tool",
                                         "Offer page mail click"]
    w = max(len(x) for x in labels + ["ANSWER"])
    head = f"{'ANSWER':<{w}}  {'TEST':>6}  {'SHARE':>6}  {'7-DAY':>6}  {'YESTERDAY':>9}"
    rule = "-" * len(head)

    lines = [f"SSJ price poll (demand test since {TEST_START})", "", head, rule]
    for slug, label in ANSWERS:
        a = counts[slug]
        share = f"{a / answers:.0%}" if answers else "-"
        lines.append(f"{label:<{w}}  {a:>6}  {share:>6}  {last7.get(slug, 0):>6}"
                     f"  {yest.get(slug, 0):>9}")
    lines.append(rule)
    lines.append(f"{'ANSWERS':<{w}}  {answers:>6}  {'100%' if answers else '-':>6}"
                 f"  {sum(last7.get(s, 0) for s, _ in ANSWERS):>6}"
                 f"  {sum(yest.get(s, 0) for s, _ in ANSWERS):>9}")
    for slug, label in [(SKIP, "Skipped"), (MORE, "More about the tool"),
                        (MAIL, "Offer page mail click")]:
        lines.append(f"{label:<{w}}  {window.get(slug, 0):>6}  {'':>6}"
                     f"  {last7.get(slug, 0):>6}  {yest.get(slug, 0):>9}")
    lines.append("")
    lines.append(f"Denominator since {TEST_START}: {visits} K-factor page visits, "
                 f"{used} calculator uses.")
    if visits:
        lines.append(f"Response rate: {(answers + skipped) / visits:.0%} of page visits "
                     f"({answers} answered, {skipped} skipped)")
    lines.append(f"Verdict: {_verdict(counts, answers, today)}")
    lines.append(f"Also GO with >= {MIN_EMAILS} interest emails: count those in the inbox.")
    lines.append("Counts are taps, not people.")
    return "\n".join(lines)


def main() -> int:
    """Standalone run: fetch our own data and print the section."""
    print()
    print("JR Anchored — SSJ Price Poll")
    print("=" * 60)
    token = os.environ.get("GOATCOUNTER_API_TOKEN", "").strip()
    if not token:
        print("  GOATCOUNTER_API_TOKEN not set — skipping poll results.")
        return 0

    # Imported here: owner_check_analytics imports this module.
    from datetime import timedelta, timezone, datetime
    from owner_check_analytics import _fetch_hits, _iso

    now = datetime.now(timezone.utc)
    today0 = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end = _iso(today0)
    try:
        window = _fetch_hits(token, TEST_START + "T00:00:00Z", end)
        last7 = _fetch_hits(token, _iso(today0 - timedelta(days=7)), end)
        yest = _fetch_hits(token, _iso(today0 - timedelta(days=1)), end)
    except Exception as exc:  # noqa: BLE001 — informational, never fail the cron
        print(f"  ⚠️  Could not fetch GoatCounter stats: {exc}")
        return 0

    section = format_price_poll(window, last7, yest)
    if section is None:
        print("  Price poll has recorded nothing yet.")
        return 0
    for line in section.split("\n"):
        print(f"  {line}")
    return 0


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    sys.exit(main())
