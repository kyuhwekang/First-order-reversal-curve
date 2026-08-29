# FORC Analysis

MATLAB code for extracting reversible and irreversible Preisach distributions from measured first-order reversal curve (FORC) data.

## Input data

The input file should be an Excel or CSV file containing:

- Column 1: time (s)
- Column 2: voltage (V)
- Column 3: charge (C)

By default, numerical data are read starting from row 10. The corresponding settings can be changed at the beginning of the MATLAB file.

Before running the code, enter the sample dimensions and FORC measurement parameters, including the waveform frequency, baseline field, maximum field, and reversal-field increment.

## Output

The code calculates:

- Reversible distribution, $p_{\mathrm{rev}}$
- Irreversible distribution, $p_{\mathrm{irr}}$

The results are saved in an Excel workbook together with the corresponding electric-field coordinates and basic analysis information.

## Requirements

- MATLAB

## Usage

1. Open `FORC_extract_distributions.m`.
2. Edit the parameters at the beginning of the file.
3. Run the script.
4. Select the measured FORC data file.
5. Select a location to save the analyzed results.