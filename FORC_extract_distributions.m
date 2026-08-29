%% FORC_extract_distributions.m
% Extract reversible and irreversible Preisach distributions from measured
% first-order reversal curve (FORC) data.
%
% INPUT WORKBOOK (default settings)
% ---------------------------------
% Excel workbook: .xlsx or .xls
% Worksheet      : first worksheet
% Data start     : row 10
% Column A       : time [s]
% Column B       : voltage across the dielectric/sample [V]
% Column C       : measured charge [C]
%
% Rows 1-9 may contain headers or instrument metadata. Extra columns are
% allowed. The worksheet, first data row, and column numbers are editable
% below, so the analysis logic does not need to be changed for a different
% workbook layout.
%
% REQUIRED DATA CONDITIONS
% ------------------------
% - One measurement sample per row.
% - Time must be numerical and strictly increasing.
% - Voltage and charge must already use the desired sign convention.
% - The retained baseline interval must be recorded before the FORC pulses.
% - The pulse ordering must match the waveform settings below.
% - The final FORC pulse must include its decreasing branch after the peak.
%
% OUTPUTS
% -------
% p_rev(E_rev)       reversible distribution   [uC/(kV*cm)]
% p_irr(E_a,E_b)     irreversible distribution [uC/kV^2]
%
% OUTPUT WORKBOOK SHEETS
% ----------------------
% p_irr       : p_irr matrix with E_b rows and E_a columns
% p_rev       : E_rev and p_rev
% diagnostics : branch-by-branch peak/fitting checks
% metadata    : parameters used for the analysis
%
% MATLAB R2019a or later is recommended. No additional toolbox is required.

clear;

%% ========================= USER PARAMETERS ===========================

% ----- Input workbook layout -----
sheet_name     = 1;    % worksheet number or name, e.g. 1 or 'Sheet1'
first_data_row = 10;   % first row containing numerical measurement data

time_column    = 1;    % Excel column A
voltage_column = 2;    % Excel column B
charge_column  = 3;    % Excel column C

% ----- Sample geometry -----
dielectric_thickness = 10e-6;       % dielectric thickness [m]
area_factor          = 100;   % dimensionless effective-area factor (e.g., number of dielectric layers)
sample_width         = 1e-3;      % active width [m]
sample_length        = 2e-3;      % active length [m]

% Effective electrical area:
%   A_eff = area_factor * sample_width * sample_length
%
% For a single active area equal to width*length, use area_factor = 1.
% For multilayer or other geometries, area_factor must represent the
% effective-area multiplier appropriate to the measured total charge.

% ----- FORC waveform parameters -----
frequency = 100;      % duration of each triangle = 1/frequency [Hz]
E_base    = -100;     % baseline field [kV/cm]
E_max     = 100;      % largest reversal field [kV/cm]
dE_rev    = 2;        % reversal-field increment [kV/cm]

% Expected pulse ordering after the initial baseline interval:
%
% false:
%   E_base -> E_rev(1) -> E_base
%   E_base -> E_rev(2) -> E_base
%   ...
%
% true:
%   E_base -> E_max    -> E_base   (full repoling triangle)
%   E_base -> E_rev(1) -> E_base   (FORC triangle)
%   E_base -> E_max    -> E_base
%   E_base -> E_rev(2) -> E_base
%   ...
%
% where E_rev(k) = E_base + k*dE_rev.
repoling_full_sweep = false;

% ----- Beginning of usable record -----
% Samples at t <= t_use_start are discarded.
% The retained interval
%   t_use_start < t <= t_baseline_end
% must be part of the initial constant-field baseline. It is used for
% drift estimation and baseline-field estimation. FORC peak tracking starts
% after t_baseline_end.
t_use_start    = 0.75;   % [s]
t_baseline_end = 1.00;   % [s]

% ----- Polarization-drift correction -----
% 'auto'   : fit P = a*t + b during the retained baseline and remove a*t
% 'manual' : determine the drift rate from C_drift/t_drift
slope_mode = 'auto';
C_drift    = -0.6849e-7;   % charge change in manual mode [C]
t_drift    = 1.0;          % corresponding time interval [s]

% ----- Local linear fitting -----
min_fit_points = 3;   % minimum raw P-E samples required in one field bin

% ----- Peak tracking -----
peak_search_halfwidth_fraction = 0.10;  % +/- fraction of one period
peak_smoothing_fraction        = 0.01;  % moving-average width / period
peak_threshold_fraction        = 0.40;  % threshold / dE_rev

% ----- End of decreasing-branch detection -----
rise_tolerance_fraction      = 0.05;  % rise above running minimum / dE_rev
sustained_rise_fraction      = 0.02;  % required rising duration / period
monotonic_tolerance_fraction = 0.03;  % small field-jitter tolerance / dE_rev

% ----- Diagnostic plots -----
plot_time_trace = true;
plot_branches   = true;
plot_p_rev      = true;
plot_p_irr      = true;
plot_debug      = false;


%% ========================= PARAMETER CHECKS ==========================

if ~isscalar(first_data_row) || first_data_row < 1 || mod(first_data_row,1) ~= 0
    error('first_data_row must be a positive integer.');
end

input_columns = [time_column, voltage_column, charge_column];
if any(input_columns < 1) || any(mod(input_columns,1) ~= 0) || ...
        numel(unique(input_columns)) ~= 3
    error('time_column, voltage_column, and charge_column must be distinct positive integers.');
end

if dielectric_thickness <= 0
    error('dielectric_thickness must be greater than zero.');
end

if area_factor <= 0 || sample_width <= 0 || sample_length <= 0
    error('area_factor, sample_width, and sample_length must be positive.');
end

if frequency <= 0
    error('frequency must be greater than zero.');
end

if E_max <= E_base
    error('E_max must be greater than E_base.');
end

if dE_rev <= 0
    error('dE_rev must be greater than zero.');
end

N_exact = (E_max - E_base) / dE_rev;
if abs(N_exact - round(N_exact)) > 1e-10
    error('(E_max - E_base) must be an integer multiple of dE_rev.');
end
N_forc = round(N_exact);

if N_forc < 2
    error('At least two reversal fields are required to calculate p_irr.');
end

if t_use_start < 0 || t_baseline_end <= t_use_start
    error('Require 0 <= t_use_start < t_baseline_end.');
end

if min_fit_points < 2 || mod(min_fit_points,1) ~= 0
    error('min_fit_points must be an integer >= 2.');
end

if ~any(strcmpi(strtrim(slope_mode), {'auto','manual'}))
    error('slope_mode must be ''auto'' or ''manual''.');
end

if peak_search_halfwidth_fraction <= 0 || peak_search_halfwidth_fraction >= 0.5
    error('peak_search_halfwidth_fraction must be between 0 and 0.5.');
end

if peak_smoothing_fraction <= 0 || peak_threshold_fraction <= 0
    error('Peak smoothing and threshold fractions must be greater than zero.');
end

if rise_tolerance_fraction < 0 || sustained_rise_fraction <= 0 || ...
        monotonic_tolerance_fraction < 0
    error('Branch-detection fractions are invalid.');
end

if ~(isscalar(repoling_full_sweep) && ...
        (islogical(repoling_full_sweep) || ismember(repoling_full_sweep,[0 1])))
    error('repoling_full_sweep must be true or false.');
end


%% ========================= LOAD EXCEL DATA ===========================

[filename, pathname] = uigetfile( ...
    {'*.xlsx;*.xls', 'Excel workbooks (*.xlsx, *.xls)'}, ...
    'Select FORC measurement workbook');

if isequal(filename,0)
    error('No input workbook was selected.');
end

input_file = fullfile(pathname, filename);
raw_all = readmatrix(input_file, 'Sheet', sheet_name);

if size(raw_all,1) < first_data_row
    error('The worksheet has fewer than first_data_row = %d rows.', first_data_row);
end

if size(raw_all,2) < max(input_columns)
    error(['The worksheet has %d columns, but column %d is required by ', ...
           'the input-column settings.'], size(raw_all,2), max(input_columns));
end

raw = raw_all(first_data_row:end, input_columns);

% A row without numerical time cannot represent a measurement sample.
raw = raw(isfinite(raw(:,1)), :);

if size(raw,1) < 3
    error('The worksheet does not contain enough numerical measurement rows.');
end

t_raw = raw(:,1);     % [s]
V_raw = raw(:,2);     % [V]
C_raw = raw(:,3);     % [C]


%% ========================= UNIT CONVERSION ===========================

% Electric field:
%   E [kV/cm] = (V [V] / thickness [m]) / 1e5
E_raw = (V_raw ./ dielectric_thickness) / 1e5;

% Effective electrical area [m^2].
A_eff = area_factor * sample_width * sample_length;

% Polarization:
%   P [uC/cm^2] = Q [C] / A_eff [m^2] * 100
P_raw = (C_raw ./ A_eff) * 100;


%% ========================= TRUNCATE / VALIDATE DATA ==================

idx_start = find(t_raw > t_use_start, 1, 'first');
if isempty(idx_start)
    error('No data exist after t_use_start = %.6g s.', t_use_start);
end

t = t_raw(idx_start:end);
E = E_raw(idx_start:end);
P = P_raw(idx_start:end);

valid = isfinite(t) & isfinite(E) & isfinite(P);
num_removed = nnz(~valid);
t = t(valid);
E = E(valid);
P = P(valid);

if num_removed > 0
    warning('%d retained-time rows with nonfinite time/voltage/charge were removed.', num_removed);
end

if numel(t) < 3
    error('Not enough valid samples remain after truncation and cleaning.');
end

if any(diff(t) <= 0)
    error('Time values must be strictly increasing after truncation.');
end

dt_all = diff(t);
dt = median(dt_all);

if ~isfinite(dt) || dt <= 0
    error('Could not determine a valid measurement sampling interval.');
end

if max(dt_all) > 5*dt
    warning(['A time gap larger than five times the median sampling interval was detected. ', ...
             'Missing samples may affect peak tracking or fitting.']);
end


%% ========================= REMOVE LINEAR P(t) DRIFT ==================

% Retained part of the initial constant-field baseline.
mask_baseline = t <= t_baseline_end;

if nnz(mask_baseline) < 2
    error(['At least two valid samples are required in ', ...
           '(t_use_start, t_baseline_end].']);
end

switch lower(strtrim(slope_mode))
    case 'auto'
        drift_fit = polyfit(t(mask_baseline), P(mask_baseline), 1);
        dPdt = drift_fit(1);   % [uC/(cm^2*s)]

    case 'manual'
        if ~isfinite(C_drift) || ~isfinite(t_drift) || t_drift <= 0
            error('Manual mode requires finite C_drift and t_drift > 0.');
        end
        dPdt = ((C_drift / t_drift) / A_eff) * 100;
end

% Preserve the polarization value at the first retained sample while
% removing the fitted linear slope.
P = P - dPdt .* (t - t(1));

% Measured baseline used only for peak detection. The nominal E_base still
% defines the Preisach field grid.
E_background = mean(E(mask_baseline));

if abs(E_background - E_base) > 2*dE_rev
    warning(['Measured baseline field (%.6g kV/cm) differs from E_base ', ...
             '(%.6g kV/cm) by more than 2*dE_rev. Check voltage scaling, ', ...
             'dielectric thickness, timing, and E_base.'], ...
             E_background, E_base);
end


%% ========================= TIME-TRACE PLOT ===========================

if plot_time_trace
    P_range = max(P) - min(P);
    E_range = max(E) - min(E);
    if ~isfinite(P_range) || P_range <= 0, P_range = 1; end
    if ~isfinite(E_range) || E_range <= 0, E_range = 1; end

    P_norm = (P - min(P)) / P_range;
    E_norm = (E - min(E)) / E_range;

    figure('Name','Normalized measured signals','Color','w');
    plot(t, E_norm, 'LineWidth', 1.1); hold on;
    plot(t, P_norm, 'LineWidth', 1.1);
    xline(t_baseline_end, '--', 'FORC sequence begins');
    grid on; box on;
    xlabel('Time (s)');
    ylabel('Normalized amplitude');
    legend('E', 'P after drift correction', 'Location','best');
    title('Measured FORC signals');
end


%% ========================= TRACK TRIANGLE PEAKS ======================

T = 1 / frequency;
samples_per_period = T / dt;

if samples_per_period < 10
    warning(['Only %.2f measured samples per waveform period were found. ', ...
             'Derivative fitting may be poorly resolved.'], samples_per_period);
end

E_relative = E - E_background;
smooth_points = max(3, round(peak_smoothing_fraction * T / dt));
smooth_points = min(smooth_points, numel(E));
E_detect = movmean(E_relative, smooth_points);

peak_threshold = dE_rev * peak_threshold_fraction;
idx_after_baseline = find(t > t_baseline_end, 1, 'first');
if isempty(idx_after_baseline)
    error('No data exist after t_baseline_end = %.6g s.', t_baseline_end);
end

% Local maxima without findpeaks (no Signal Processing Toolbox required).
local_peak = false(size(E_detect));
local_peak(2:end-1) = ...
    E_detect(2:end-1) >= E_detect(1:end-2) & ...
    E_detect(2:end-1) >  E_detect(3:end);

candidate_peaks = find(local_peak & (E_detect >= peak_threshold));
candidate_peaks = candidate_peaks(candidate_peaks >= idx_after_baseline);

if isempty(candidate_peaks)
    error(['No waveform peak was detected after t_baseline_end. Check ', ...
           'frequency, dE_rev, timing, voltage scaling, and peak settings.']);
end

search_halfwidth = peak_search_halfwidth_fraction * T;

% Refine the first detected peak to the raw-E maximum in its local window.
first_seed = candidate_peaks(1);
j0 = find(t >= t(first_seed) - search_halfwidth, 1, 'first');
j1 = find(t <= t(first_seed) + search_halfwidth, 1, 'last');
if isempty(j0), j0 = first_seed; end
if isempty(j1), j1 = first_seed; end
[~, rel_raw] = max(E(j0:j1));
first_peak = j0 + rel_raw - 1;

% Search every expected pulse slot independently. This prevents one missing
% pulse from silently shifting the indexing of all later FORC branches.
if repoling_full_sweep
    required_detected = 2*N_forc;
else
    required_detected = N_forc;
end

all_peaks = nan(required_detected,1);
all_peaks(1) = first_peak;

for pulse_number = 2:required_detected
    t_expected = t(first_peak) + (pulse_number-1)*T;

    if t_expected > t(end)
        error(['The measurement ends before expected triangle %d of %d. ', ...
               'The complete FORC sequence was not recorded.'], ...
               pulse_number, required_detected);
    end

    j0 = find(t >= t_expected - search_halfwidth, 1, 'first');
    j1 = find(t <= t_expected + search_halfwidth, 1, 'last');

    if isempty(j0) || isempty(j1) || j1 <= j0
        error('No usable search window exists for expected triangle %d.', pulse_number);
    end

    peak_value = max(E_detect(j0:j1));
    if peak_value < peak_threshold
        error(['Expected triangle %d of %d was not detected near t = %.6g s. ', ...
               'Check frequency, waveform ordering, threshold, and data completeness.'], ...
               pulse_number, required_detected, t_expected);
    end

    [~, rel_raw] = max(E(j0:j1));
    all_peaks(pulse_number) = j0 + rel_raw - 1;
end

if repoling_full_sweep
    forc_peaks = all_peaks(2:2:end);
else
    forc_peaks = all_peaks;
end
forc_peaks = forc_peaks(:);


%% ========================= EXTRACT DECREASING BRANCHES ===============

branch_E = cell(N_forc,1);
branch_P = cell(N_forc,1);
branch_sample_count = zeros(N_forc,1);

E_smooth = movmean(E, smooth_points);
sustain_points = max(2, round(sustained_rise_fraction * T / dt));
rise_tolerance = max(1e-9, rise_tolerance_fraction * dE_rev);
monotonic_tolerance = monotonic_tolerance_fraction * dE_rev;

nominal_peak_field  = E_base + (1:N_forc).' * dE_rev;
measured_peak_field = nan(N_forc,1);

for w = 1:N_forc
    peak_idx = forc_peaks(w);
    measured_peak_field(w) = E(peak_idx);

    % A decreasing branch should occupy approximately half a triangle.
    end_limit = find(t <= t(peak_idx) + 0.5*T, 1, 'last');
    if isempty(end_limit), end_limit = numel(t); end

    if end_limit <= peak_idx + 1
        error('Insufficient data after FORC peak %d.', w);
    end

    running_min = E_smooth(peak_idx);
    rise_count = 0;
    branch_end = peak_idx;

    for k = peak_idx+1:end_limit
        if E_smooth(k) <= running_min
            running_min = E_smooth(k);
            rise_count = 0;
        else
            is_rising = E_smooth(k) > E_smooth(k-1) + monotonic_tolerance;
            above_min = E_smooth(k) >= running_min + rise_tolerance;

            if is_rising && above_min
                rise_count = rise_count + 1;
            else
                rise_count = 0;
            end
        end

        if rise_count >= sustain_points
            branch_end = k - rise_count;
            break;
        else
            branch_end = k;
        end
    end

    if branch_end <= peak_idx
        error('Could not extract a decreasing branch for FORC pulse %d.', w);
    end

    E_segment = E(peak_idx:branch_end);
    P_segment = P(peak_idx:branch_end);
    valid = isfinite(E_segment) & isfinite(P_segment);
    E_segment = E_segment(valid);
    P_segment = P_segment(valid);

    if numel(E_segment) < min_fit_points
        error('FORC branch %d contains too few valid samples.', w);
    end

    branch_E{w} = E_segment(:);
    branch_P{w} = P_segment(:);
    branch_sample_count(w) = numel(E_segment);
end

peak_field_error = measured_peak_field - nominal_peak_field;
if any(abs(peak_field_error) > dE_rev)
    warning(['At least one measured reversal peak differs from its nominal ', ...
             'field by more than dE_rev. Check pulse correspondence and ', ...
             'electric-field conversion.']);
end


%% ========================= BRANCH / DEBUG PLOTS ======================

if plot_branches
    figure('Name','Extracted FORC branches','Color','w');
    hold on;
    for w = 1:N_forc
        plot(branch_E{w}, branch_P{w}, 'LineWidth', 0.8);
    end
    grid on; box on;
    xlabel('E (kV/cm)');
    ylabel('P (\muC/cm^2)');
    title('Extracted decreasing FORC branches');
end

if plot_debug
    figure('Name','FORC peak detection','Color','w');
    plot(t, E, 'LineWidth', 0.9); hold on;
    plot(t(all_peaks), E(all_peaks), 'o', 'MarkerSize', 4);
    plot(t(forc_peaks), E(forc_peaks), 'x', 'MarkerSize', 7, 'LineWidth', 1.2);
    grid on; box on;
    xlabel('Time (s)');
    ylabel('E (kV/cm)');
    legend('Measured E', 'Expected triangle peaks', 'Selected FORC peaks', ...
        'Location','best');
    title('Detected waveform peaks');
end


%% ========================= FIT dP/dE_b ===============================

% dP_dEb(q,w) is the fitted slope in field bin q of FORC branch w.
% Only q <= w is populated. Every raw P-E sample inside a bin is fitted to
%
%   P = m*E + b,
%
% and m is used as dP/dE_b. A bin remains NaN if it has fewer than
% min_fit_points usable samples.

dP_dEb = nan(N_forc, N_forc);
min_field_span = 1e-9 * max(dE_rev,1);

for w = 1:N_forc
    E_branch = branch_E{w};
    P_branch = branch_P{w};

    if w == 1
        edges = [min(E_branch); max(E_branch)];
    else
        interior_edges = (E_base + (1:w-1)*dE_rev).';
        edges = sort([min(E_branch); interior_edges; max(E_branch)], 'ascend');
    end

    if numel(edges) ~= w + 1
        error('Unexpected number of field-bin edges for FORC branch %d.', w);
    end

    for q = 1:w
        E_lo = edges(q);
        E_hi = edges(q+1);

        if ~isfinite(E_lo) || ~isfinite(E_hi) || (E_hi-E_lo) < min_field_span
            continue;
        end

        % Half-open bins avoid double-counting samples exactly on an
        % interior boundary. The final bin includes its upper edge.
        if q < w
            in_bin = E_branch >= E_lo & E_branch < E_hi;
        else
            in_bin = E_branch >= E_lo & E_branch <= E_hi;
        end

        E_fit = E_branch(in_bin);
        P_fit = P_branch(in_bin);

        if numel(E_fit) < min_fit_points
            continue;
        end

        if (max(E_fit)-min(E_fit)) < min_field_span
            continue;
        end

        coeff = polyfit(E_fit, P_fit, 1);
        dP_dEb(q,w) = coeff(1);
    end
end

fit_bin_count = sum(isfinite(dP_dEb), 1).';


%% ========================= CALCULATE p_rev ===========================

% p_rev(E_rev) = 0.5 * dP/dE_b on the diagonal.
%
% Units:
%   (uC/cm^2)/(kV/cm) = uC/(kV*cm)

E_rev = E_base + ((0:N_forc-1).' + 0.5) * dE_rev;
p_rev = 0.5 * diag(dP_dEb);


%% ========================= CALCULATE p_irr ===========================

% p_irr(E_a,E_b) = 0.5 * d/dE_a(dP/dE_b)
% using a forward finite difference between neighboring FORC branches.

d2P = (dP_dEb(:,2:end) - dP_dEb(:,1:end-1)) / dE_rev;
p_irr_full = 0.5 * d2P;

p_irr = p_irr_full(1:end-1,:);
E_b = E_rev(1:end-1);
E_a = E_base + ((1:N_forc-1).' + 0.5) * dE_rev;


%% ========================= PLOT DISTRIBUTIONS ========================

if plot_p_rev
    figure('Name','Reversible distribution','Color','w');
    plot(E_rev, p_rev, '-o', 'LineWidth', 1.4, 'MarkerSize', 4);
    grid on; box on;
    xlabel('E_{rev} (kV/cm)');
    ylabel('p_{rev} (\muC/(kV\cdotcm))');
    title('Reversible Preisach distribution');
end

if plot_p_irr
    figure('Name','Irreversible distribution','Color','w');
    imagesc(E_a, E_b, p_irr);
    set(gca, 'YDir', 'normal');
    axis tight;
    colormap(parula);
    colorbar;
    xlabel('E_a (kV/cm)');
    ylabel('E_b (kV/cm)');
    title('Irreversible Preisach distribution, p_{irr} (\muC/kV^2)');
end


%% ========================= SAVE RESULTS ==============================

[output_name, output_path] = uiputfile( ...
    {'*.xlsx', 'Excel Workbook (*.xlsx)'}, ...
    'Save FORC distributions as');

if isequal(output_name,0)
    fprintf('Result export canceled by user.\n');
else
    [~,~,output_ext] = fileparts(output_name);
    if isempty(output_ext)
        output_name = [output_name '.xlsx'];
    elseif ~strcmpi(output_ext, '.xlsx')
        error('Output file must use the .xlsx extension.');
    end

    output_file = fullfile(output_path, output_name);

    % Remove an existing workbook first so cells from an older, larger
    % result cannot remain outside the new written ranges.
    if isfile(output_file)
        delete(output_file);
    end

    % ----- p_irr sheet -----
    p_irr_header = [{'E_b / E_a (kV/cm)'}, num2cell(E_a(:).')];
    p_irr_body   = [num2cell(E_b(:)), num2cell(p_irr)];
    writecell([p_irr_header; p_irr_body], ...
        output_file, 'Sheet', 'p_irr', 'Range', 'A1');

    % ----- p_rev sheet -----
    p_rev_sheet = [ ...
        {'E_rev (kV/cm)', 'p_rev (uC/(kV*cm))'}; ...
        num2cell([E_rev(:), p_rev(:)]) ...
        ];
    writecell(p_rev_sheet, output_file, 'Sheet', 'p_rev', 'Range', 'A1');

    % ----- diagnostics sheet -----
    diagnostics_sheet = [ ...
        {'Branch', 'Nominal reversal E (kV/cm)', 'Measured peak E (kV/cm)', ...
         'Peak error (kV/cm)', 'Extracted samples', 'Successful fitted bins'}; ...
        num2cell([(1:N_forc).', nominal_peak_field, measured_peak_field, ...
                  peak_field_error, branch_sample_count, fit_bin_count]) ...
        ];
    writecell(diagnostics_sheet, output_file, 'Sheet', 'diagnostics', 'Range', 'A1');

    % ----- metadata sheet -----
    metadata = {
        'Source filename', filename;
        'Source worksheet', string(sheet_name);
        'First data row', first_data_row;
        'Time column', time_column;
        'Voltage column', voltage_column;
        'Charge column', charge_column;
        'Description', 'FORC-derived reversible and irreversible Preisach distributions';
        'E units', 'kV/cm';
        'P units', 'uC/cm^2';
        'p_rev units', 'uC/(kV*cm)';
        'p_irr units', 'uC/kV^2';
        'frequency (Hz)', frequency;
        'E_base (kV/cm)', E_base;
        'E_max (kV/cm)', E_max;
        'dE_rev (kV/cm)', dE_rev;
        'Number of FORC branches', N_forc;
        'Full repoling enabled', logical(repoling_full_sweep);
        't_use_start (s)', t_use_start;
        't_baseline_end (s)', t_baseline_end;
        'slope_mode', slope_mode;
        'removed dP/dt (uC/(cm^2*s))', dPdt;
        'measured baseline E (kV/cm)', E_background;
        'median sample interval (s)', dt;
        'measured samples per period', samples_per_period;
        'dielectric_thickness (m)', dielectric_thickness;
        'area_factor', area_factor;
        'sample_width (m)', sample_width;
        'sample_length (m)', sample_length;
        'effective_area (m^2)', A_eff;
        'min_fit_points', min_fit_points;
        };
    writecell(metadata, output_file, 'Sheet', 'metadata', 'Range', 'A1');

    fprintf('Results saved to:\n%s\n', output_file);
end


%% ========================= CONSOLE SUMMARY ===========================

fprintf('\n================ FORC ANALYSIS SUMMARY ================\n');
fprintf('Input file                  : %s\n', filename);
fprintf('Worksheet                   : %s\n', string(sheet_name));
fprintf('Number of FORC branches     : %d\n', N_forc);
fprintf('Expected triangle peaks     : %d\n', numel(all_peaks));
fprintf('FORC peaks analyzed         : %d\n', numel(forc_peaks));
fprintf('Nominal field range         : %.6g to %.6g kV/cm\n', E_base, E_max);
fprintf('Reversal-field increment    : %.6g kV/cm\n', dE_rev);
fprintf('Measured baseline field     : %.6g kV/cm\n', E_background);
fprintf('Median sampling interval    : %.6g s\n', dt);
fprintf('Measured samples per period : %.3f\n', samples_per_period);
fprintf('Max reversal-field error    : %.6g kV/cm\n', max(abs(peak_field_error)));
fprintf('Removed P drift             : %.6g uC/(cm^2*s)\n', dPdt);
fprintf('Finite p_rev values         : %d / %d\n', nnz(isfinite(p_rev)), numel(p_rev));
fprintf('Finite p_irr values         : %d / %d\n', nnz(isfinite(p_irr)), numel(p_irr));
fprintf('=======================================================\n');
