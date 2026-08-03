# IBKR to Yahoo Finance CSV Converter

A command-line tool and automated pipeline to convert Interactive Brokers (IBKR) CSV exports (Portfolio Analyst reports, Flex Queries, and Activity Statements) into the standard CSV format required for importing portfolios into Yahoo Finance.

---

## 🔒 Security & Privacy Notice

> [!IMPORTANT]
> Financial data exported from Interactive Brokers contains personal financial records. 
> The project directory contains strict `.gitignore` rules ensuring that **all input CSV files in `inputs/` and all generated CSV files in `outputs/` are ignored by Git**. 
> You can safely place your financial statements in `inputs/` without risking pushing private financial data to public Git repositories.

---

## 📁 Directory Structure

```text
IBKR_to_Yahoo_Finance/
├── inputs/                    # 📥 Drop your exported IBKR CSV files here (git-ignored)
│   └── .gitkeep
├── outputs/                   # 📤 Converted Yahoo Finance CSV files are saved here (git-ignored)
│   └── .gitkeep
├── tests/                     # 🧪 Automated unit test suite
│   └── test_converter.py
├── convert_ibkr_to_yahoo.py   # ⚙️ Python conversion script
├── yahoo_sample-portfolio.csv # 📄 Sample Yahoo Finance CSV import template
├── README.md                  # 📖 Instructions and documentation
└── .gitignore                 # 🔒 Security rules to exclude CSV financial data
```

---

## 🚀 Quick Start

### 1. Requirements
- Python 3.6 or higher (uses built-in standard libraries, no third-party package installation required).

### 2. Export CSV from Interactive Brokers
1. Log into your **Interactive Brokers Client Portal** (or Trader Workstation).
2. Go to **Reports** → **Portfolio Analyst** (or **Flex Queries** / **Activity Statements**).
3. Export your portfolio summary or positions report as a **CSV** file.
4. Drop the exported CSV file into the `inputs/` directory.

### 3. Run the Conversion Script

#### Option A: Batch Convert All Files in `inputs/` (Default)
Simply run the script with no arguments. It will automatically process every `.csv` file in `inputs/` and generate converted files in `outputs/`:

```bash
python3 convert_ibkr_to_yahoo.py
```

#### Option B: Convert a Specific File
Specify custom input and output file paths using `-i` and `-o`:

```bash
python3 convert_ibkr_to_yahoo.py -i inputs/ApexArc_Consulting_Corp._Inception_July_31_2026.csv -o outputs/my_yahoo_portfolio.csv
```

#### Option C: Parse Trade History Instead of Open Positions
By default, the script converts current **Open Positions**. To parse **Trade Summary** history instead, use `--source trades`:

```bash
python3 convert_ibkr_to_yahoo.py -s trades
```

---

## 🛠️ Command-Line Options

| Option | Short | Default | Description |
| :--- | :--- | :--- | :--- |
| `--input` | `-i` | `inputs` | Path to an IBKR CSV file or a folder containing CSV files |
| `--output` | `-o` | `outputs` | Path for the output Yahoo CSV file or destination folder |
| `--source` | `-s` | `positions` | Data section to parse: `positions` (default), `trades`, or `auto` |
| `--verbose` | `-v` | `False` | Enable detailed logging of sections and lines parsed |

---

## 📊 Yahoo Finance CSV Format

Yahoo Finance requires CSV files with the following exact columns:

```csv
Symbol,Trade Date,Purchase Price,Quantity
GOOG,2026-07-31,307.8778,63.3813
AAPL,2026-07-31,296.2375,32
NVDA,2026-07-31,184.1246,205.1395
```

### Key Conversions Applied:
- **Symbol**: Standardized ticker symbols (e.g. clean whitespace, converts class share formatting).
- **Trade Date**: Converted to standard `YYYY-MM-DD` ISO format.
- **Purchase Price**: Automatically calculated as `Cost Basis / Quantity` in local security currency.
- **Quantity**: Preserves precise integer or fractional share counts.
- **Filters**: Automatically removes summary total rows (`Total`), cash holdings (`CAD`, `USD`), and non-tradable currency entries.

---

## 📥 How to Import into Yahoo Finance

1. Navigate to **[Yahoo Finance Portfolios](https://finance.yahoo.com/portfolios)**.
2. Click **Create Portfolio** (or select an existing portfolio).
3. Click **Add Symbols / Import**.
4. Select **Import CSV**.
5. Upload your generated CSV file from the `outputs/` folder (e.g. `outputs/yahoo_portfolio.csv`).

---

## 🧪 Running Tests

A comprehensive unit test suite is included to verify date parsing, ticker cleaning, section mapping, price calculations, and end-to-end file conversions:

```bash
python3 -m unittest discover -s tests
```

---

## 📄 License

MIT License. Feel free to modify and adapt for your workflow.
