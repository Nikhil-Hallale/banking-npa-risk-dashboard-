-- ==============================================================================
-- Project: RBI Non-Performing Asset (NPA) Trend & Risk Analytics Pipeline
-- Module: Institutional Credit Risk & Macroprudential Analysis Engine
-- Target Audience: Investment Banking, Risk Management, & Corporate Credit Strategy (e.g., JPMC)
-- Database Compatibility: SQLite / Standard ANSI SQL
-- Description: Executes multi-dimensional credit risk assessments on cleaned RBI banking
--              data, evaluating deterioration momentum, concentration risk, and structural skews.
-- ==============================================================================

-- ==============================================================================
-- SECTION 1: CORE ASSET-QUALITY TREND METRICS
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- METRIC 1A: YoY Basis Point Change in NPA Ratios (Granular Bank vs. Segment Level)
-- Risk Objective: Quantify the directional velocity of credit asset decay.
-- Logic: Isolates segment-level series over time to dynamically monitor trend lines.
-- ------------------------------------------------------------------------------
WITH segment_series AS (
    SELECT 
        year, 
        bank_type,
        (SUM(gross_npas) / SUM(gross_advances)) * 100 AS segment_weighted_npa_ratio
    FROM clean_npa
    WHERE gross_npas IS NOT NULL AND gross_advances IS NOT NULL
    GROUP BY year, bank_type
),
segment_lagged AS (
    SELECT 
        *,
        LAG(segment_weighted_npa_ratio) OVER (PARTITION BY bank_type ORDER BY year ASC) AS prev_segment_npa_ratio
    FROM segment_series
)
SELECT 
    c.year, 
    c.bank_type, 
    c.banks,
    ROUND(c.npa_ratio, 2) AS bank_npa_ratio,
    ROUND(c.npa_ratio - LAG(c.npa_ratio) OVER (PARTITION BY c.banks ORDER BY c.year ASC), 2) AS bank_yoy_basis_point_change,
    ROUND(s.segment_weighted_npa_ratio, 2) AS segment_weighted_npa_ratio,
    ROUND(s.segment_weighted_npa_ratio - s.prev_segment_npa_ratio, 2) AS segment_yoy_basis_point_change
FROM clean_npa c
JOIN segment_lagged s ON c.year = s.year AND c.bank_type = s.bank_type
ORDER BY c.year DESC, c.bank_type ASC, c.banks ASC;


-- ------------------------------------------------------------------------------
-- METRIC 1B: Asset-Weighted NPA Ratio vs. Simple Average by Segment & Year
-- Risk Objective: Isolate systemic tracking distortion. Outlines whether credit 
--                 risk is concentrated in mega-cap systemically important banks (D-SIBs)
--                 or isolated within non-systemic tail-end entities.
-- ------------------------------------------------------------------------------
SELECT 
    year,
    bank_type,
    ROUND(AVG(npa_ratio), 2) AS simple_average_npa_ratio,
    ROUND((SUM(gross_npas) / SUM(gross_advances)) * 100, 2) AS asset_weighted_npa_ratio,
    -- Positive variance means asset stress is heavily concentrated within the sector's largest balance sheets
    ROUND(((SUM(gross_npas) / SUM(gross_advances)) * 100) - AVG(npa_ratio), 2) AS variance_skew
FROM clean_npa
WHERE gross_npas IS NOT NULL AND gross_advances IS NOT NULL
GROUP BY year, bank_type
ORDER BY year DESC, bank_type ASC;


-- ------------------------------------------------------------------------------
-- METRIC 1C: Credit Divergence Profile (Asset Scaling Velocity vs. NPA Growth)
-- Risk Objective: Determine if absolute NPA expansion is an operational byproduct 
--                 of loan book scaling or a structural breakdown in underwriting discipline.
-- ------------------------------------------------------------------------------
WITH bank_timeline AS (
    SELECT 
        banks,
        bank_type,
        MIN(year) AS start_year,
        MAX(year) AS end_year,
        (MAX(year) - MIN(year)) AS total_years
    FROM clean_npa
    GROUP BY banks
),
boundary_values AS (
    SELECT 
        c.banks,
        t.bank_type,
        t.total_years,
        MAX(CASE WHEN c.year = t.start_year THEN c.gross_advances END) AS start_advances,
        MAX(CASE WHEN c.year = t.end_year THEN c.gross_advances END) AS end_advances,
        MAX(CASE WHEN c.year = t.start_year THEN c.gross_npas END) AS start_npas,
        MAX(CASE WHEN c.year = t.end_year THEN c.gross_npas END) AS end_npas
    FROM clean_npa c
    JOIN bank_timeline t ON c.banks = t.banks
    GROUP BY c.banks
)
SELECT 
    banks,
    bank_type,
    total_years,
    ROUND(((end_advances - start_advances) / start_advances) * 100, 2) AS total_advances_growth_pct,
    ROUND(((end_npas - start_npas) / start_npas) * 100, 2) AS total_npa_growth_pct,
    -- Divergence Vector > 0 indicates toxic assets are structurally outpacing clean book growth
    ROUND((((end_npas - start_npas) / start_npas)) - (((end_advances - start_advances) / start_advances)), 4) AS credit_risk_divergence_vector
FROM boundary_values
WHERE start_advances > 0 AND start_npas > 0 AND total_years >= 2
ORDER BY credit_risk_divergence_vector DESC;


-- ==============================================================================
-- SECTION 2: SEGMENT COMPARISON & SYSTEMIC CONCENTRATION
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- METRIC 2A: Sector Inter-Bank Dispersion Profile (Median & Structural Spread)
-- Risk Objective: Quantify peer-group distribution characteristics and capture 
--                 the true polarization of credit quality across bank classes.
-- ------------------------------------------------------------------------------
WITH ranked_data AS (
    SELECT 
        year,
        bank_type,
        npa_ratio,
        ROW_NUMBER() OVER (PARTITION BY year, bank_type ORDER BY npa_ratio ASC) AS row_num,
        COUNT(*) OVER (PARTITION BY year, bank_type) AS total_count
    FROM clean_npa
    WHERE npa_ratio IS NOT NULL
)
SELECT 
    year,
    bank_type,
    ROUND(MIN(npa_ratio), 2) AS floor_minimum,
    -- Dynamic mathematical median selection via running window index matching
    ROUND(AVG(CASE WHEN row_num BETWEEN total_count/2.0 AND total_count/2.0 + 1 THEN npa_ratio END), 2) AS median_npa_ratio,
    ROUND(MAX(npa_ratio), 2) AS ceiling_maximum,
    ROUND(MAX(npa_ratio) - MIN(npa_ratio), 2) AS inter_bank_spread
FROM ranked_data
GROUP BY year, bank_type
ORDER BY year DESC, bank_type ASC;


-- ------------------------------------------------------------------------------
-- METRIC 2B: Systemic Risk Top 5 Concentration Dominance Index
-- Risk Objective: Measure sovereign-level risk pooling. Evaluates what percentage 
--                 of the entire banking system's toxic assets is concentrated 
--                 within the top 5 largest risk vectors.
-- ------------------------------------------------------------------------------
WITH annual_system_total AS (
    SELECT 
        year,
        SUM(gross_npas) AS total_system_wide_npas
    FROM clean_npa
    GROUP BY year
),
ranked_individual_npas AS (
    SELECT 
        c.year,
        c.banks,
        c.bank_type,
        c.gross_npas,
        ROW_NUMBER() OVER (PARTITION BY c.year ORDER BY c.gross_npas DESC) AS risk_rank
    FROM clean_npa c
)
SELECT 
    r.year,
    r.risk_rank,
    r.banks,
    r.bank_type,
    ROUND(r.gross_npas, 2) AS gross_npas,
    ROUND((r.gross_npas / t.total_system_wide_npas) * 100, 2) AS individual_share_of_system_npa,
    -- Running total tracking cumulative concentration footprint of topmost critical vectors
    ROUND(SUM(r.gross_npas) OVER (PARTITION BY r.year ORDER BY r.risk_rank ASC) / t.total_system_wide_npas * 100, 2) AS cumulative_top_n_concentration_pct
FROM ranked_individual_npas r
JOIN annual_system_total t ON r.year = t.year
WHERE r.risk_rank <= 5
ORDER BY r.year DESC, r.risk_rank ASC;


-- ==============================================================================
-- SECTION 3: VOLATILITY & AUTOMATED CREDIT RISK FLAGGING
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- METRIC 3A: Asset Quality Instability Profile (Coefficient of Variation - CV)
-- Risk Objective: Identify erratic provisioning cycles. A high CV signifies unhedged 
--                 portfolio structures, volatile exposures, or unpredictable default behavior.
-- Logic: Employs explicit numeric aggregation bounds based on active reporting records.
-- ------------------------------------------------------------------------------
WITH bank_stats AS (
    SELECT 
        banks,
        bank_type,
        COUNT(npa_ratio) AS reporting_years,
        AVG(npa_ratio) AS mean_npa_ratio,
        TOTAL( (npa_ratio - (SELECT AVG(npa_ratio) FROM clean_npa WHERE banks = c.banks)) * 
               (npa_ratio - (SELECT AVG(npa_ratio) FROM clean_npa WHERE banks = c.banks)) 
             ) / COUNT(npa_ratio) AS variance
    FROM clean_npa c
    GROUP BY banks
)
SELECT 
    banks,
    bank_type,
    reporting_years,
    ROUND(mean_npa_ratio, 2) AS historical_mean_npa,
    ROUND(variance, 4) AS npa_variance,
    -- CV formula = Population Standard Deviation / Population Mean
    ROUND((EXP(0.5 * LOG(variance)) / mean_npa_ratio), 4) AS coefficient_of_variation
FROM bank_stats
WHERE reporting_years >= 3 AND mean_npa_ratio > 0
ORDER BY coefficient_of_variation DESC;


-- ------------------------------------------------------------------------------
-- METRIC 3B: Statistical Credit Anomaly Engine via YoY Delta Z-Scores
-- Risk Objective: Operates as an automated institutional surveillance alert. Flags 
--                 idiosyncratic balance-sheet deterioration pacing well outside normal 
--                 historical system-wide standard deviations.
-- ------------------------------------------------------------------------------
WITH yoy_deltas AS (
    SELECT 
        year,
        bank_type,
        banks,
        npa_ratio,
        (npa_ratio - LAG(npa_ratio) OVER (PARTITION BY banks ORDER BY year ASC)) AS npa_ratio_yoy_delta
    FROM clean_npa
),
global_delta_stats AS (
    SELECT 
        AVG(npa_ratio_yoy_delta) AS system_mean_delta,
        TOTAL((npa_ratio_yoy_delta - (SELECT AVG(npa_ratio_yoy_delta) FROM yoy_deltas)) * 
              (npa_ratio_yoy_delta - (SELECT AVG(npa_ratio_yoy_delta) FROM yoy_deltas))) / COUNT(*) AS system_variance_delta
    FROM yoy_deltas
    WHERE npa_ratio_yoy_delta IS NOT NULL
),
scored AS (
    SELECT 
        y.year,
        y.bank_type,
        y.banks,
        ROUND(y.npa_ratio, 2) AS current_npa_ratio,
        ROUND(y.npa_ratio_yoy_delta, 2) AS anomalous_jump_basis_points,
        -- Compares individual variance against global system baseline delta variance via log transformation bounds
        ROUND((y.npa_ratio_yoy_delta - g.system_mean_delta) / EXP(0.5 * LOG(g.system_variance_delta)), 2) AS statistical_z_score
    FROM yoy_deltas y
    CROSS JOIN global_delta_stats g
    WHERE y.npa_ratio_yoy_delta IS NOT NULL
)
SELECT * 
FROM scored
WHERE statistical_z_score >= 1.96 -- Signals structural tail risk outliers (95% confidence interval threshold)
ORDER BY statistical_z_score DESC;
