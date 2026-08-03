#!/usr/bin/env python3
"""
IBKR to Yahoo Finance CSV Converter

Converts Interactive Brokers (IBKR) CSV export files (Portfolio Analyst,
Flex Queries, Activity Statements) into Yahoo Finance portfolio import CSV format:
    Symbol,Trade Date,Purchase Price,Quantity

Usage:
    python convert_ibkr_to_yahoo.py [options]

Options:
    -i, --input PATH     Input IBKR CSV file or directory (default: inputs/)
    -o, --output PATH    Output Yahoo CSV file or directory (default: outputs/)
    -s, --source SECTION Data section to parse: 'positions' (default) or 'trades'
    -v, --verbose        Enable verbose output
"""

import argparse
import csv
import glob
import os
import re
import sys
from datetime import datetime
from pathlib import Path


def parse_date(date_str):
    """
    Parses various date formats and converts to YYYY-MM-DD.
    Supported formats include MM/DD/YYYY, YYYY-MM-DD, YYYYMMDD, DD/MM/YYYY, etc.
    """
    if not date_str or not isinstance(date_str, str):
        return None

    date_str = date_str.strip()
    if not date_str or date_str.lower() in ("total", "subtotal", "n/a", "-"):
        return None

    # Try common ISO and standard formats
    formats = [
        "%m/%d/%Y",       # 07/31/2026
        "%Y-%m-%d",       # 2026-07-31
        "%Y%m%d",         # 20260731
        "%d/%m/%Y",       # 31/07/2026
        "%Y/%m/%d",       # 2026/07/31
        "%m-%d-%Y",       # 07-31-2026
        "%d-%m-%Y",       # 31-07-2026
        "%Y-%m-%d %H:%M:%S", # 2026-07-31 14:30:00
    ]

    for fmt in formats:
        try:
            dt = datetime.strptime(date_str, fmt)
            return dt.strftime("%Y-%m-%d")
        except ValueError:
            continue

    # Regex attempt for YYYYMMDD if string contains digits
    match = re.search(r"(\d{4})[-/]?(\d{2})[-/]?(\d{2})", date_str)
    if match:
        year, month, day = match.groups()
        return f"{year}-{month}-{day}"

    return date_str


def clean_symbol(symbol):
    """
    Cleans stock symbol/ticker for Yahoo Finance compatibility.
    e.g. BRK B -> BRK-B, GOOGL -> GOOGL
    """
    if not symbol:
        return ""
    symbol = str(symbol).strip().upper()
    # Replace space or dot with hyphen for share classes (e.g. BRK.B -> BRK-B) if needed
    # But preserve standard symbols
    symbol = re.sub(r"\s+", "-", symbol)
    return symbol


def parse_ibkr_csv(file_path, source_type="positions", verbose=False):
    """
    Reads an IBKR export CSV file and extracts open positions or trades.
    Returns a list of dicts: [{'Symbol': ..., 'Trade Date': ..., 'Purchase Price': ..., 'Quantity': ...}]
    """
    results = []
    
    if not os.path.exists(file_path):
        print(f"Error: Input file '{file_path}' does not exist.", file=sys.stderr)
        return results

    with open(file_path, "r", encoding="utf-8-sig", errors="replace") as f:
        reader = csv.reader(f)
        
        current_section = None
        headers = {}
        as_of_date = None

        for line_num, row in enumerate(reader, 1):
            if not row or len(row) < 3:
                continue

            section_name = row[0].strip()
            record_type = row[1].strip()

            # Track MetaInfo "As Of" date if present
            if record_type == "MetaInfo":
                for i in range(2, len(row) - 1):
                    if row[i].strip().lower() == "as of":
                        parsed_meta_date = parse_date(row[i + 1])
                        if parsed_meta_date:
                            as_of_date = parsed_meta_date

            # Process Section Headers
            if record_type == "Header":
                current_section = section_name
                # Map normalized column names to index relative to row[2:]
                cols = [col.strip().lower() for col in row[2:]]
                headers[current_section] = cols
                if verbose:
                    print(f"[Line {line_num}] Found header for section '{current_section}': {cols}")
                continue

            # Process Section Data
            if record_type == "Data" and current_section:
                sec_lower = current_section.lower()
                is_target_section = False

                if source_type == "positions" and ("open position" in sec_lower or "position summary" in sec_lower or "positions" in sec_lower):
                    is_target_section = True
                elif source_type == "trades" and ("trade summary" in sec_lower or "trade" in sec_lower or "transaction" in sec_lower):
                    is_target_section = True
                elif source_type == "auto":
                    if "open position" in sec_lower or "position summary" in sec_lower or "positions" in sec_lower or "trade summary" in sec_lower:
                        is_target_section = True

                if not is_target_section:
                    continue

                sec_cols = headers.get(current_section, [])
                if not sec_cols:
                    continue

                # Build dictionary for row values
                val_row = row[2:]
                row_dict = {}
                for idx, col_name in enumerate(sec_cols):
                    if idx < len(val_row):
                        row_dict[col_name] = val_row[idx].strip()

                # Extract fields using flexible column matching
                symbol = (
                    row_dict.get("symbol")
                    or row_dict.get("ticker")
                    or row_dict.get("financial instrument")
                    or row_dict.get("financialinstrument")
                )
                if not symbol or symbol.lower() in ("total", "subtotal", "header", ""):
                    continue

                # Filter out cash, forex, or summary rows
                instrument = (
                    row_dict.get("financial instrument")
                    or row_dict.get("financialinstrument")
                    or row_dict.get("asset class")
                    or row_dict.get("assetclass")
                    or ""
                ).lower()

                if instrument in ("cash", "forex", "total"):
                    continue

                # Quantity
                raw_qty = (
                    row_dict.get("quantity")
                    or row_dict.get("quantity bought")
                    or row_dict.get("shares")
                    or "0"
                )
                try:
                    qty = float(raw_qty.replace(",", ""))
                except ValueError:
                    continue

                if qty <= 0:
                    continue

                # Date
                raw_date = (
                    row_dict.get("date")
                    or row_dict.get("trade date")
                    or row_dict.get("as of")
                    or row_dict.get("paydate")
                )
                trade_date = parse_date(raw_date) if raw_date else as_of_date
                if not trade_date:
                    trade_date = datetime.today().strftime("%Y-%m-%d")

                # Purchase Price calculation
                # Priority 1: Cost Basis / Quantity (for position summary)
                # Priority 2: Proceeds Bought / Quantity Bought (for trade summary)
                # Priority 3: Average Price Bought / Price / ClosePrice
                purchase_price = None
                raw_cost_basis = (
                    row_dict.get("cost basis")
                    or row_dict.get("costbasis")
                    or row_dict.get("proceeds bought")
                )
                raw_price = (
                    row_dict.get("average price bought")
                    or row_dict.get("closeprice")
                    or row_dict.get("price")
                )

                if raw_cost_basis:
                    try:
                        cost_basis = float(raw_cost_basis.replace(",", "").replace("$", ""))
                        cost_basis = abs(cost_basis)
                        if qty > 0 and cost_basis > 0:
                            purchase_price = cost_basis / qty
                    except ValueError:
                        pass

                if purchase_price is None and raw_price:
                    try:
                        purchase_price = float(raw_price.replace(",", "").replace("$", ""))
                    except ValueError:
                        pass

                if purchase_price is None or purchase_price <= 0:
                    if verbose:
                        print(f"Skipping {symbol}: Could not determine valid purchase price.")
                    continue

                symbol_clean = clean_symbol(symbol)

                results.append({
                    "Symbol": symbol_clean,
                    "Trade Date": trade_date,
                    "Purchase Price": f"{purchase_price:.4f}".rstrip("0").rstrip("."),
                    "Quantity": f"{qty:.6f}".rstrip("0").rstrip(".")
                })

    return results


def write_yahoo_csv(records, output_file_path):
    """
    Writes parsed records to Yahoo Finance portfolio CSV format.
    Format: Symbol,Trade Date,Purchase Price,Quantity
    """
    output_dir = os.path.dirname(output_file_path)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir, exist_ok=True)

    fieldnames = ["Symbol", "Trade Date", "Purchase Price", "Quantity"]
    
    with open(output_file_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for rec in records:
            writer.writerow(rec)


def convert_file(input_path, output_path, source_type="positions", verbose=False):
    """
    Converts a single IBKR CSV file to Yahoo Finance CSV format.
    """
    if verbose:
        print(f"Processing input file: {input_path}")

    records = parse_ibkr_csv(input_path, source_type=source_type, verbose=verbose)
    
    if not records:
        print(f"Warning: No valid records found in '{input_path}'.", file=sys.stderr)
        return False

    write_yahoo_csv(records, output_path)
    print(f"Successfully converted {len(records)} positions -> '{output_path}'")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Convert IBKR CSV exports to Yahoo Finance portfolio import CSV format."
    )
    parser.add_argument(
        "-i", "--input",
        default="inputs",
        help="Input IBKR CSV file or directory containing CSV files (default: inputs/)"
    )
    parser.add_argument(
        "-o", "--output",
        default="outputs",
        help="Output Yahoo CSV file or directory (default: outputs/)"
    )
    parser.add_argument(
        "-s", "--source",
        choices=["positions", "trades", "auto"],
        default="positions",
        help="Data section to parse: 'positions' (default), 'trades', or 'auto'"
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable verbose output logging"
    )

    args = parser.parse_args()

    input_path = os.path.abspath(args.input)
    output_path = os.path.abspath(args.output)

    # Case 1: Input path is a single file
    if os.path.isfile(input_path):
        if os.path.isdir(output_path) or output_path.endswith("/") or output_path.endswith("\\"):
            base_name = os.path.splitext(os.path.basename(input_path))[0]
            out_file = os.path.join(output_path, f"{base_name}_yahoo.csv")
        else:
            out_file = output_path
        convert_file(input_path, out_file, source_type=args.source, verbose=args.verbose)

    # Case 2: Input path is a directory
    elif os.path.isdir(input_path):
        csv_files = glob.glob(os.path.join(input_path, "*.csv"))
        if not csv_files:
            print(f"No CSV files found in directory '{input_path}'.", file=sys.stderr)
            sys.exit(1)

        os.makedirs(output_path, exist_ok=True)
        success_count = 0

        for file_file in sorted(csv_files):
            base_name = os.path.splitext(os.path.basename(file_file))[0]
            out_file = os.path.join(output_path, f"{base_name}_yahoo.csv")
            if convert_file(file_file, out_file, source_type=args.source, verbose=args.verbose):
                success_count += 1

        print(f"\nBatch processing complete: {success_count}/{len(csv_files)} files converted successfully.")

    else:
        print(f"Error: Input path '{input_path}' not found.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
