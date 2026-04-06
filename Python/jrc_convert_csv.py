#!/usr/bin/env python3
"""
use as: jrc_convert_csv <file_path> <column> <skip_lines> [delimiter]

"file_path"   path to a delimited data file. May have metadata header lines
              at the top (timestamps, machine info, etc.) before the actual
              column headers or data.
"column"      the column to extract. Can be:
                - a column name (string) if a header row is present after skip_lines
                - a column number (1-based integer) if no header row is present
"skip_lines"  number of lines to skip at the top of the file before reading
              data (e.g. 3 to skip 3 lines of machine header info).
              Set to 0 if the file starts directly with column headers or data.
"delimiter"   optional: column delimiter. Default: auto-detect (tries tab, then
              space, then comma). Pass 'tab', 'space', or 'comma' to force.

Converts a multi-column delimited file into the standard CSV format used by
the jrc statistical suite. Extracts a single column and writes it to a new CSV.

Output CSV has two columns:
  id     -- integer row identifier (1-based)
  value  -- the extracted numeric values

Non-numeric rows in the selected column are skipped with a warning.

Output is saved to the same directory as the input file. Filename:
  <input_stem>_col<column>_skip<n>.csv

Examples:
  jrc_convert_csv data.txt ForceN 3
  jrc_convert_csv data.txt ForceN 3 tab
  jrc_convert_csv data.txt 2 0 space
  jrc_convert_csv data.csv ForceN 5 comma

Author: Joep Rous
Version: 1.0
"""

import sys
import os
import csv
import io

sys.path.insert(0, os.path.join(os.environ.get("JR_PROJECT_ROOT", ""), "bin"))
from jr_helpers import jr_log_output_hashes


def detect_delimiter(sample_lines):
    """Try tab, then space, then comma. Return the one that gives most columns."""
    best_delim = "\t"
    best_count = 0
    for delim in ["\t", " ", ","]:
        # Count columns in first non-empty line
        for line in sample_lines:
            stripped = line.strip()
            if stripped:
                parts = [p for p in stripped.split(delim) if p.strip()]
                if len(parts) > best_count:
                    best_count = len(parts)
                    best_delim = delim
                break
    return best_delim


def split_line(line, delimiter):
    """Split a line by delimiter, stripping whitespace from each field."""
    if delimiter == " ":
        # Split on any whitespace (handles multiple spaces)
        return line.strip().split()
    return [f.strip() for f in line.strip().split(delimiter)]


def main():
    # -----------------------------------------------------------------------
    # Input validation
    # -----------------------------------------------------------------------

    if len(sys.argv) < 4:
        print("❌ Not enough arguments. Usage:")
        print("     jrc_convert_csv <file_path> <column> <skip_lines> [delimiter]")
        print("   Examples:")
        print("     jrc_convert_csv data.txt ForceN 3")
        print("     jrc_convert_csv data.txt ForceN 3 tab")
        print("     jrc_convert_csv data.txt 2 0 space")
        sys.exit(1)

    file_path  = sys.argv[1]
    col_arg    = sys.argv[2]
    skip_arg   = sys.argv[3]
    delim_arg  = sys.argv[4].lower() if len(sys.argv) >= 5 else "auto"

    if not os.path.isfile(file_path):
        print(f"❌ File not found: {file_path}")
        sys.exit(1)

    try:
        skip_lines = int(skip_arg)
        if skip_lines < 0:
            raise ValueError
    except ValueError:
        print(f"❌ 'skip_lines' must be a non-negative integer. Got: {skip_arg}")
        sys.exit(1)

    if delim_arg not in ("auto", "tab", "space", "comma"):
        print(f"❌ 'delimiter' must be 'tab', 'space', 'comma', or omitted for auto. Got: {delim_arg}")
        sys.exit(1)

    delimiter_map = {"tab": "\t", "space": " ", "comma": ","}

    # -----------------------------------------------------------------------
    # Read file
    # -----------------------------------------------------------------------

    with open(file_path, "r", encoding="utf-8", errors="replace") as f:
        all_lines = f.readlines()

    if skip_lines >= len(all_lines):
        print(f"❌ skip_lines ({skip_lines}) >= total lines in file ({len(all_lines)}).")
        sys.exit(1)

    data_lines = all_lines[skip_lines:]

    # -----------------------------------------------------------------------
    # Detect delimiter
    # -----------------------------------------------------------------------

    if delim_arg == "auto":
        delimiter = detect_delimiter(data_lines[:10])
        delim_name = {"\t": "tab", " ": "space", ",": "comma"}.get(delimiter, repr(delimiter))
        print(f"   Auto-detected delimiter: {delim_name}")
    else:
        delimiter  = delimiter_map[delim_arg]
        delim_name = delim_arg

    # -----------------------------------------------------------------------
    # Parse header / column selection
    # -----------------------------------------------------------------------

    # Try to determine if first data line is a header
    col_index   = None
    header_row  = None
    start_index = 0        # index into data_lines where actual data begins

    # Try to parse col_arg as an integer (column number)
    try:
        col_num   = int(col_arg)
        col_index = col_num - 1   # convert to 0-based
        if col_index < 0:
            raise ValueError("Column number must be >= 1")
        print(f"   Column selection: column number {col_num} (1-based)")
    except ValueError as e:
        if "Column number" in str(e):
            print(f"❌ {e}")
            sys.exit(1)
        # col_arg is a column name — look for header row
        col_name  = col_arg
        col_index = None

        # Search first non-empty line for the column name
        for i, line in enumerate(data_lines[:5]):
            fields = split_line(line, delimiter)
            if col_name in fields:
                header_row  = fields
                col_index   = fields.index(col_name)
                start_index = i + 1
                print(f"   Header row found at line {skip_lines + i + 1}")
                print(f"   Column '{col_name}' found at position {col_index + 1}")
                break

        if col_index is None:
            # Show what columns are available
            first_fields = split_line(data_lines[0], delimiter) if data_lines else []
            print(f"❌ Column '{col_name}' not found in the first 5 lines after skipping.")
            if first_fields:
                print(f"   First data line fields: {first_fields}")
            sys.exit(1)

    # -----------------------------------------------------------------------
    # Extract values
    # -----------------------------------------------------------------------

    values  = []
    skipped = []
    row_id  = 1

    for line_no_rel, line in enumerate(data_lines[start_index:], start=1):
        abs_line_no = skip_lines + start_index + line_no_rel
        stripped    = line.strip()
        if not stripped:
            continue

        fields = split_line(stripped, delimiter)

        if col_index >= len(fields):
            skipped.append((abs_line_no, f"only {len(fields)} field(s), expected >= {col_index + 1}"))
            continue

        raw_val = fields[col_index].replace(",", ".")   # handle European decimal comma
        try:
            val = float(raw_val)
            values.append((row_id, val))
            row_id += 1
        except ValueError:
            skipped.append((abs_line_no, f"non-numeric: '{raw_val[:30]}'"))

    if skipped:
        print(f"⚠️  {len(skipped)} row(s) skipped:")
        for line_no, reason in skipped[:10]:
            print(f"   line {line_no}: {reason}")
        if len(skipped) > 10:
            print(f"   ... and {len(skipped) - 10} more")

    if not values:
        print("❌ No valid numeric values found in the selected column.")
        sys.exit(1)

    # -----------------------------------------------------------------------
    # Build output filename
    # -----------------------------------------------------------------------

    stem      = os.path.splitext(os.path.basename(file_path))[0]
    out_dir   = os.path.dirname(os.path.abspath(file_path))
    safe_stem = "".join(c if c.isalnum() or c in "_-" else "_" for c in stem)
    safe_col  = "".join(c if c.isalnum() or c in "_-" else "_" for c in str(col_arg))
    out_name  = f"{safe_stem}_col{safe_col}_skip{skip_lines}.csv"
    out_path  = os.path.join(out_dir, out_name)

    # -----------------------------------------------------------------------
    # Write CSV
    # -----------------------------------------------------------------------

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("id,value\n")
        for row_id, val in values:
            f.write(f"{row_id},{val!r}\n")

    # -----------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------

    print(" ")
    print("✅ Delimited File Conversion")
    print("   version: 1.0, author: Joep Rous")
    print("   ==============================")
    print(f"   input file:      {file_path}")
    print(f"   delimiter:       {delim_name}")
    print(f"   lines skipped:   {skip_lines} (header metadata)")
    print(f"   column:          {col_arg}")
    print(f"   values written:  {len(values)}")
    print(f"   rows skipped:    {len(skipped)}")
    print(f"   output file:     {out_path}")
    print(" ")
    print("   Output columns: 'id' (row names), 'value' (data)")
    print("   Use 'value' as the column name argument in jrc_* scripts.")
    print(" ")
    jr_log_output_hashes([out_path])


if __name__ == "__main__":
    main()
