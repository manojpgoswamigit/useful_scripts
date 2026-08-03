#!/usr/bin/env python3
"""
Unit tests for IBKR to Yahoo Finance CSV converter.
"""

import csv
import os
import sys
import tempfile
import unittest
from pathlib import Path

# Add parent directory to sys.path to import converter module
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from convert_ibkr_to_yahoo import (
    clean_symbol,
    convert_file,
    parse_date,
    parse_ibkr_csv,
    write_yahoo_csv,
)


class TestIBKRToYahooConverter(unittest.TestCase):

    def test_parse_date(self):
        """Test parsing of various date formats."""
        self.assertEqual(parse_date("07/31/2026"), "2026-07-31")
        self.assertEqual(parse_date("2026-07-31"), "2026-07-31")
        self.assertEqual(parse_date("20260731"), "2026-07-31")
        self.assertEqual(parse_date("31/07/2026"), "2026-07-31")
        self.assertIsNone(parse_date("Total"))
        self.assertIsNone(parse_date(""))
        self.assertIsNone(parse_date(None))

    def test_clean_symbol(self):
        """Test cleaning and normalizing stock tickers."""
        self.assertEqual(clean_symbol("GOOG"), "GOOG")
        self.assertEqual(clean_symbol("brk b"), "BRK-B")
        self.assertEqual(clean_symbol("  aapl  "), "AAPL")
        self.assertEqual(clean_symbol(""), "")

    def test_parse_open_position_summary(self):
        """Test parsing Open Position Summary lines from mock IBKR CSV content."""
        csv_content = (
            'Open Position Summary,Header,Date,FinancialInstrument,Currency,Symbol,Description,Sector,Quantity,ClosePrice,Value,Cost Basis,UnrealizedP&L,FXRateToBase\n'
            'Open Position Summary,Data,07/31/2026,ETFs,USD,DRAM,ROUNDHILL MEMORY ETF,Technology,200,50.37,10074,13681.0006,-3607.0006,1.4017\n'
            'Open Position Summary,Data,07/31/2026,Stocks,USD,AAPL,APPLE INC,Technology,32,308.91,9885.12,9479.600096,405.519904,1.4017\n'
            'Open Position Summary,Data,Total,ETFs,USD,,,,,,10074,13681.0006,-3607.0006\n'
            'Open Position Summary,Data,07/31/2026,Cash,CAD,CAD,Canadian Dollar,Cash,1310.446799,1,1310.446799, , ,1\n'
        )

        with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".csv") as tmp:
            tmp.write(csv_content)
            tmp_path = tmp.name

        try:
            records = parse_ibkr_csv(tmp_path, source_type="positions")
            self.assertEqual(len(records), 2)
            
            # Record 1: DRAM
            self.assertEqual(records[0]["Symbol"], "DRAM")
            self.assertEqual(records[0]["Trade Date"], "2026-07-31")
            self.assertEqual(records[0]["Quantity"], "200")
            # 13681.0006 / 200 = 68.405003 -> "68.405"
            self.assertEqual(records[0]["Purchase Price"], "68.405")

            # Record 2: AAPL
            self.assertEqual(records[1]["Symbol"], "AAPL")
            self.assertEqual(records[1]["Trade Date"], "2026-07-31")
            self.assertEqual(records[1]["Quantity"], "32")
            # 9479.600096 / 32 = 296.237503 -> "296.2375"
            self.assertEqual(records[1]["Purchase Price"], "296.2375")
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    def test_parse_trade_summary(self):
        """Test parsing Trade Summary section when requested."""
        csv_content = (
            'Trade Summary,Header,Financial Instrument,Currency,Symbol,Description,Sector,Quantity Bought,Average Price Bought,Proceeds Bought,Proceeds Bought in Base,Quantity Sold,Average Price Sold,Proceeds Sold,Proceeds Sold in Base\n'
            'Trade Summary,Data,Stocks,United States Dollar,AMZN,AMAZON.COM INC,Consumer Cyclicals,81,266.512592593,-21587.52,-29712.035228,0,0,0,0\n'
        )

        with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".csv") as tmp:
            tmp.write(csv_content)
            tmp_path = tmp.name

        try:
            records = parse_ibkr_csv(tmp_path, source_type="trades")
            self.assertEqual(len(records), 1)
            self.assertEqual(records[0]["Symbol"], "AMZN")
            self.assertEqual(records[0]["Quantity"], "81")
            self.assertEqual(records[0]["Purchase Price"], "266.5126")
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    def test_write_yahoo_csv(self):
        """Test writing dict records to Yahoo portfolio CSV format."""
        records = [
            {"Symbol": "GOOG", "Trade Date": "2018-07-05", "Purchase Price": "281.79", "Quantity": "10"}
        ]

        with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".csv") as tmp:
            tmp_path = tmp.name

        try:
            write_yahoo_csv(records, tmp_path)
            with open(tmp_path, "r", encoding="utf-8") as f:
                content = f.read().splitlines()

            self.assertEqual(content[0], "Symbol,Trade Date,Purchase Price,Quantity")
            self.assertEqual(content[1], "GOOG,2018-07-05,281.79,10")
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    def test_end_to_end_sample_file(self):
        """Test converting actual input file in inputs/ directory if present."""
        sample_input = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "..", "inputs", "ApexArc_Consulting_Corp._Inception_July_31_2026.csv")
        )
        if not os.path.exists(sample_input):
            self.skipTest("Sample input file not found.")

        with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".csv") as tmp:
            tmp_path = tmp.name

        try:
            success = convert_file(sample_input, tmp_path)
            self.assertTrue(success)

            with open(tmp_path, "r", encoding="utf-8") as f:
                reader = csv.reader(f)
                rows = list(reader)

            # Check header
            self.assertEqual(rows[0], ["Symbol", "Trade Date", "Purchase Price", "Quantity"])
            # Check row count (41 open positions + 1 header = 42 rows)
            self.assertEqual(len(rows), 42)

            # Check specific tickers
            symbols = [row[0] for row in rows[1:]]
            self.assertIn("AAPL", symbols)
            self.assertIn("GOOG", symbols)
            self.assertIn("NVDA", symbols)
            self.assertNotIn("CAD", symbols) # Ensure Cash filter worked
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)


if __name__ == "__main__":
    unittest.main()
