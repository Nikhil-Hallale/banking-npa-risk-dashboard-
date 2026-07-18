-- ==============================================================================
-- Project: RBI Non-Performing Asset (NPA) Trend & Risk Analytics Pipeline
-- Target Audience: Institutional Risk & Corporate Banking Analytics (e.g., JPMC)
-- Purpose: Extracts, forward-fills, standardizes, and structures granular bank-level 
--          NPA historical metrics from raw regulatory reports.
-- ==============================================================================

DROP TABLE IF EXISTS clean_npa;

CREATE TABLE clean_npa AS
WITH indexed_raw AS (
    -- 1. Create a sequential index using rowid to preserve true document layout order
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY rowid) AS row_idx
    FROM raw_npa
),
year_partitions AS (
    -- 2. Forward-fill the empty years using a window sequence group
    SELECT 
        *,
        SUM(
            CASE WHEN year IS NOT NULL AND year != '' THEN 1 ELSE 0 END
        ) OVER (ORDER BY row_idx) AS year_group
    FROM indexed_raw
),
filled_years AS (
    -- 3. Extract the forward-filled year partition values
    SELECT 
        CAST(MAX(year) OVER (PARTITION BY year_group) AS INTEGER) AS clean_year,
        TRIM(banks) AS raw_banks,
        gross_npas AS raw_npa,
        gross_advances AS raw_advances,
        gross_npas_to_gr AS raw_ratio
    FROM year_partitions
),
standardized_data AS (
    -- 4. Clean formatting, explicit banking-sector mapping, and string standardizations
    SELECT 
        clean_year AS year,
        
        -- Convert names to lowercase for robust conditional mapping
        TRIM(LOWER(raw_banks)) AS banks_lower,
        
        -- Formats bank name to display with a clean capitalized initial letter
        UPPER(SUBSTR(TRIM(raw_banks), 1, 1)) || LOWER(SUBSTR(TRIM(raw_banks), 2)) AS formatted_bank_name,
        
        CASE 
            -- Map Public Sector Banks (including historical pre-merger entities)
            WHEN TRIM(LOWER(raw_banks)) LIKE 'state bank%' OR TRIM(LOWER(raw_banks)) LIKE '%of baroda' 
              OR TRIM(LOWER(raw_banks)) LIKE '%of india%' OR TRIM(LOWER(raw_banks)) LIKE 'canara%' 
              OR TRIM(LOWER(raw_banks)) LIKE 'central bank%' OR TRIM(LOWER(raw_banks)) LIKE 'indian bank%' 
              OR TRIM(LOWER(raw_banks)) LIKE 'punjab%' OR TRIM(LOWER(raw_banks)) LIKE 'uco bank%' 
              OR TRIM(LOWER(raw_banks)) LIKE 'union bank%' OR TRIM(LOWER(raw_banks)) LIKE 'united bank%'
              OR TRIM(LOWER(raw_banks)) LIKE 'corporation bank%' OR TRIM(LOWER(raw_banks)) LIKE 'dena bank%'
              OR TRIM(LOWER(raw_banks)) LIKE 'oriental bank%' OR TRIM(LOWER(raw_banks)) LIKE 'syndicate bank%'
              OR TRIM(LOWER(raw_banks)) LIKE 'vijaya bank%' OR TRIM(LOWER(raw_banks)) LIKE 'allahabad bank%'
              OR TRIM(LOWER(raw_banks)) LIKE 'andhra bank%' OR TRIM(LOWER(raw_banks)) LIKE 'bharatiya mahila%'
            THEN 'PUBLIC SECTOR BANKS'

            -- Map Private Sector Banks
            WHEN TRIM(LOWER(raw_banks)) LIKE '%axis bank%' OR TRIM(LOWER(raw_banks)) LIKE '%bandhan%'
              OR TRIM(LOWER(raw_banks)) LIKE '%city union%' OR TRIM(LOWER(raw_banks)) LIKE '%csb bank%'
              OR TRIM(LOWER(raw_banks)) LIKE '%dcb bank%' OR TRIM(LOWER(raw_banks)) LIKE '%dhanlaxmi%'
              OR TRIM(LOWER(raw_banks)) LIKE '%federal bank%' OR TRIM(LOWER(raw_banks)) LIKE '%hdfc bank%'
              OR TRIM(LOWER(raw_banks)) LIKE '%icici bank%' OR TRIM(LOWER(raw_banks)) LIKE '%idbi bank%'
              OR TRIM(LOWER(raw_banks)) LIKE '%idfc%' OR TRIM(LOWER(raw_banks)) LIKE '%indusind%'
              OR TRIM(LOWER(raw_banks)) LIKE '%jammu%' OR TRIM(LOWER(raw_banks)) LIKE '%karnataka%'
              OR TRIM(LOWER(raw_banks)) LIKE '%karur vysya%' OR TRIM(LOWER(raw_banks)) LIKE '%kotak mahindra%'
              OR TRIM(LOWER(raw_banks)) LIKE '%nainital%' OR TRIM(LOWER(raw_banks)) LIKE '%rbl bank%'
              OR TRIM(LOWER(raw_banks)) LIKE '%south indian%' OR TRIM(LOWER(raw_banks)) LIKE '%tamilnad mercantile%'
              OR TRIM(LOWER(raw_banks)) LIKE '%yes bank%' OR TRIM(LOWER(raw_banks)) LIKE '%lakshmi vilas%'
            THEN 'PRIVATE SECTOR BANKS'

            -- Map Small Finance Banks
            WHEN TRIM(LOWER(raw_banks)) LIKE '%small finance%' 
            THEN 'SMALL FINANCE BANKS'

            -- Fallback categorization for individual foreign institutions
            ELSE 'FOREIGN BANKS'
        END AS bank_type,

        -- Institutional Risk Note: Hyphens, spaces, and true zero values are isolated.
        -- Non-reporting or un-published fields are explicitly cast to NULL (Not Given) 
        -- to protect numeric calculations (SUM, AVG) from distortion.
        CASE 
            WHEN TRIM(raw_npa) IN ('-', '', '0', '0.0') THEN NULL
            WHEN REPLACE(REPLACE(raw_npa, ',', ''), ' ', '') GLOB '*[0-9]*' 
            THEN CAST(REPLACE(REPLACE(raw_npa, ',', ''), ' ', '') AS REAL)
            ELSE NULL
        END AS gross_npas,
        
        CASE 
            WHEN TRIM(raw_advances) IN ('-', '', '0', '0.0') THEN NULL
            WHEN REPLACE(REPLACE(raw_advances, ',', ''), ' ', '') GLOB '*[0-9]*' 
            THEN CAST(REPLACE(REPLACE(raw_advances, ',', ''), ' ', '') AS REAL)
            ELSE NULL
        END AS gross_advances,
        
        CASE 
            WHEN TRIM(raw_ratio) IN ('-', '', '0', '0.0') THEN NULL
            WHEN REPLACE(REPLACE(raw_ratio, ',', ''), ' ', '') GLOB '*[0-9]*' 
            THEN CAST(REPLACE(REPLACE(raw_ratio, ',', ''), ' ', '') AS REAL)
            ELSE NULL
        END AS npa_ratio
    FROM filled_years
)
-- 5. Exclude aggregation/summary rows to maintain strict, granular asset level granularity
SELECT 
    year,
    bank_type,
    formatted_bank_name AS banks,
    gross_npas,
    gross_advances,
    npa_ratio
FROM standardized_data
WHERE banks_lower NOT LIKE '%all scheduled commercial banks%'
  AND banks_lower NOT LIKE '%public sector banks%'
  AND banks_lower NOT LIKE '%private sector banks%'
  AND banks_lower NOT LIKE '%small finance banks%'
  AND banks_lower NOT LIKE '%foreign banks%'
  AND banks_lower NOT LIKE '%nationalised banks%'
  AND banks_lower NOT LIKE '%source:%'
  AND banks_lower NOT LIKE '%mergers%'
  AND formatted_bank_name != ''
ORDER BY year DESC, bank_type ASC, banks ASC;
