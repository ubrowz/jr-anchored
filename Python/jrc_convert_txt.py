#!/usr/bin/env python3
"""
use as: jrc_convert_txt <file_path> [start_line] [end_line]

"file_path"   path to a plain text file with one numeric value per line,
              no header row.
"start_line"  optional: first line to include (1-based, default: 1)
"end_line"    optional: last line to include (1-based, default: last line)
              Use start_line and end_line to extract a range of interest,
              e.g. to skip a stabilisation period at the start of a test.

Converts a single-column text file into the standard CSV format used by
the jrc statistical suite. Non-numeric lines (empty lines, comments) are
skipped with a warning.

Output CSV has two columns:
  id     -- integer row identifier (1-based, within the selected range)
  value  -- the numeric value

Output is saved to the same directory as the input file. Filename:
  <input_stem>_lines<start>to<end>.csv   (when a range is specified)
  <input_stem>_converted.csv             (when no range is specified)

Example:
  jrc_convert_txt measurements.txt
  jrc_convert_txt measurements.txt 50 200
  jrc_convert_txt measurements.txt 50

Author: Joep Rous
Version: 1.0
"""

import sys
import os

sys.path.insert(0, os.path.join(os.environ.get("JR_PROJECT_ROOT", ""), "bin"))
from jr_helpers import jr_log_output_hashes


def main():
    # -----------------------------------------------------------------------
    # Input validation
    # -----------------------------------------------------------------------

    if len(sys.argv) < 2:
        print("❌ Not enough arguments. Usage:")
        print("     jrc_convert_txt <file_path> [start_line] [end_line]")
        print("   Example:")
        print("     jrc_convert_txt measurements.txt 50 200")
        sys.exit(1)

    file_path = sys.argv[1]

    if not os.path.isfile(file_path):
        print(f"❌ File not found: {file_path}")
        sys.exit(1)

    # Parse optional line range
    start_line = 1
    end_line   = None

    if len(sys.argv) >= 3:
        try:
            start_line = int(sys.argv[2])
            if start_line < 1:
                raise ValueError
        except ValueError:
            print(f"❌ 'start_line' must be a positive integer. Got: {sys.argv[2]}")
            sys.exit(1)

    if len(sys.argv) >= 4:
        try:
            end_line = int(sys.argv[3])
            if end_line < start_line:
                raise ValueError
        except ValueError:
            print(f"❌ 'end_line' must be an integer >= start_line ({start_line}). "
                  f"Got: {sys.argv[3]}")
            sys.exit(1)

    # -----------------------------------------------------------------------
    # Read and parse
    # -----------------------------------------------------------------------

    with open(file_path, "r", encoding="utf-8", errors="replace") as f:
        all_lines = f.readlines()

    total_lines = len(all_lines)

    if end_line is None:
        end_line = total_lines

    if start_line > total_lines:
        print(f"❌ start_line ({start_line}) exceeds total lines in file ({total_lines}).")
        sys.exit(1)

    end_line = min(end_line, total_lines)
    selected = all_lines[start_line - 1 : end_line]   # 0-indexed slice

    values    = []
    skipped   = []
    row_id    = 1

    for line_no, raw in enumerate(selected, start=start_line):
        stripped = raw.strip()
        if not stripped:
            skipped.append((line_no, "empty"))
            continue
        # Allow optional comma as decimal separator (European locale)
        normalized = stripped.replace(",", ".")
        try:
            val = float(normalized)
            values.append((row_id, val))
            row_id += 1
        except ValueError:
            skipped.append((line_no, f"non-numeric: '{stripped[:30]}'"))

    if skipped:
        print(f"⚠️  {len(skipped)} line(s) skipped:")
        for line_no, reason in skipped[:10]:
            print(f"   line {line_no}: {reason}")
        if len(skipped) > 10:
            print(f"   ... and {len(skipped) - 10} more")

    if not values:
        print("❌ No valid numeric values found in the selected range.")
        sys.exit(1)

    # -----------------------------------------------------------------------
    # Build output filename
    # -----------------------------------------------------------------------

    stem     = os.path.splitext(os.path.basename(file_path))[0]
    out_dir  = os.path.dirname(os.path.abspath(file_path))

    # Sanitise stem for safe filename
    safe_stem = "".join(c if c.isalnum() or c in "_-" else "_" for c in stem)

    range_specified = len(sys.argv) >= 3
    if range_specified:
        out_name = f"{safe_stem}_lines{start_line}to{end_line}.csv"
    else:
        out_name = f"{safe_stem}_converted.csv"

    out_path = os.path.join(out_dir, out_name)

    # -----------------------------------------------------------------------
    # Write CSV
    # -----------------------------------------------------------------------

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("id,value\n")
        for row_id, val in values:
            # Preserve full precision
            f.write(f"{row_id},{val!r}\n")

    # -----------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------

    print(" ")
    print("✅ Text File Conversion")
    print("   version: 1.0, author: Joep Rous")
    print("   ========================")
    print(f"   input file:      {file_path}")
    print(f"   lines selected:  {start_line} to {end_line} "
          f"({end_line - start_line + 1} lines)")
    print(f"   values written:  {len(values)}")
    print(f"   lines skipped:   {len(skipped)}")
    print(f"   output file:     {out_path}")
    print(" ")
    print("   Output columns: 'id' (row names), 'value' (data)")
    print("   Use 'value' as the column name argument in jrc_* scripts.")
    print(" ")
    jr_log_output_hashes([out_path])


if __name__ == "__main__":
    main()
