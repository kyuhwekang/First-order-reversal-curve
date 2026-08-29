# FORC Preisach Distribution Analysis

`FORC_extract_distributions.m` is a MATLAB script for extracting reversible and irreversible Preisach distributions from measured first-order reversal curve (FORC) data.

The repository intentionally contains only the analysis script. Waveform generation and instrument control are not included because those procedures depend on the waveform generator, amplifier, digitizer, and experimental configuration used in each laboratory.

## Outputs

The script calculates

- the reversible distribution $p_{\mathrm{rev}}(E_{\mathrm{rev}})$, and
- the irreversible distribution $p_{\mathrm{irr}}(E_a,E_b)$.

The results are exported to an Excel workbook together with the analysis parameters used for that run.

## Requirements

- MATLAB R2019a or later is recommended.
- No additional MATLAB toolbox is required.
- The input measurement must be stored in an Excel workbook (`.xlsx` or `.xls`).

The script uses base MATLAB functions including `readmatrix`, `writecell`, `polyfit`, `movmean`, and standard plotting functions.

# 1. Required input workbook format

By default, the script reads the **first worksheet** of the selected Excel workbook and assumes that numerical measurement data begin on **row 10**.

The default column assignment is:

| Excel column | Quantity | Required unit |
|---|---|---|
| A | Time | s |
| B | Voltage across the dielectric/sample | V |
| C | Measured charge | C |

Therefore, the numerical portion of the worksheet should have the form

```text
              A                 B                 C
         Time (s)         Voltage (V)        Charge (C)
Row 10   0.750001          -91.20            -1.23e-7
Row 11   0.750002          -91.20            -1.22e-7
Row 12   0.750003          -91.20            -1.22e-7
   ...      ...               ...                ...
```

Rows 1 through 9 are ignored by default and may contain instrument headers, labels, comments, or other metadata. Column headings are not required because the script uses column positions rather than text labels.

Extra worksheet columns are allowed and are ignored unless the input-column settings are changed.

The worksheet layout can be changed without modifying the analysis itself by editing

```matlab
sheet_name     = 1;
first_data_row = 10;

time_column    = 1;
voltage_column = 2;
charge_column  = 3;
```

For example, `voltage_column = 4` instructs the script to read voltage from Excel column D.

## Input-data requirements

Each measurement sample must occupy one worksheet row. In addition:

1. Time must be numerical and strictly increasing.
2. Time must be given in seconds.
3. Voltage must be the voltage corresponding to the dielectric/sample and must be given in volts.
4. Charge must be given in coulombs.
5. Voltage and charge must already use the desired sign convention. The script does not automatically reverse either signal.
6. The data must contain the initial constant-field baseline interval used for drift correction and peak referencing.
7. The data must contain the complete FORC pulse sequence expected from the waveform parameters specified in the script.
8. The final FORC pulse must include its decreasing branch after the reversal point. A file ending at the final peak cannot provide the complete final branch.
9. Large gaps or missing samples should be avoided. The script warns when a time gap exceeds five times the median sampling interval.

Rows containing nonfinite time, voltage, or charge values in the retained measurement interval are removed. A warning reports how many such rows were removed.

# 2. Sample geometry and unit conversion

The user specifies

```matlab
dielectric_thickness
area_factor
sample_width
sample_length
```

in SI units.

The effective electrical area is

$$
A_{\mathrm{eff}}
=
F_A w l,
$$

where $F_A$ is `area_factor`, $w$ is `sample_width`, and $l$ is `sample_length`.

For a single active area equal to $w l$, use

```matlab
area_factor = 1;
```

For multilayer devices or other electrode geometries, `area_factor` should represent the appropriate multiplier that converts the physical width and length into the effective area associated with the measured total charge.

The measured voltage is converted to electric field according to

$$
E\;(\mathrm{kV/cm})
=
\frac{V}{t_D}\frac{1}{10^5},
$$

where $t_D$ is the dielectric thickness in meters.

The measured charge is converted to polarization according to

$$
P\;(\mu\mathrm{C/cm^2})
=
\frac{Q}{A_{\mathrm{eff}}}\times100,
$$

because

$$
1\;\mathrm{C/m^2}=100\;\mu\mathrm{C/cm^2}.
$$

The accuracy of the extracted distributions therefore depends directly on the correctness of the dielectric thickness and effective-area definition.

# 3. Required FORC waveform sequence

The analysis does not require a particular waveform-generator brand or source-file format. It does, however, require the measured electric-field sequence to follow the FORC ordering described below.

The waveform is defined in the script by

```matlab
frequency = 100;
E_base    = -100;
E_max     = 100;
dE_rev    = 2;
```

where all electric fields are in kV/cm.

The number of FORC reversal branches is determined automatically from

$$
N_{\mathrm{FORC}}
=
\frac{E_{\max}-E_{\mathrm{base}}}
{\Delta E_{\mathrm{rev}}}.
$$

The quantity $(E_{\max}-E_{\mathrm{base}})/\Delta E_{\mathrm{rev}}$ must therefore be an integer.

The nominal reversal field of branch $k$ is

$$
E_{\mathrm{rev},k}
=
E_{\mathrm{base}}
+k\Delta E_{\mathrm{rev}},
\qquad
k=1,2,\ldots,N_{\mathrm{FORC}}.
$$

For example, with

$$
E_{\mathrm{base}}=-100\;\mathrm{kV/cm},
\quad
E_{\max}=100\;\mathrm{kV/cm},
\quad
\Delta E_{\mathrm{rev}}=2\;\mathrm{kV/cm},
$$

the expected reversal peaks are

$$
-98,-96,-94,\ldots,98,100\;\mathrm{kV/cm}.
$$

Each triangular waveform must have a duration of

$$
T=\frac{1}{f},
$$

where $f$ is `frequency`.

## Without a full repoling sweep

Set

```matlab
repoling_full_sweep = false;
```

The measured sequence after the initial baseline interval must be

```text
E_base -> E_rev,1 -> E_base
E_base -> E_rev,2 -> E_base
E_base -> E_rev,3 -> E_base
...
E_base -> E_max   -> E_base
```

The script interprets every detected triangle as one FORC branch.

## With a full repoling sweep before every FORC branch

Set

```matlab
repoling_full_sweep = true;
```

The measured sequence must alternate between a full sweep and a FORC sweep:

```text
E_base -> E_max   -> E_base     full repoling sweep
E_base -> E_rev,1 -> E_base     FORC branch 1

E_base -> E_max   -> E_base     full repoling sweep
E_base -> E_rev,2 -> E_base     FORC branch 2

...
```

The script then uses the even-numbered detected triangles as the FORC branches.

If the actual experimental waveform has a different pulse ordering, the peak-selection section of the script must be adapted before the calculated distributions can be interpreted correctly.

# 4. Baseline interval and data truncation

Two timing parameters control the beginning of the analysis:

```matlab
t_use_start    = 0.75;
t_baseline_end = 1.00;
```

Samples satisfying

$$
t\leq t_{\mathrm{use,start}}
$$

are discarded.

The retained interval

$$
t_{\mathrm{use,start}} < t \leq t_{\mathrm{baseline,end}}
$$

must correspond to the initial constant-field baseline before the FORC pulse sequence begins.

This interval serves two purposes:

1. estimation of the linear polarization drift, and
2. estimation of the measured baseline electric field used for pulse detection.

Consequently, `t_baseline_end` should be set at or immediately before the beginning of the first waveform triangle. It should not lie inside the FORC pulse sequence.

The script compares the measured mean field in this interval with `E_base` and issues a warning if they differ by more than $2\Delta E_{\mathrm{rev}}$.

# 5. Polarization-drift correction

Slow linear drift in the measured polarization can be removed before calculating field derivatives.

## Automatic mode

```matlab
slope_mode = 'auto';
```

The retained baseline data are fitted to

$$
P(t)=at+b.
$$

The slope $a=dP/dt$ is then removed:

$$
P_{\mathrm{corrected}}(t)
=
P(t)-a[t-t_0],
$$

where $t_0$ is the first retained time value. Referencing the correction to $t_0$ removes the slope without arbitrarily changing the polarization value at the beginning of the retained record.

## Manual mode

```matlab
slope_mode = 'manual';
```

The user supplies a measured charge drift `C_drift` over a time interval `t_drift`. The script converts this charge-rate correction to polarization rate using the same effective area used for the measured polarization.

# 6. Peak detection and branch extraction

After `t_baseline_end`, the script detects the first waveform peak and then searches each expected triangle slot at the known period $T=1/f$. If a required pulse is missing, the analysis stops with an error rather than shifting all subsequent FORC indices.

A moving average is used only for robust peak and branch-end detection. The selected reversal point itself is refined to the maximum of the **raw measured electric field** within the search window.

For each selected FORC peak, the script extracts the following decreasing-field portion of the waveform. The search is limited to approximately half of one waveform period so that it does not continue into the next rising branch.

The script also compares the detected reversal fields with their nominal values. A warning is issued if a detected reversal peak differs from its expected field by more than `dE_rev`.

The optional plots

```matlab
plot_time_trace = true;
plot_branches   = true;
plot_debug      = false;
```

are useful for confirming that the pulse sequence and decreasing branches have been identified correctly before the resulting distributions are used quantitatively.

# 7. Calculation of the reversible distribution

Each decreasing FORC branch is divided into field intervals separated by $\Delta E_{\mathrm{rev}}$.

Within each interval, **all measured $P$-$E$ samples** are included in a linear least-squares fit

$$
P=mE+b.
$$

The fitted slope is used as

$$
m
=
\frac{\partial P}{\partial E_b}.
$$

A field interval is left as `NaN` if it contains fewer than `min_fit_points` valid samples. The script does not extrapolate a slope from insufficient data.

The reversible Preisach distribution is calculated from the diagonal terms:

$$
p_{\mathrm{rev}}(E_{\mathrm{rev}})
=
\frac{1}{2}
\left.
\frac{\partial P}{\partial E_b}
\right|_{E_a\approx E_b}.
$$

Because

$$
\frac{\mu\mathrm{C/cm^2}}
{\mathrm{kV/cm}}
=
\frac{\mu\mathrm{C}}
{\mathrm{kV}\cdot\mathrm{cm}},
$$

the units of $p_{\mathrm{rev}}$ are

$$
\mu\mathrm{C/(kV\cdot cm)}.
$$

# 8. Calculation of the irreversible distribution

The irreversible Preisach distribution is calculated as

$$
p_{\mathrm{irr}}(E_a,E_b)
=
\frac{1}{2}
\frac{\partial}{\partial E_a}
\left(
\frac{\partial P}{\partial E_b}
\right).
$$

The derivative with respect to $E_a$ is evaluated using the difference between neighboring FORC branches:

$$
\frac{\partial}{\partial E_a}
\left(
\frac{\partial P}{\partial E_b}
\right)
\approx
\frac{
\left(\partial P/\partial E_b\right)_{j+1}
-
\left(\partial P/\partial E_b\right)_j
}
{\Delta E_{\mathrm{rev}}}.
$$

Therefore,

$$
p_{\mathrm{irr}}
\approx
\frac{1}{2\Delta E_{\mathrm{rev}}}
\left[
\left(\frac{\partial P}{\partial E_b}\right)_{j+1}
-
\left(\frac{\partial P}{\partial E_b}\right)_j
\right].
$$

The units of $p_{\mathrm{irr}}$ are

$$
\mu\mathrm{C/kV^2}.
$$

Cells for which the required linear fits are unavailable remain `NaN`.

# 9. Output workbook

After the calculation, the script asks the user to select an `.xlsx` output filename.

If an existing file is selected and overwrite is confirmed, the old workbook is deleted before the new results are written. This prevents cells from an older, larger result matrix from remaining in the workbook.

The output workbook contains four worksheets.

## `p_irr`

The first row contains the $E_a$ coordinates and the first column contains the $E_b$ coordinates.

```text
E_b / E_a (kV/cm)    E_a1       E_a2       E_a3       ...
E_b1                  p_irr      p_irr      p_irr      ...
E_b2                  p_irr      p_irr      p_irr      ...
E_b3                  p_irr      p_irr      p_irr      ...
...
```

$p_{\mathrm{irr}}$ is reported in $\mu\mathrm{C/kV^2}$.

## `p_rev`

The reversible distribution is saved in two columns:

| Column | Quantity | Unit |
|---|---|---|
| 1 | $E_{\mathrm{rev}}$ | kV/cm |
| 2 | $p_{\mathrm{rev}}$ | $\mu$C/(kV·cm) |


## `diagnostics`

This worksheet provides one row per FORC branch with

- branch number,
- nominal reversal field,
- measured reversal-peak field,
- measured-minus-nominal peak error,
- number of raw samples retained in the decreasing branch, and
- number of field bins for which a valid linear fit was obtained.

This sheet is intended as a compact quality-control record. Large reversal-field errors, unusually short extracted branches, or unexpectedly few successful fitted bins should be investigated before the distributions are interpreted quantitatively.

## `metadata`

The metadata worksheet records the principal information required to reproduce or audit the analysis, including

- source filename and worksheet,
- source row and column assignments,
- sample geometry,
- effective area,
- waveform frequency,
- $E_{\mathrm{base}}$, $E_{\max}$, and $\Delta E_{\mathrm{rev}}$,
- number of FORC branches,
- repoling mode,
- retained baseline interval,
- drift-correction mode and removed $dP/dt$,
- measured baseline field,
- median measurement sampling interval,
- measured samples per waveform period, and
- minimum number of points required for each linear fit.

Only the **source filename**, not the full local computer path, is written to the metadata sheet.

# 10. Recommended workflow

1. Confirm that the Excel workbook follows the required time-voltage-charge format.
2. Enter the worksheet location and sample geometry in `USER PARAMETERS`.
3. Enter the electric-field waveform parameters actually used in the experiment.
4. Set `repoling_full_sweep` to match the measured pulse ordering.
5. Set `t_use_start` and `t_baseline_end` so that the retained baseline interval contains only the initial constant-field portion of the measurement.
6. Run the script and select the measurement workbook.
7. Inspect the normalized time trace and extracted FORC branches.
8. If necessary, enable `plot_debug` to verify peak identification.
9. Check the console summary for warnings, reversal-field error, sampling density, and the number of finite $p_{\mathrm{rev}}$ and $p_{\mathrm{irr}}$ values.
10. Save the result workbook.

# 11. Important assumptions and limitations

The script assumes a uniformly ordered FORC experiment with a known waveform frequency and constant reversal-field increment.

In particular:

- The first analyzed waveform after `t_baseline_end` must correspond to the first expected triangle in the selected repoling mode.
- Reversal fields must advance monotonically from $E_{\mathrm{base}}+\Delta E_{\mathrm{rev}}$ to $E_{\max}$.
- Each triangular waveform must have approximately the period specified by `frequency`.
- The voltage column must represent the field-driving voltage appropriate for the dielectric thickness used in the conversion.
- The effective electrical area must correspond to the charge measured by the experiment.
- The measurement sampling density must be high enough to provide multiple raw $P$-$E$ samples inside each field interval. If many output cells are `NaN`, the sampling density and `min_fit_points` should be checked before changing the fitting procedure.
- Linear fitting within each field interval assumes that the local $P(E)$ response can be represented adequately by a straight line over that interval.
- The analysis does not symmetrize $p_{\mathrm{irr}}$, reconstruct a hysteresis loop, or calculate heat generation. Those are separate post-processing operations and are intentionally excluded from this primary extraction script.

# 12. Repository contents

```text
FORC-analysis/
├── FORC_extract_distributions.m
└── README.md
```

The MATLAB script is self-contained and does not depend on a waveform-generation script in this repository.
