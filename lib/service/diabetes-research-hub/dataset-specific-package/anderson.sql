-- code provenance: `TypicalSqlPageNotebook.commonDDL` (file:///home/runner/work/www.surveilr.com/www.surveilr.com/lib/std/notebook/sqlpage.ts)
-- idempotently create location where SQLPage looks for its content
CREATE TABLE IF NOT EXISTS "sqlpage_files" (
  "path" VARCHAR PRIMARY KEY NOT NULL,
  "contents" TEXT NOT NULL,
  "last_modified" TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Drop the view if it exists, then create the drh_participant view
DROP VIEW IF EXISTS drh_participant;
CREATE VIEW drh_participant AS
SELECT 
    'CTR3-' || DeidentID AS participant_id, -- Prefix 'CTR3-' to DeidentID to form participant_id
    'CTR3' AS study_id,                       -- Static assignment of study_id as 'CTR3'
    '' AS site_id,                            -- Placeholder for site_id
    '' AS diagnosis_icd,                     -- Placeholder for diagnosis ICD
    '' AS med_rxnorm,                         -- Placeholder for medication RxNorm
    '' AS treatment_modality,                 -- Placeholder for treatment modality
    Gender AS gender,                         -- Direct mapping of Gender
    Race || ', ' || Ethnicity AS race_ethnicity, -- Concatenate Race and Ethnicity for race_ethnicity
    "Age at Enrollment" AS age,               -- Direct mapping of Age at Enrollment
    CASE 
        WHEN Weight IS NOT NULL AND Height IS NOT NULL 
        THEN (Weight / ((Height / 100.0) * (Height / 100.0))) -- BMI calculation if Weight and Height are available
        ELSE NULL
    END AS bmi,                               -- Alias for BMI calculation
    HbA1CTest AS baseline_hba1c,             -- Mapping HbA1CTest to baseline_hba1c
    '' AS diabetes_type,                      -- Placeholder for diabetes type
    '' AS study_arm                           -- Placeholder for study arm
FROM uniform_resource_enrollment;

-- Drop the view if it exists, then create the view for uniform_resource_cgm
DROP VIEW IF EXISTS drh_vw_uniform_resource_cgm;
CREATE VIEW drh_vw_uniform_resource_cgm AS
SELECT
    'CTR3-' || DeidentID AS participant_id, -- Prefix 'CTR3-' to DeidentID for participant_id
    strftime('%Y-%m-%d %H:%M:%S', InternalTime) AS Date_Time, -- Format InternalTime to Date_Time
    CAST(CGM AS REAL) AS CGM_value             -- Cast CGM to REAL for numeric representation
FROM 
    uniform_resource_cgm;

-- Drop the view if it exists, then create the view for uniform_resource_cgmcal
DROP VIEW IF EXISTS drh_vw_uniform_resource_cgmcal;
CREATE VIEW drh_vw_uniform_resource_cgmcal AS
SELECT
    'CTR3-' || DeidentID AS participant_id, -- Prefix 'CTR3-' to DeidentID for participant_id
    strftime('%Y-%m-%d %H:%M:%S', InternalTime) AS Date_Time, -- Format InternalTime to Date_Time
    CAST(Cal AS REAL) AS CGM_value             -- Cast Cal to REAL for numeric representation
FROM 
    uniform_resource_cgmcal;

-- Drop the view if it exists, then create the view for uniform_resource_monitorcgm
DROP VIEW IF EXISTS drh_vw_uniform_resource_monitorcgm;
CREATE VIEW drh_vw_uniform_resource_monitorcgm AS
SELECT
    'CTR3-' || DeidentID AS participant_id, -- Prefix 'CTR3-' to DeidentID for participant_id
    strftime('%Y-%m-%d %H:%M:%S', LocalDtTm) AS Date_Time, -- Format LocalDtTm to Date_Time
    CAST(CGM AS REAL) AS CGM_value             -- Cast CGM to REAL for numeric representation
FROM 
    uniform_resource_monitorcgm;

-- Drop the view if it exists, then create the combined CGM tracing view
DROP VIEW IF EXISTS combined_cgm_tracing;
CREATE VIEW combined_cgm_tracing AS
SELECT 
    participant_id, 
    Date_Time, 
    CGM_value
FROM 
    drh_vw_uniform_resource_cgm
UNION ALL
SELECT 
    participant_id, 
    Date_Time, 
    CGM_value
FROM 
    drh_vw_uniform_resource_cgmcal
UNION ALL
SELECT 
    participant_id, 
    Date_Time, 
    CGM_value
FROM 
    drh_vw_uniform_resource_monitorcgm;


--CTR DS to DRH model (standarization with server UI)

-- View to count the number of CGM tracing files
DROP VIEW IF EXISTS drh_number_of_cgm_tracing_files_view;
CREATE VIEW drh_number_of_cgm_tracing_files_view AS
SELECT COUNT(*) AS table_count
FROM sqlite_master
WHERE type = 'table' 
AND name IN ('uniform_resource_cgm', 'uniform_resource_cgmcal', 'uniform_resource_monitorcgm');

-- View to list the names of raw CGM tables
DROP VIEW IF EXISTS drh_raw_cgm_table_lst;
CREATE VIEW drh_raw_cgm_table_lst AS
SELECT name, tbl_name as table_name
FROM sqlite_master
WHERE type = 'table' AND name IN ('uniform_resource_cgm', 'uniform_resource_cgmcal', 'uniform_resource_monitorcgm');

-- View to count the total number of CGM raw files
DROP VIEW IF EXISTS drh_number_cgm_count;
CREATE VIEW drh_number_cgm_count AS
SELECT count(*) as number_of_cgm_raw_files
FROM sqlite_master
WHERE type = 'table' AND name IN ('uniform_resource_cgm', 'uniform_resource_cgmcal', 'uniform_resource_monitorcgm');

DROP VIEW IF EXISTS study_wise_csv_file_names;
CREATE VIEW study_wise_csv_file_names AS
SELECT name 
FROM sqlite_master
WHERE type = 'table' AND name LIKE 'uniform_resource_%' and name !='uniform_resource_transform';


DROP VIEW IF EXISTS study_wise_number_cgm_raw_files_count;
CREATE VIEW study_wise_number_cgm_raw_files_count AS
SELECT count(*) as number_of_cgm_raw_files
FROM sqlite_master
WHERE type = 'table' AND name  IN ('uniform_resource_cgm', 'uniform_resource_cgmcal', 'uniform_resource_monitorcgm');

-------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-- Perform De-identification
-- Anonymize email addresses in the uniform_resource_investigator table
UPDATE uniform_resource_investigator
SET email = anonymize_email(email)
WHERE email IS NOT NULL;

-- Anonymize email addresses in the uniform_resource_author table
UPDATE uniform_resource_author
SET email = anonymize_email(email)
WHERE email IS NOT NULL;


CREATE TEMP VIEW IF NOT EXISTS device_info AS
SELECT device_id, name, created_at
FROM device d;


-- Insert into orchestration_nature only if it doesn't exist
INSERT OR IGNORE INTO orchestration_nature (
    orchestration_nature_id,
    nature,
    elaboration,
    created_at,
    created_by,
    updated_at,
    updated_by,
    deleted_at,
    deleted_by,
    activity_log
) 
SELECT
    'deidentification',         -- Unique ID for the orchestration nature
    'De-identification',        -- Human-readable name for the orchestration nature
    NULL,                       -- No elaboration provided at insert time
    CURRENT_TIMESTAMP,          -- Timestamp of creation
    d.device_id,                  -- Creator's name
    NULL,                       -- No updated timestamp yet
    NULL,                       -- No updater yet
    NULL,                       -- Not deleted
    NULL,                       -- No deleter yet
    NULL                        -- No activity log yet
FROM device_info d
LIMIT 1;  -- Limiting to 1 device

-- Insert into orchestration_session only if it doesn't exist
INSERT OR IGNORE INTO orchestration_session (
    orchestration_session_id,
    device_id,
    orchestration_nature_id,
    version,
    orch_started_at,
    orch_finished_at,
    elaboration,
    args_json,
    diagnostics_json,
    diagnostics_md
)
SELECT
    'ORCHSESSID-' || hex(randomblob(16)),  -- Generate a random hex blob for orchestration_session_id
    d.device_id,                             -- Pull device_id from the device_info view
    'deidentification',                      -- Reference to the orchestration_nature_id we just inserted
    '',                                      -- Version (placeholder)
    CURRENT_TIMESTAMP,                       -- Start time
    NULL,                                    -- Finished time (to be updated later)
    NULL,                                    -- Elaboration (if any)
    NULL,                                    -- Args JSON (if any)
    NULL,                                    -- Diagnostics JSON (if any)
    NULL                                     -- Diagnostics MD (if any)
FROM device_info d
LIMIT 1;  -- Limiting to 1 device

-- Create a temporary view to retrieve orchestration session information
CREATE TEMP VIEW IF NOT EXISTS session_info AS
SELECT
    orchestration_session_id
FROM 
    orchestration_session
WHERE 
    orchestration_nature_id = 'deidentification'
LIMIT 1;

-- Insert into orchestration_session_entry only if it doesn't exist
INSERT OR IGNORE INTO orchestration_session_entry (
    orchestration_session_entry_id,
    session_id,
    ingest_src,
    ingest_table_name,
    elaboration
) VALUES (
    'ORCHSESSENID-' || hex(randomblob(16)),  -- Generate a random hex blob for orchestration_session_entry_id
    (SELECT orchestration_session_id FROM session_info limit 1),  -- Session ID from previous insert
    'ctr-anderson-stateless.sql',  -- Replace with actual ingest source
    '',  -- Placeholder for actual table name
    NULL  -- Elaboration (if any)
);

-- Create or replace a temporary view for session execution tracking
DROP VIEW IF EXISTS temp_session_info;  -- Remove any existing view
CREATE TEMP VIEW temp_session_info AS
SELECT
    orchestration_session_id,
    (SELECT orchestration_session_entry_id FROM orchestration_session_entry WHERE session_id = orchestration_session_id LIMIT 1) AS orchestration_session_entry_id
FROM orchestration_session 
WHERE orchestration_nature_id = 'deidentification'
LIMIT 1;

-- Insert into orchestration_session_exec for uniform_resource_investigator
INSERT OR IGNORE INTO orchestration_session_exec (
    orchestration_session_exec_id,
    exec_nature,
    session_id,
    session_entry_id,
    exec_code,
    exec_status,
    input_text,
    output_text,
    exec_error_text,
    narrative_md
)
SELECT
    'ORCHSESSEXID-' || ((SELECT COUNT(*) FROM orchestration_session_exec) + 1),  -- Unique ID based on count
    'De-identification',                                -- Nature of execution
    s.orchestration_session_id,                         -- Session ID from the temp view
    s.orchestration_session_entry_id,                   -- Session Entry ID from the temp view
    'UPDATE uniform_resource_investigator SET email = anonymize_email(email) executed',  -- Description of the executed code
    'SUCCESS',                                          -- Execution status
    'email column in uniform_resource_investigator',   -- Input text reference
    'De-identification completed',                      -- Output text summary
    CASE 
        WHEN (SELECT changes() = 0) THEN 'No rows updated'  -- Capture update status
        ELSE NULL 
    END,
    'username in email is masked'                       -- Narrative for clarification
FROM temp_session_info s;  -- From the temporary session info view

-- Insert into orchestration_session_exec for uniform_resource_author
INSERT OR IGNORE INTO orchestration_session_exec (
    orchestration_session_exec_id,
    exec_nature,
    session_id,
    session_entry_id,
    exec_code,
    exec_status,
    input_text,
    output_text,
    exec_error_text,
    narrative_md
)
SELECT
    'ORCHSESSEXID-' || ((SELECT COUNT(*) FROM orchestration_session_exec) + 1),  -- Unique ID based on count
    'De-identification',                                -- Nature of execution
    s.orchestration_session_id,                         -- Session ID from the temp view
    s.orchestration_session_entry_id,                   -- Session Entry ID from the temp view
    'UPDATE uniform_resource_author SET email = anonymize_email(email) executed',  -- Description of the executed code
    'SUCCESS',                                          -- Execution status
    'email column in uniform_resource_author',          -- Input text reference
    'De-identification completed',                      -- Output text summary
    CASE 
        WHEN (SELECT changes() = 0) THEN 'No rows updated'  -- Capture update status
        ELSE NULL 
    END,
    'username in email is masked'                       -- Narrative for clarification
FROM temp_session_info s;  -- From the temporary session info view

-- Update orchestration_session to set finished timestamp and diagnostics
UPDATE orchestration_session
SET 
    orch_finished_at = CURRENT_TIMESTAMP,             -- Set the finish time
    diagnostics_json = '{"status": "completed"}',     -- Diagnostics status in JSON format
    diagnostics_md = 'De-identification process completed'  -- Markdown summary
WHERE orchestration_session_id = (SELECT orchestration_session_id FROM temp_session_info LIMIT 1);  -- Update the session identified in the temp view


-----------------------------------------------------------------------------
-- Verification and validation process

-- Create a view that represents the expected schema with required columns and properties
CREATE VIEW IF NOT EXISTS expected_schema_view AS
SELECT 
'uniform_resource_institution' AS table_name, 'institution_id' AS column_name, 'TEXT' AS column_type, 1 AS is_primary_key, 1 AS not_null
UNION ALL SELECT 'uniform_resource_institution', 'institution_name', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_institution', 'city', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_institution', 'state', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_institution', 'country', 'TEXT', 0, 1

UNION ALL SELECT 'uniform_resource_lab', 'lab_id', 'TEXT', 1, 1
UNION ALL SELECT 'uniform_resource_lab', 'lab_name', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_lab', 'lab_pi', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_lab', 'institution_id', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_lab', 'study_id', 'TEXT', 0, 1

UNION ALL SELECT 'uniform_resource_study', 'study_id', 'TEXT', 1, 1
UNION ALL SELECT 'uniform_resource_study', 'study_name', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_study', 'start_date', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_study', 'end_date', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_study', 'treatment_modalities', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_study', 'funding_source', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_study', 'nct_number', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_study', 'study_description', 'TEXT', 0, 1

UNION ALL SELECT 'uniform_resource_site', 'site_id', 'TEXT', 1, 1
UNION ALL SELECT 'uniform_resource_site', 'study_id', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_site', 'site_name', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_site', 'site_type', 'TEXT', 0, 1


UNION ALL SELECT 'uniform_resource_investigator', 'investigator_id', 'TEXT', 1, 1
UNION ALL SELECT 'uniform_resource_investigator', 'investigator_name', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_investigator', 'email', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_investigator', 'institution_id', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_investigator', 'study_id', 'TEXT', 0, 1

UNION ALL SELECT 'uniform_resource_publication', 'publication_id', 'TEXT', 1, 1
UNION ALL SELECT 'uniform_resource_publication', 'publication_title', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_publication', 'digital_object_identifier', 'TEXT', 0, 0
UNION ALL SELECT 'uniform_resource_publication', 'publication_site', 'TEXT', 0, 0
UNION ALL SELECT 'uniform_resource_publication', 'study_id', 'TEXT', 0, 1

UNION ALL SELECT 'uniform_resource_author', 'author_id', 'TEXT', 1, 1
UNION ALL SELECT 'uniform_resource_author', 'name', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_author', 'email', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_author', 'investigator_id', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_author', 'study_id', 'TEXT', 0, 1

UNION ALL SELECT 'uniform_resource_cgm_file_metadata', 'metadata_id', 'TEXT', 1, 1
UNION ALL SELECT 'uniform_resource_cgm_file_metadata', 'devicename', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_cgm_file_metadata', 'device_id', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_cgm_file_metadata', 'source_platform', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_cgm_file_metadata', 'patient_id', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_cgm_file_metadata', 'file_name', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_cgm_file_metadata', 'file_format', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_cgm_file_metadata', 'file_upload_date', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_cgm_file_metadata', 'data_start_date', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_cgm_file_metadata', 'data_end_date', 'TEXT', 0, 1
UNION ALL SELECT 'uniform_resource_cgm_file_metadata', 'study_id', 'TEXT', 0, 1;

CREATE TEMP VIEW IF NOT EXISTS device_info AS
SELECT device_id, name, created_at
FROM device d;


INSERT OR IGNORE INTO orchestration_nature (
    orchestration_nature_id,
    nature,
    elaboration,
    created_at,
    created_by,
    updated_at,
    updated_by,
    deleted_at,
    deleted_by,
    activity_log
) 
SELECT
    'V&V',                                   -- orchestration_nature_id (unique identifier)
    'Verification and Validation',           -- nature
    NULL,                                    -- elaboration
    CURRENT_TIMESTAMP,          -- Timestamp of creation
    d.device_id,                               -- created_by
    NULL,                                    -- updated_at
    NULL,                                    -- updated_by
    NULL,                                    -- deleted_at
    NULL,                                    -- deleted_by
    NULL                                     -- activity_log
FROM device_info d
LIMIT 1;  -- Limiting to 1 device


-- Insert into orchestration_session only if it doesn't exist
INSERT OR IGNORE INTO orchestration_session (
    orchestration_session_id,
    device_id,
    orchestration_nature_id,
    version,
    orch_started_at,
    orch_finished_at,
    elaboration,
    args_json,
    diagnostics_json,
    diagnostics_md
)
SELECT
    'ORCHSESSID-' || hex(randomblob(16)),  -- Generate a random hex blob for orchestration_session_id
    d.device_id,                             -- Pull device_id from the device_info view
    'V&V',                      -- Reference to the orchestration_nature_id we just inserted
    '',                                      -- Version (placeholder)
    CURRENT_TIMESTAMP,                       -- Start time
    NULL,                                    -- Finished time (to be updated later)
    NULL,                                    -- Elaboration (if any)
    NULL,                                    -- Args JSON (if any)
    NULL,                                    -- Diagnostics JSON (if any)
    NULL                                     -- Diagnostics MD (if any)
FROM device_info d
LIMIT 1;  -- Limiting to 1 device

-- Create a temporary view to retrieve orchestration session information
CREATE TEMP VIEW IF NOT EXISTS session_info AS
SELECT
    orchestration_session_id
FROM 
    orchestration_session
WHERE 
    orchestration_nature_id = 'V&V'
LIMIT 1;

-- Insert into orchestration_session_entry only if it doesn't exist
INSERT OR IGNORE INTO orchestration_session_entry (
    orchestration_session_entry_id,
    session_id,
    ingest_src,
    ingest_table_name,
    elaboration
) VALUES (
    'ORCHSESSENID-' || hex(randomblob(16)),  -- Generate a random hex blob for orchestration_session_entry_id
    (SELECT orchestration_session_id FROM session_info limit 1),  -- Session ID from previous insert
    'ctr-anderson-stateless.sql',  -- Replace with actual ingest source
    '',  -- Placeholder for actual table name
    NULL  -- Elaboration (if any)
);


-- Create or Replace Temp Session Info View
DROP VIEW IF EXISTS temp_session_info;
CREATE TEMP VIEW temp_session_info AS
SELECT
    orchestration_session_id,
    (SELECT orchestration_session_entry_id FROM orchestration_session_entry WHERE session_id = orchestration_session_id LIMIT 1) AS orchestration_session_entry_id
FROM orchestration_session 
WHERE orchestration_nature_id = 'V&V'
LIMIT 1;

-- Create or Replace Temp Schema Validation Missing Columns View
DROP VIEW IF EXISTS temp_SchemaValidationMissingColumns;
CREATE TEMP VIEW temp_SchemaValidationMissingColumns AS
SELECT 
    'Schema Validation: Missing Columns' AS heading,
    e.table_name,
    e.column_name,
    e.column_type,
    e.is_primary_key,
    'Missing column: ' || e.column_name || ' in table ' || e.table_name AS status,
    'Include the ' || e.column_name || ' in table ' || e.table_name AS remediation
FROM 
    expected_schema_view e
LEFT JOIN (
    SELECT 
        m.name AS table_name,
        p.name AS column_name,
        p.type AS column_type,
        p.pk AS is_primary_key
    FROM 
        sqlite_master m
    JOIN 
        pragma_table_info(m.name) p
    WHERE 
        m.type = 'table' AND
        m.name NOT LIKE 'uniform_resource_cgm_tracing%' AND
        m.name != 'uniform_resource_transform' AND 
        m.name LIKE 'uniform_resource_%'
) a ON e.table_name = a.table_name AND e.column_name = a.column_name
WHERE 
    a.column_name IS NULL;

--  Insert Operation into orchestration_session_issue Table
INSERT OR IGNORE INTO orchestration_session_issue (
    orchestration_session_issue_id, 
    session_id, 
    session_entry_id, 
    issue_type, 
    issue_message, 
    issue_row, 
    issue_column, 
    invalid_value, 
    remediation, 
    elaboration
)
SELECT 
    lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(6))) AS orchestration_session_issue_id,
    tsi.orchestration_session_id,
    tsi.orchestration_session_entry_id,
    svc.heading AS issue_type,
    svc.status AS issue_message,
    NULL AS issue_row,
    svc.column_name AS issue_column,
    NULL AS invalid_value,
    svc.remediation,
    NULL AS elaboration
FROM 
    temp_SchemaValidationMissingColumns svc
JOIN 
    temp_session_info tsi ON 1=1;





DROP VIEW IF EXISTS temp_DataIntegrityInvalidDates;
CREATE TEMP VIEW temp_DataIntegrityInvalidDates AS
SELECT 
    'Data Integrity Checks: Invalid Dates' AS heading,
    table_name,
    column_name,
    value,
    'Dates must be in YYYY-MM-DD format: ' || value AS status,
    'The date value in column: ' || column_name || ' of table ' || table_name || ' does not follow the YYYY-MM-DD format. Please ensure the dates are in this format' AS remediation
FROM (
    SELECT 
        'uniform_resource_study' AS table_name,
        'start_date' AS column_name,
        start_date AS value
    FROM 
        uniform_resource_study
    WHERE 
        start_date IS NOT NULL AND start_date != ''
    
    UNION ALL
    
    SELECT 
        'uniform_resource_study' AS table_name,
        'end_date' AS column_name,
        end_date AS value
    FROM 
        uniform_resource_study
    WHERE 
        end_date IS NOT NULL AND end_date != ''
    
    UNION ALL
    
    SELECT 
        'uniform_resource_cgm_file_metadata' AS table_name,
        'file_upload_date' AS column_name,
        file_upload_date AS value
    FROM 
        uniform_resource_cgm_file_metadata
    WHERE 
        file_upload_date IS NOT NULL AND file_upload_date != ''
    
    UNION ALL
    
    SELECT 
        'uniform_resource_cgm_file_metadata' AS table_name,
        'data_start_date' AS column_name,
        data_start_date AS value
    FROM 
        uniform_resource_cgm_file_metadata
    WHERE 
        data_start_date IS NOT NULL AND data_start_date != ''
    
    UNION ALL
    
    SELECT 
        'uniform_resource_cgm_file_metadata' AS table_name,
        'data_end_date' AS column_name,
        data_end_date AS value
    FROM 
        uniform_resource_cgm_file_metadata
    WHERE 
        data_end_date IS NOT NULL AND data_end_date != ''
) 
WHERE 
    value NOT LIKE '____-__-__';


INSERT OR IGNORE INTO orchestration_session_issue (
    orchestration_session_issue_id, 
    session_id, 
    session_entry_id, 
    issue_type, 
    issue_message, 
    issue_row, 
    issue_column, 
    invalid_value, 
    remediation, 
    elaboration
)
SELECT 
    lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(6))) AS orchestration_session_issue_id,
    tsi.orchestration_session_id,
    tsi.orchestration_session_entry_id,
    diid.heading AS issue_type,
    diid.status AS issue_message,
    NULL AS issue_row,
    diid.column_name AS issue_column,
    diid.value AS invalid_value,
    diid.remediation,
    NULL AS elaboration
FROM temp_DataIntegrityInvalidDates diid
JOIN 
    temp_session_info tsi ON 1=1;

-- Generate SQL for finding empty or NULL values in table

DROP VIEW IF EXISTS DataIntegrityEmptyCells;
CREATE TEMP VIEW DataIntegrityEmptyCells AS
    SELECT 
        'Data Integrity Checks: Empty Cells' AS heading,
        table_name,
        column_name,
        'The rows empty are:'|| GROUP_CONCAT(rowid) AS issue_row,  -- Concatenates row IDs with empty values
        'The following rows in column ' || column_name || ' of file ' || substr(table_name, 18) || ' are either NULL or empty.' AS status,
        'Please provide values for the ' || column_name || ' column in file ' || substr(table_name, 18) ||'.The Rows are:'|| GROUP_CONCAT(rowid) AS remediation
    FROM (
        
        SELECT 
            'uniform_resource_study' AS table_name,
            'study_id' AS column_name,
            study_id AS value,
            rowid
        FROM 
            uniform_resource_study  
        WHERE 
            study_id IS NULL OR study_id = ''

        UNION ALL

        SELECT 
            'uniform_resource_study' AS table_name,
            'study_name' AS column_name,
            study_name AS value,
            rowid
        FROM 
            uniform_resource_study  
        WHERE 
            study_name IS NULL OR study_name = ''

        UNION ALL

        SELECT 
            'uniform_resource_study' AS table_name,
            'start_date' AS column_name,
            start_date AS value,
            rowid
        FROM 
            uniform_resource_study  
        WHERE 
            start_date IS NULL OR start_date = ''
        
        UNION ALL
        
        
        SELECT 
            'uniform_resource_study' AS table_name,
            'end_date' AS column_name,
            end_date AS value,
            rowid
        FROM 
            uniform_resource_study 
        WHERE 
            end_date IS NULL OR end_date = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_study' AS table_name,
            'treatment_modalities' AS column_name,
            treatment_modalities AS value,
            rowid
        FROM 
            uniform_resource_study 
        WHERE 
            treatment_modalities IS NULL OR treatment_modalities = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_study' AS table_name,
            'funding_source' AS column_name,
            funding_source AS value,
            rowid
        FROM 
            uniform_resource_study 
        WHERE 
            funding_source IS NULL OR funding_source = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_study' AS table_name,
            'nct_number' AS column_name,
            nct_number AS value,
            rowid
        FROM 
            uniform_resource_study 
        WHERE 
            nct_number IS NULL OR nct_number = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_study' AS table_name,
            'study_description' AS column_name,
            study_description AS value,
            rowid
        FROM 
            uniform_resource_study 
        WHERE 
            study_description IS NULL OR study_description = ''
        
        UNION ALL


        --- uniform_resource_institution table

        SELECT 
            'uniform_resource_institution' AS table_name,
            'institution_id' AS column_name,
            institution_id AS value,
            rowid
        FROM 
            uniform_resource_institution 
        WHERE 
            institution_id IS NULL OR institution_id = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_institution' AS table_name,
            'institution_name' AS column_name,
            institution_name AS value,
            rowid
        FROM 
            uniform_resource_institution 
        WHERE 
            institution_name IS NULL OR institution_name = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_institution' AS table_name,
            'city' AS column_name,
            city AS value,
            rowid
        FROM 
            uniform_resource_institution 
        WHERE 
            city IS NULL OR city = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_institution' AS table_name,
            'state' AS column_name,
            state AS value,
            rowid
        FROM 
            uniform_resource_institution 
        WHERE 
            state IS NULL OR state = ''
        
        UNION ALL

         SELECT 
            'uniform_resource_institution' AS table_name,
            'country' AS column_name,
            country AS value,
            rowid
        FROM 
            uniform_resource_institution 
        WHERE 
            country IS NULL OR country = ''
        
        UNION ALL       
        

        -- uniform_resource_site table

        SELECT 
            'uniform_resource_site' AS table_name,
            'site_id' AS column_name,
            site_id AS value,
            rowid
        FROM 
            uniform_resource_site  
        WHERE 
            site_id IS NULL OR site_id = ''
        
        UNION ALL
        

        SELECT 
            'uniform_resource_site' AS table_name,
            'study_id' AS column_name,
            study_id AS value,
            rowid
        FROM 
            uniform_resource_site  
        WHERE 
            study_id IS NULL OR study_id = ''
        
        UNION ALL


        SELECT 
            'uniform_resource_site' AS table_name,
            'site_name' AS column_name,
            site_name AS value,
            rowid
        FROM 
            uniform_resource_site  
        WHERE 
            site_name IS NULL OR site_name = ''
        
        UNION ALL

        
        SELECT 
            'uniform_resource_site' AS table_name,
            'site_type' AS column_name,
            site_type AS value,
            rowid
        FROM 
            uniform_resource_site  
        WHERE 
            site_type IS NULL OR site_type = ''
        
        UNION ALL        

        -- uniform_resource_lab table

        SELECT 
            'uniform_resource_lab' AS table_name,
            'lab_id' AS column_name,
            lab_id AS value,
            rowid
        FROM 
            uniform_resource_lab  
        WHERE 
            lab_id IS NULL OR lab_id = ''
        
        UNION ALL       

        SELECT 
            'uniform_resource_lab' AS table_name,
            'lab_name' AS column_name,
            lab_name AS value,
            rowid
        FROM 
            uniform_resource_lab  
        WHERE 
            lab_name IS NULL OR lab_name = ''
        
        UNION ALL      

         SELECT 
            'uniform_resource_lab' AS table_name,
            'lab_pi' AS column_name,
            lab_pi AS value,
            rowid
        FROM 
            uniform_resource_lab  
        WHERE 
            lab_pi IS NULL OR lab_pi = ''
        
        UNION ALL    

          SELECT 
            'uniform_resource_lab' AS table_name,
            'institution_id' AS column_name,
            institution_id AS value,
            rowid
        FROM 
            uniform_resource_lab  
        WHERE 
            institution_id IS NULL OR institution_id = ''
        
        UNION ALL    

        SELECT 
            'uniform_resource_lab' AS table_name,
            'study_id' AS column_name,
            study_id AS value,
            rowid
        FROM 
            uniform_resource_lab  
        WHERE 
            study_id IS NULL OR study_id = ''
        
        UNION ALL    
        

        -- uniform_resource_cgm_file_metadata 

        SELECT 
            'uniform_resource_cgm_file_metadata' AS table_name,
            'metadata_id' AS column_name,
            metadata_id AS value,
            rowid
        FROM 
            uniform_resource_cgm_file_metadata  
        WHERE 
            metadata_id IS NULL OR metadata_id = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_cgm_file_metadata' AS table_name,
            'devicename' AS column_name,
            devicename AS value,
            rowid
        FROM 
            uniform_resource_cgm_file_metadata  
        WHERE 
            devicename IS NULL OR devicename = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_cgm_file_metadata' AS table_name,
            'device_id' AS column_name,
            device_id AS value,
            rowid
        FROM 
            uniform_resource_cgm_file_metadata  
        WHERE 
            device_id IS NULL OR device_id = ''
        
        UNION ALL


        SELECT 
            'uniform_resource_cgm_file_metadata' AS table_name,
            'source_platform' AS column_name,
            source_platform AS value,
            rowid
        FROM 
            uniform_resource_cgm_file_metadata  
        WHERE 
            source_platform IS NULL OR source_platform = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_cgm_file_metadata' AS table_name,
            'patient_id' AS column_name,
            patient_id AS value,
            rowid
        FROM 
            uniform_resource_cgm_file_metadata  
        WHERE 
            patient_id IS NULL OR patient_id = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_cgm_file_metadata' AS table_name,
            'file_name' AS column_name,
            file_name AS value,
            rowid
        FROM 
            uniform_resource_cgm_file_metadata  
        WHERE 
            file_name IS NULL OR file_name = ''
        
        UNION ALL

        
        SELECT 
            'uniform_resource_cgm_file_metadata' AS table_name,
            'file_format' AS column_name,
            file_format AS value,
            rowid
        FROM 
            uniform_resource_cgm_file_metadata  
        WHERE 
            file_format IS NULL OR file_format = ''
        
        UNION ALL



        SELECT 
            'uniform_resource_cgm_file_metadata' AS table_name,
            'file_upload_date' AS column_name,
            file_upload_date AS value,
            rowid
        FROM 
            uniform_resource_cgm_file_metadata  
        WHERE 
            file_upload_date IS NULL OR file_upload_date = ''
        
        UNION ALL
        
        
        SELECT 
            'uniform_resource_cgm_file_metadata' AS table_name,
            'data_start_date' AS column_name,
            data_start_date AS value,
            rowid
        FROM 
            uniform_resource_cgm_file_metadata 
        WHERE 
            data_start_date IS NULL OR data_start_date = ''
        
        UNION ALL
        

        SELECT 
            'uniform_resource_cgm_file_metadata' AS table_name,
            'data_end_date' AS column_name,
            data_end_date AS value,
            rowid
        FROM 
            uniform_resource_cgm_file_metadata 
        WHERE 
            data_end_date IS NULL OR data_end_date = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_cgm_file_metadata' AS table_name,
            'study_id' AS column_name,
            study_id AS value,
            rowid
        FROM 
            uniform_resource_cgm_file_metadata  
        WHERE 
            study_id IS NULL OR study_id = ''
        
        UNION ALL

        -- uniform_resource_investigator
        SELECT 
            'uniform_resource_investigator' AS table_name,
            'investigator_id' AS column_name,
            investigator_id AS value,
            rowid
        FROM 
            uniform_resource_investigator 
        WHERE 
            investigator_id IS NULL OR investigator_id = ''

        UNION ALL

        SELECT 
            'uniform_resource_investigator' AS table_name,
            'investigator_name' AS column_name,
            investigator_name AS value,
            rowid
        FROM 
            uniform_resource_investigator 
        WHERE 
            investigator_name IS NULL OR investigator_name = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_investigator' AS table_name,
            'email' AS column_name,
            email AS value,
            rowid
        FROM 
            uniform_resource_investigator 
        WHERE 
            email IS NULL OR email = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_investigator' AS table_name,
            'institution_id' AS column_name,
            institution_id AS value,
            rowid
        FROM 
            uniform_resource_investigator 
        WHERE 
            institution_id IS NULL OR institution_id = ''

        UNION ALL

        SELECT 
            'uniform_resource_investigator' AS table_name,
            'study_id' AS column_name,
            study_id AS value,
            rowid
        FROM 
            uniform_resource_investigator 
        WHERE 
            study_id IS NULL OR study_id = ''

        UNION ALL

        -- uniform_resource_publication table

        SELECT 
            'uniform_resource_publication' AS table_name,
            'publication_id' AS column_name,
            publication_id AS value,
            rowid
        FROM 
            uniform_resource_publication 
        WHERE 
            publication_id IS NULL OR publication_id = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_publication' AS table_name,
            'publication_title' AS column_name,
            publication_title AS value,
            rowid
        FROM 
            uniform_resource_publication 
        WHERE 
            publication_title IS NULL OR publication_title = ''

        UNION ALL

        SELECT 
            'uniform_resource_publication' AS table_name,
            'digital_object_identifier' AS column_name,
            digital_object_identifier AS value,
            rowid
        FROM 
            uniform_resource_publication 
        WHERE 
            digital_object_identifier IS NULL OR digital_object_identifier = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_publication' AS table_name,
            'publication_site' AS column_name,
            publication_site AS value,
            rowid
        FROM 
            uniform_resource_publication 
        WHERE 
            publication_site IS NULL OR publication_site = ''

        UNION ALL

        SELECT 
            'uniform_resource_publication' AS table_name,
            'study_id' AS column_name,
            study_id AS value,
            rowid
        FROM 
            uniform_resource_publication 
        WHERE 
            study_id IS NULL OR study_id = ''
        
        -- uniform_resource_author table

        UNION ALL

        SELECT 
            'uniform_resource_author' AS table_name,
            'author_id' AS column_name,
            author_id AS value,
            rowid
        FROM 
            uniform_resource_author 
        WHERE 
            author_id IS NULL OR author_id = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_author' AS table_name,
            'name' AS column_name,
            name AS value,
            rowid
        FROM 
            uniform_resource_author 
        WHERE 
            name IS NULL OR name = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_author' AS table_name,
            'email' AS column_name,
            email AS value,
            rowid
        FROM 
            uniform_resource_author 
        WHERE 
            email IS NULL OR email = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_author' AS table_name,
            'investigator_id' AS column_name,
            investigator_id AS value,
            rowid
        FROM 
            uniform_resource_author 
        WHERE 
            investigator_id IS NULL OR investigator_id = ''
        
        UNION ALL

        SELECT 
            'uniform_resource_author' AS table_name,
            'study_id' AS column_name,
            study_id AS value,
            rowid
        FROM 
            uniform_resource_author 
        WHERE 
            study_id IS NULL OR study_id = ''

    )
    GROUP BY table_name, column_name ; 


INSERT OR IGNORE INTO orchestration_session_issue (
    orchestration_session_issue_id, 
    session_id, 
    session_entry_id, 
    issue_type, 
    issue_message, 
    issue_row, 
    issue_column, 
    invalid_value, 
    remediation, 
    elaboration
)
SELECT 
    lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(6))) AS orchestration_session_issue_id,
    tsi.orchestration_session_id,
    tsi.orchestration_session_entry_id,
    d_empty.heading AS issue_type,
    d_empty.status AS issue_message,
    d_empty.issue_row AS issue_row,
    d_empty.column_name AS issue_column,
    NULL AS invalid_value,
    d_empty.remediation AS remediation,
    NULL AS elaboration
FROM DataIntegrityEmptyCells d_empty
JOIN 
    temp_session_info tsi ON 1=1;


DROP VIEW IF EXISTS table_counts;
CREATE TEMP VIEW table_counts AS
SELECT 
    'uniform_resource_study' AS table_name,
    COUNT(*) AS row_count
FROM uniform_resource_study
UNION ALL
SELECT 'uniform_resource_cgm_file_metadata' AS table_name,
    COUNT(*) AS row_count
FROM uniform_resource_cgm_file_metadata
UNION ALL
SELECT 'drh_participant' AS table_name,
    COUNT(*) AS row_count
FROM drh_participant
UNION ALL
SELECT 'uniform_resource_institution' AS table_name,
    COUNT(*) AS row_count
FROM uniform_resource_institution
UNION ALL
SELECT 'uniform_resource_lab' AS table_name,
    COUNT(*) AS row_count
FROM uniform_resource_lab
UNION ALL
SELECT 'uniform_resource_site' AS table_name,
    COUNT(*) AS row_count
FROM uniform_resource_site
UNION ALL
SELECT 'uniform_resource_investigator' AS table_name,
    COUNT(*) AS row_count
FROM uniform_resource_investigator
UNION ALL
SELECT 'uniform_resource_publication' AS table_name,
    COUNT(*) AS row_count
FROM uniform_resource_publication
UNION ALL
SELECT 'uniform_resource_author' AS table_name,
    COUNT(*) AS row_count
FROM uniform_resource_author;


DROP VIEW IF EXISTS empty_tables;
CREATE TEMP VIEW empty_tables AS
SELECT 
    table_name,
    row_count,
    'The File ' || substr(table_name, 18) || ' is empty' AS status,
    'The file ' || substr(table_name, 18) || ' has zero records. Please check and ensure the file is populated with data.' AS remediation
FROM 
    table_counts
WHERE 
    row_count = 0;


INSERT OR IGNORE INTO orchestration_session_issue (
    orchestration_session_issue_id, 
    session_id, 
    session_entry_id, 
    issue_type, 
    issue_message, 
    issue_row, 
    issue_column, 
    invalid_value, 
    remediation, 
    elaboration
)
SELECT 
    lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(6))) AS orchestration_session_issue_id,
    tsi.orchestration_session_id,
    tsi.orchestration_session_entry_id,
    'Data Integrity Checks: Empty Tables' AS issue_type,
    ed.status AS issue_message,
    NULL AS issue_row,
    NULL AS issue_column,
    NULL AS invalid_value,
    ed.remediation,
    NULL AS elaboration
FROM 
    empty_tables ed
JOIN 
    temp_session_info tsi ON 1=1;


-- CREATE TEMP VIEW EmptyCellsEnrollment AS
-- SELECT 
--     'Data Integrity Checks: Empty Cells' AS heading,
--     'Enrollment' AS table_name,
--     column_name,
--     COUNT(*) AS missing_count,  -- Count of missing values in the column
--     'The following rows in column ' || column_name || ' of file ' || substr('Enrollment', 18) || ' are either NULL or empty: ' || 
--     GROUP_CONCAT(CASE 
--         WHEN column_name = 'participant_id' THEN participant_id
--         WHEN column_name = 'study_id' THEN study_id
--         WHEN column_name = 'site_id' THEN site_id
--         WHEN column_name = 'diagnosis_icd' THEN diagnosis_icd
--         WHEN column_name = 'med_rxnorm' THEN med_rxnorm
--         WHEN column_name = 'treatment_modality' THEN treatment_modality
--         WHEN column_name = 'gender' THEN gender
--         WHEN column_name = 'race_ethnicity' THEN race_ethnicity
--         WHEN column_name = 'age' THEN age
--         WHEN column_name = 'bmi' THEN bmi
--         WHEN column_name = 'baseline_hba1c' THEN baseline_hba1c
--         WHEN column_name = 'diabetes_type' THEN diabetes_type
--         WHEN column_name = 'study_arm' THEN study_arm
--         END
--     ) AS status,
--     'Please provide values for the ' || column_name || ' column in file ' || substr('Enrollment', 18) || '.' AS remediation
-- FROM (
--     SELECT 
--         'participant_id' AS column_name,
--         participant_id
--     FROM drh_participant
--     WHERE participant_id IS NULL OR participant_id = ''
    
--     UNION ALL
    
--     SELECT 
--         'study_id' AS column_name,
--         study_id
--     FROM drh_participant
--     WHERE study_id IS NULL OR study_id = ''
    
--     UNION ALL
    
--     SELECT 
--         'site_id' AS column_name,
--         site_id
--     FROM drh_participant
--     WHERE site_id IS NULL OR site_id = ''
    
--     UNION ALL
    
--     SELECT 
--         'diagnosis_icd' AS column_name,
--         diagnosis_icd
--     FROM drh_participant
--     WHERE diagnosis_icd IS NULL OR diagnosis_icd = ''
    
--     UNION ALL
    
--     SELECT 
--         'med_rxnorm' AS column_name,
--         med_rxnorm
--     FROM drh_participant
--     WHERE med_rxnorm IS NULL OR med_rxnorm = ''
    
--     UNION ALL
    
--     SELECT 
--         'treatment_modality' AS column_name,
--         treatment_modality
--     FROM drh_participant
--     WHERE treatment_modality IS NULL OR treatment_modality = ''
    
--     UNION ALL
    
--     SELECT 
--         'gender' AS column_name,
--         gender
--     FROM drh_participant
--     WHERE gender IS NULL OR gender = ''
    
--     UNION ALL
    
--     SELECT 
--         'race_ethnicity' AS column_name,
--         race_ethnicity
--     FROM drh_participant
--     WHERE race_ethnicity IS NULL OR race_ethnicity = ''
    
--     UNION ALL
    
--     SELECT 
--         'age' AS column_name,
--         age
--     FROM drh_participant
--     WHERE age IS NULL OR age = ''
    
--     UNION ALL
    
--     SELECT 
--         'bmi' AS column_name,
--         bmi
--     FROM drh_participant
--     WHERE bmi IS NULL OR bmi = ''
    
--     UNION ALL
    
--     SELECT 
--         'baseline_hba1c' AS column_name,
--         baseline_hba1c
--     FROM drh_participant
--     WHERE baseline_hba1c IS NULL OR baseline_hba1c = ''
    
--     UNION ALL
    
--     SELECT 
--         'diabetes_type' AS column_name,
--         diabetes_type
--     FROM drh_participant
--     WHERE diabetes_type IS NULL OR diabetes_type = ''
    
--     UNION ALL
    
--     SELECT 
--         'study_arm' AS column_name,
--         study_arm
--     FROM drh_participant
--     WHERE study_arm IS NULL OR study_arm = ''
-- ) AS missing_data
-- GROUP BY column_name;



-- -- INSERT OR IGNORE INTO orchestration_session_issue (
-- --     orchestration_session_issue_id, 
-- --     session_id, 
-- --     session_entry_id, 
-- --     issue_type, 
-- --     issue_message, 
-- --     issue_row, 
-- --     issue_column, 
-- --     invalid_value, 
-- --     remediation, 
-- --     elaboration
-- -- )
-- -- SELECT 
-- --     lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(6))) AS orchestration_session_issue_id,
-- --     tsi.orchestration_session_id,
-- --     tsi.orchestration_session_entry_id,
-- --     d_empty.heading AS issue_type,
-- --     d_empty.status AS issue_message,
-- --     d_empty.issue_row AS issue_row,
-- --     d_empty.column_name AS issue_column,
-- --     NULL AS invalid_value,
-- --     d_empty.remediation AS remediation,
-- --     NULL AS elaboration
-- -- FROM EmptyCellsEnrollment d_empty
-- -- JOIN 
-- --     temp_session_info tsi ON 1=1;

--  SELECT 
--     lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(6))) AS orchestration_session_issue_id,
--     tsi.orchestration_session_id,
--     tsi.orchestration_session_entry_id,
--     d_empty.heading AS issue_type,
--     d_empty.status AS issue_message,
--     d_empty.issue_row AS issue_row,
--     d_empty.column_name AS issue_column,
--     NULL AS invalid_value,
--     d_empty.remediation AS remediation,
--     NULL AS elaboration
-- FROM EmptyCellsEnrollment d_empty;


-- Update orchestration_session to set finished timestamp and diagnostics
UPDATE orchestration_session
SET 
    orch_finished_at = CURRENT_TIMESTAMP,             -- Set the finish time
    diagnostics_json = '{"status": "completed"}',     -- Diagnostics status in JSON format
    diagnostics_md = 'Verification Validation process completed'  -- Markdown summary
WHERE orchestration_session_id = (SELECT orchestration_session_id FROM temp_session_info LIMIT 1);  -- Update the session identified in the temp view




--Sqlpage display db views-----------------------------------------------

-- Drop and recreate the device view
-- This view contains the basic information about devices used in the system.
DROP VIEW IF EXISTS drh_device;
CREATE VIEW drh_device AS
SELECT device_id, name, created_at
FROM device d;

-- Drop and recreate the number_of_files_converted view
-- This view calculates the total number of files that have been converted,
-- excluding those with a placeholder content_digest.
DROP VIEW IF EXISTS drh_number_of_files_converted;
CREATE VIEW drh_number_of_files_converted AS
SELECT COUNT(*) AS file_count
FROM uniform_resource
WHERE content_digest != '-';

-- Drop and recreate the converted_files_list view
-- This view lists all converted files based on their file extensions.
DROP VIEW IF EXISTS drh_converted_files_list;
CREATE VIEW drh_converted_files_list AS
SELECT file_basename
FROM ur_ingest_session_fs_path_entry
WHERE file_extn IN ('csv', 'xls', 'xlsx', 'json', 'html');

-- Drop and recreate the converted_table_list view
-- This view retrieves the names of all converted tables, filtering out
-- certain specific tables from the results.
DROP VIEW IF EXISTS drh_converted_table_list;
CREATE VIEW drh_converted_table_list AS
SELECT tbl_name AS table_name
FROM sqlite_master
WHERE type = 'table'
  AND name LIKE 'uniform_resource%'
  AND name != 'uniform_resource_transform'
  AND name != 'uniform_resource';

-- Drop and recreate the study files table info view
-- This view provides detailed information about study files, including 
-- their formats and relative file names. It joins multiple tables to gather
-- comprehensive details.
DROP VIEW IF EXISTS drh_study_files_table_info;
CREATE VIEW IF NOT EXISTS drh_study_files_table_info AS
       SELECT ur.uniform_resource_id,
              ur.nature AS file_format,
              SUBSTR(pe.file_path_rel, INSTR(pe.file_path_rel, '/') + 1, INSTR(pe.file_path_rel, '.') - INSTR(pe.file_path_rel, '/') - 1) as file_name,
              'uniform_resource_' || SUBSTR(pe.file_path_rel, INSTR(pe.file_path_rel, '/') + 1, INSTR(pe.file_path_rel, '.') - INSTR(pe.file_path_rel, '/') - 1) AS table_name
FROM uniform_resource ur
LEFT JOIN ur_ingest_session_fs_path p ON ur.ingest_fs_path_id = p.ur_ingest_session_fs_path_id
LEFT JOIN ur_ingest_session_fs_path_entry pe ON ur.uniform_resource_id = pe.uniform_resource_id
WHERE ur.ingest_fs_path_id IS NOT NULL;

-- Create a view to display the status of files transformed during the ingestion sessions
DROP VIEW IF EXISTS drh_vw_ingest_session_entries_status;
CREATE VIEW drh_vw_ingest_session_entries_status AS
SELECT
    isession.ur_ingest_session_id,
    isession.device_id,
    isession.behavior_id,
    isession.behavior_json,
    isession.ingest_started_at,
    isession.ingest_finished_at,
    isession.session_agent,    
    isession.created_at AS session_created_at,
    isession.created_by AS session_created_by,
    isession.updated_at AS session_updated_at,
    isession.updated_by AS session_updated_by,
    isession.deleted_at AS session_deleted_at,
    isession.deleted_by AS session_deleted_by,
    isession.activity_log AS session_activity_log,
    fspath.ur_ingest_session_fs_path_id,
    fspath.ingest_session_id AS fspath_ingest_session_id,
    fspath.root_path,    
    fspath.created_at AS fspath_created_at,
    fspath.created_by AS fspath_created_by,
    fspath.updated_at AS fspath_updated_at,
    fspath.updated_by AS fspath_updated_by,
    fspath.deleted_at AS fspath_deleted_at,
    fspath.deleted_by AS fspath_deleted_by,
    fspath.activity_log AS fspath_activity_log,
    entry.ur_ingest_session_fs_path_entry_id,
    entry.ingest_session_id AS entry_ingest_session_id,
    entry.ingest_fs_path_id,
    entry.uniform_resource_id,
    entry.file_path_abs,
    entry.file_path_rel_parent,
    entry.file_path_rel,
    entry.file_basename,
    entry.file_extn,
    entry.captured_executable,
    entry.ur_status,
    entry.ur_diagnostics,
    entry.ur_transformations,    
    entry.created_at AS entry_created_at,
    entry.created_by AS entry_created_by,
    entry.updated_at AS entry_updated_at,
    entry.updated_by AS entry_updated_by,
    entry.deleted_at AS entry_deleted_at,
    entry.deleted_by AS entry_deleted_by,
    entry.activity_log AS entry_activity_log
FROM
    ur_ingest_session isession
    JOIN ur_ingest_session_fs_path fspath ON isession.ur_ingest_session_id = fspath.ingest_session_id
    JOIN ur_ingest_session_fs_path_entry entry ON fspath.ur_ingest_session_fs_path_id = entry.ingest_fs_path_id;

-- Orchestration views-----------------------------------------------------------------------

-- Drop and recreate the orchestration session view
-- This view summarizes the orchestration session details for monitoring purposes.
DROP VIEW IF EXISTS drh_orch_session_view;
CREATE VIEW drh_orch_session_view AS
SELECT
    orchestration_session_id, device_id, orchestration_nature_id,
    version, orch_started_at, orch_finished_at,
    diagnostics_json, diagnostics_md
FROM orchestration_session;

-- Drop and recreate the deidentification orchestration session view
-- This view specifically filters orchestration sessions related to deidentification.
DROP VIEW IF EXISTS drh_orch_session_deidentifyview;
CREATE VIEW drh_orch_session_deidentifyview AS
SELECT
    orchestration_session_id, device_id, orchestration_nature_id,
    version, orch_started_at, orch_finished_at,
    diagnostics_json, diagnostics_md
FROM orchestration_session
WHERE orchestration_nature_id = 'deidentification';

-- Drop and recreate the orchestration session entry view
-- This view lists details about individual entries within orchestration sessions.
DROP VIEW IF EXISTS drh_orchestration_session_entry_view;
CREATE VIEW drh_orchestration_session_entry_view AS
SELECT
    orchestration_session_entry_id, session_id, ingest_src, ingest_table_name
FROM orchestration_session_entry;

-- Drop and recreate the orchestration session execution view
-- This view captures execution details of orchestration sessions for auditing.
DROP VIEW IF EXISTS drh_orchestration_session_exec_view;
CREATE VIEW drh_orchestration_session_exec_view AS
SELECT
    orchestration_session_exec_id, exec_nature, session_id, session_entry_id,
    parent_exec_id, namespace, exec_identity, exec_code, exec_status,
    input_text, exec_error_text, output_text, output_nature, narrative_md
FROM orchestration_session_exec;

-- Drop and recreate the orchestration deidentification view
-- This view aggregates information from orchestration session executions related to deidentification.
DROP VIEW IF EXISTS drh_vw_orchestration_deidentify;
CREATE VIEW drh_vw_orchestration_deidentify AS
SELECT
    osex.orchestration_session_exec_id,
    osex.exec_nature,
    osex.session_id,
    osex.session_entry_id,
    osex.parent_exec_id,
    osex.namespace,
    osex.exec_identity,
    osex.exec_code,
    osex.exec_status,
    osex.input_text,
    osex.exec_error_text,
    osex.output_text,
    osex.output_nature,
    osex.narrative_md,    
    os.device_id,
    os.orchestration_nature_id,
    os.version,
    os.orch_started_at,
    os.orch_finished_at,    
    os.args_json,
    os.diagnostics_json,
    os.diagnostics_md
FROM
    orchestration_session_exec osex
    JOIN orchestration_session os ON osex.session_id = os.orchestration_session_id
WHERE
    os.orchestration_nature_id = 'deidentification';

-- Drop and recreate the V&V orchestration issues view
-- This view summarizes the issues encountered during validation and verification
-- of orchestration sessions, providing useful diagnostics.
DROP VIEW IF EXISTS drh_vandv_orch_issues;
CREATE VIEW drh_vandv_orch_issues AS
SELECT    
    osi.issue_type AS 'Issue Type',
    osi.issue_message AS 'Issue Message',
    osi.issue_column AS 'Issue Column',
    osi.remediation AS 'Remediation',
    osi.issue_row AS 'Issue Row',    
    osi.invalid_value AS 'Invalid Value'  
FROM
    orchestration_session_issue osi
JOIN
    orchestration_session os
ON
    osi.session_id = os.orchestration_session_id
WHERE
    os.orchestration_nature_id = 'V&V';


----------------------DRH specific views------------------------------------------------------
-- Drop and recreate the study view to consolidate study details
DROP VIEW IF EXISTS drh_study;
CREATE VIEW drh_study AS
SELECT
    study_id, study_name, start_date, end_date, treatment_modalities,
    funding_source, nct_number, study_description
FROM uniform_resource_study;

-- Drop and recreate the CGM file metadata view for easier access to file-related information
DROP VIEW IF EXISTS drh_cgmfilemetadata_view;
CREATE VIEW drh_cgmfilemetadata_view AS
SELECT
    metadata_id, devicename, device_id, source_platform, patient_id,
    file_name, file_format, file_upload_date, data_start_date,
    data_end_date, study_id
FROM uniform_resource_cgm_file_metadata;

-- Drop and recreate the author view to manage author details related to studies
DROP VIEW IF EXISTS drh_author;
CREATE VIEW drh_author AS
SELECT
    author_id, name, email, investigator_id, study_id
FROM uniform_resource_author;

-- Drop and recreate the institution view for organizing institution-related data
DROP VIEW IF EXISTS drh_institution;
CREATE VIEW drh_institution AS
SELECT
    institution_id, institution_name, city, state, country
FROM uniform_resource_institution;

-- Drop and recreate the investigator view to manage investigator details associated with studies
DROP VIEW IF EXISTS drh_investigator;
CREATE VIEW drh_investigator AS
SELECT
    investigator_id, investigator_name, email, institution_id, study_id
FROM uniform_resource_investigator;

-- Drop and recreate the lab view to consolidate laboratory information
DROP VIEW IF EXISTS drh_lab;
CREATE VIEW drh_lab AS
SELECT
    lab_id, lab_name, lab_pi, institution_id, study_id
FROM uniform_resource_lab;

-- Drop and recreate the publication view for managing publication details related to studies
DROP VIEW IF EXISTS drh_publication;
CREATE VIEW drh_publication AS
SELECT
    publication_id, publication_title, digital_object_identifier,
    publication_site, study_id
FROM uniform_resource_publication;

-- Drop and recreate the site view to maintain site-related data for studies
DROP VIEW IF EXISTS drh_site;
CREATE VIEW drh_site AS
SELECT
    study_id, site_id, site_name, site_type
FROM uniform_resource_site;

--- Create a comprehensive study-participant dashboard view
DROP VIEW IF EXISTS drh_study_vanity_metrics_details;
CREATE VIEW drh_study_vanity_metrics_details AS
SELECT s.study_id, 
       s.study_name, 
       s.study_description, 
       s.start_date, 
       s.end_date, 
       s.nct_number, 
       COUNT(DISTINCT p.participant_id) AS total_number_of_participants, 
       ROUND(AVG(p.age), 2) AS average_age, 
       (CAST(SUM(CASE WHEN p.gender = 'F' THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*)) * 100 AS percentage_of_females, 
       GROUP_CONCAT(DISTINCT i.investigator_name) AS investigators 
FROM uniform_resource_study s 
LEFT JOIN drh_participant p ON s.study_id = p.study_id
LEFT JOIN uniform_resource_investigator i ON s.study_id = i.study_id 
GROUP BY s.study_id, s.study_name, s.study_description, s.start_date, s.end_date, s.nct_number;


-- View to count the number of files for each device in the CGM file metadata
DROP VIEW IF EXISTS drh_device_file_count_view;
CREATE VIEW drh_device_file_count_view AS
SELECT 
    devicename, 
    COUNT(DISTINCT file_name) AS number_of_files
FROM 
    uniform_resource_cgm_file_metadata
GROUP BY 
    devicename
ORDER BY 
    number_of_files DESC;

-- Create a temporary table to cache the list of raw CGM tables
DROP TABLE IF EXISTS raw_cgm_lst_cached;
CREATE TABLE raw_cgm_lst_cached AS 
  SELECT * FROM drh_raw_cgm_table_lst;

------------- Dynamically insert the SQLPage configurations for CGM raw tables --------------------------

WITH raw_cgm_table_name AS (
    -- Select all table names from the cached list of raw CGM tables
    SELECT table_name
    FROM drh_raw_cgm_table_lst
)
INSERT OR IGNORE INTO sqlpage_files (path, contents)
SELECT 
    'drh/cgm-data/raw-cgm/' || table_name||'.sql' AS path,
    '
    SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
    -- Not including breadcrumbs from sqlpage_aide_navigation
    -- Not including page title from sqlpage_aide_navigation

    SELECT ''breadcrumb'' AS component;
    WITH RECURSIVE breadcrumbs AS (
        SELECT
            COALESCE(abbreviated_caption, caption) AS title,
            COALESCE(url, path) AS link,
            parent_path, 0 AS level,
            namespace
        FROM sqlpage_aide_navigation
        WHERE namespace = ''prime'' AND path = ''/drh/cgm-data''
        UNION ALL
        SELECT
            COALESCE(nav.abbreviated_caption, nav.caption) AS title,
            COALESCE(nav.url, nav.path) AS link,
            nav.parent_path, b.level + 1, nav.namespace
        FROM sqlpage_aide_navigation nav
        INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
    )
    SELECT title, link FROM breadcrumbs ORDER BY level DESC;
    SELECT ''' || table_name || ''' || '' Table'' AS title, ''#'' AS link;
    
    SELECT ''title'' AS component, ''' || table_name || ''' AS contents;
    

    -- Initialize pagination parameters
    SET total_rows = (SELECT COUNT(*) FROM ''' || table_name || ''');  -- Total rows in the current table
    SET limit = COALESCE($limit, 50);  -- Limit for pagination, defaulting to 50
    SET offset = COALESCE($offset, 0);  -- Offset for pagination, defaulting to 0
    SET total_pages = ($total_rows + $limit - 1) / $limit;  -- Calculate total number of pages
    SET current_page = ($offset / $limit) + 1;  -- Calculate current page number

    -- Display table with pagination
    SELECT ''table'' AS component,
        TRUE AS sort,  -- Enable sorting
        TRUE AS search;  -- Enable searching
    SELECT * FROM ''' || table_name || '''
    LIMIT $limit
    OFFSET $offset;    

    -- Pagination controls for navigating through pages
    SELECT ''text'' AS component,
        (SELECT CASE WHEN $current_page > 1 THEN ''[Previous](?limit='' || $limit || ''&offset='' || ($offset - $limit) || '')'' ELSE '''' END) || '' '' ||
        ''(Page '' || $current_page || '' of '' || $total_pages || '')'' || '' '' ||
        (SELECT CASE WHEN $current_page < $total_pages THEN ''[Next](?limit='' || $limit || ''&offset='' || ($offset + $limit) || '')'' ELSE '''' END)
        AS contents_md;
    '
FROM raw_cgm_table_name;

-- code provenance: `ConsoleSqlPages.infoSchemaDDL` (file:///home/runner/work/www.surveilr.com/www.surveilr.com/lib/std/web-ui-content/console.ts)

-- console_information_schema_* are convenience views
-- to make it easier to work than pragma_table_info.

DROP VIEW IF EXISTS console_information_schema_table;
CREATE VIEW console_information_schema_table AS
SELECT
    tbl.name AS table_name,
    col.name AS column_name,
    col.type AS data_type,
    CASE WHEN col.pk = 1 THEN 'Yes' ELSE 'No' END AS is_primary_key,
    CASE WHEN col."notnull" = 1 THEN 'Yes' ELSE 'No' END AS is_not_null,
    col.dflt_value AS default_value,
    '/console/info-schema/table.sql?name=' || tbl.name || '&stats=yes' as info_schema_web_ui_path,
    '[Content](/console/info-schema/table.sql?name=' || tbl.name || '&stats=yes)' as info_schema_link_abbrev_md,
    '[' || tbl.name || ' (table) Schema](/console/info-schema/table.sql?name=' || tbl.name || '&stats=yes)' as info_schema_link_full_md,
    '/console/content/table/' || tbl.name || '.sql?stats=yes' as content_web_ui_path,
    '[Content](/console/content/table/' || tbl.name || '.sql?stats=yes)' as content_web_ui_link_abbrev_md,
    '[' || tbl.name || ' (table) Content](/console/content/table/' || tbl.name || '.sql?stats=yes)' as content_web_ui_link_full_md,
    tbl.sql as sql_ddl
FROM sqlite_master tbl
JOIN pragma_table_info(tbl.name) col
WHERE tbl.type = 'table' AND tbl.name NOT LIKE 'sqlite_%';

-- Populate the table with view-specific information
DROP VIEW IF EXISTS console_information_schema_view;
CREATE VIEW console_information_schema_view AS
SELECT
    vw.name AS view_name,
    col.name AS column_name,
    col.type AS data_type,
    '/console/info-schema/view.sql?name=' || vw.name || '&stats=yes' as info_schema_web_ui_path,
    '[Content](/console/info-schema/view.sql?name=' || vw.name || '&stats=yes)' as info_schema_link_abbrev_md,
    '[' || vw.name || ' (view) Schema](/console/info-schema/view.sql?name=' || vw.name || '&stats=yes)' as info_schema_link_full_md,
    '/console/content/view/' || vw.name || '.sql?stats=yes' as content_web_ui_path,
    '[Content](/console/content/view/' || vw.name || '.sql?stats=yes)' as content_web_ui_link_abbrev_md,
    '[' || vw.name || ' (view) Content](/console/content/view/' || vw.name || '.sql?stats=yes)' as content_web_ui_link_full_md,
    vw.sql as sql_ddl
FROM sqlite_master vw
JOIN pragma_table_info(vw.name) col
WHERE vw.type = 'view' AND vw.name NOT LIKE 'sqlite_%';

DROP VIEW IF EXISTS console_content_tabular;
CREATE VIEW console_content_tabular AS
  SELECT 'table' as tabular_nature,
         table_name as tabular_name,
         info_schema_web_ui_path,
         info_schema_link_abbrev_md,
         info_schema_link_full_md,
         content_web_ui_path,
         content_web_ui_link_abbrev_md,
         content_web_ui_link_full_md
    FROM console_information_schema_table
  UNION ALL
  SELECT 'view' as tabular_nature,
         view_name as tabular_name,
         info_schema_web_ui_path,
         info_schema_link_abbrev_md,
         info_schema_link_full_md,
         content_web_ui_path,
         content_web_ui_link_abbrev_md,
         content_web_ui_link_full_md
    FROM console_information_schema_view;

-- Populate the table with table column foreign keys
DROP VIEW IF EXISTS console_information_schema_table_col_fkey;
CREATE VIEW console_information_schema_table_col_fkey AS
SELECT
    tbl.name AS table_name,
    f."from" AS column_name,
    f."from" || ' references ' || f."table" || '.' || f."to" AS foreign_key
FROM sqlite_master tbl
JOIN pragma_foreign_key_list(tbl.name) f
WHERE tbl.type = 'table' AND tbl.name NOT LIKE 'sqlite_%';

-- Populate the table with table column indexes
DROP VIEW IF EXISTS console_information_schema_table_col_index;
CREATE VIEW console_information_schema_table_col_index AS
SELECT
    tbl.name AS table_name,
    pi.name AS column_name,
    idx.name AS index_name
FROM sqlite_master tbl
JOIN pragma_index_list(tbl.name) idx
JOIN pragma_index_info(idx.name) pi
WHERE tbl.type = 'table' AND tbl.name NOT LIKE 'sqlite_%';

-- Drop and create the table for storing navigation entries
-- for testing only: DROP TABLE IF EXISTS sqlpage_aide_navigation;
CREATE TABLE IF NOT EXISTS sqlpage_aide_navigation (
    path TEXT NOT NULL, -- the "primary key" within namespace
    caption TEXT NOT NULL, -- for human-friendly general-purpose name
    namespace TEXT NOT NULL, -- if more than one navigation tree is required
    parent_path TEXT, -- for defining hierarchy
    sibling_order INTEGER, -- orders children within their parent(s)
    url TEXT, -- for supplying links, if different from path
    title TEXT, -- for full titles when elaboration is required, default to caption if NULL
    abbreviated_caption TEXT, -- for breadcrumbs and other "short" form, default to caption if NULL
    description TEXT, -- for elaboration or explanation
    elaboration TEXT, -- optional attributes for e.g. { "target": "__blank" }
    -- TODO: figure out why Rusqlite does not allow this but sqlite3 does
    -- CONSTRAINT fk_parent_path FOREIGN KEY (namespace, parent_path) REFERENCES sqlpage_aide_navigation(namespace, path),
    CONSTRAINT unq_ns_path UNIQUE (namespace, parent_path, path)
);
DELETE FROM sqlpage_aide_navigation WHERE path LIKE '/console/%';
DELETE FROM sqlpage_aide_navigation WHERE path LIKE '/';

-- all @navigation decorated entries are automatically added to this.navigation
INSERT INTO sqlpage_aide_navigation (namespace, parent_path, sibling_order, path, url, caption, abbreviated_caption, title, description,elaboration)
VALUES
    ('prime', NULL, 1, '/', '/', 'Home', NULL, 'Resource Surveillance State Database (RSSD)', 'Welcome to Resource Surveillance State Database (RSSD)', NULL),
    ('prime', '/', 999, '/console', '/console/', 'RSSD Console', 'Console', 'Resource Surveillance State Database (RSSD) Console', 'Explore RSSD information schema, code notebooks, and SQLPage files', NULL),
    ('prime', '/console', 1, '/console/info-schema', '/console/info-schema/', 'RSSD Information Schema', 'Info Schema', NULL, 'Explore RSSD tables, columns, views, and other information schema documentation', NULL),
    ('prime', '/console', 3, '/console/sqlpage-files', '/console/sqlpage-files/', 'RSSD SQLPage Files', 'SQLPage Files', NULL, 'Explore RSSD SQLPage Files which govern the content of the web-UI', NULL),
    ('prime', '/console', 3, '/console/sqlpage-files/content.sql', '/console/sqlpage-files/content.sql', 'RSSD Data Tables Content SQLPage Files', 'Content SQLPage Files', NULL, 'Explore auto-generated RSSD SQLPage Files which display content within tables', NULL),
    ('prime', '/console', 3, '/console/sqlpage-nav', '/console/sqlpage-nav/', 'RSSD SQLPage Navigation', 'SQLPage Navigation', NULL, 'See all the navigation entries for the web-UI; TODO: need to improve this to be able to get details for each navigation entry as a table', NULL),
    ('prime', '/console', 2, '/console/notebooks', '/console/notebooks/', 'RSSD Code Notebooks', 'Code Notebooks', NULL, 'Explore RSSD Code Notebooks which contain reusable SQL and other code blocks', NULL)
ON CONFLICT (namespace, parent_path, path)
DO UPDATE SET title = EXCLUDED.title, abbreviated_caption = EXCLUDED.abbreviated_caption, description = EXCLUDED.description, url = EXCLUDED.url, sibling_order = EXCLUDED.sibling_order;

INSERT OR REPLACE INTO code_notebook_cell (notebook_kernel_id, code_notebook_cell_id, notebook_name, cell_name, interpretable_code, interpretable_code_hash, description) VALUES (
  'SQL',
  'web-ui.auto_generate_console_content_tabular_sqlpage_files',
  'Web UI',
  'auto_generate_console_content_tabular_sqlpage_files',
  '      -- code provenance: `ConsoleSqlPages.infoSchemaContentDML` (file:///home/runner/work/www.surveilr.com/www.surveilr.com/lib/std/web-ui-content/console.ts)

      -- the "auto-generated" tables will be in ''*.auto.sql'' with redirects
      DELETE FROM sqlpage_files WHERE path like ''console/content/table/%.auto.sql'';
      DELETE FROM sqlpage_files WHERE path like ''console/content/view/%.auto.sql'';
      INSERT OR REPLACE INTO sqlpage_files (path, contents)
        SELECT
            ''console/content/'' || tabular_nature || ''/'' || tabular_name || ''.auto.sql'',
            ''SELECT ''''dynamic'''' AS component, sqlpage.run_sql(''''shell/shell.sql'''') AS properties;

              SELECT ''''breadcrumb'''' AS component;
              SELECT ''''Home'''' as title, ''''/'''' AS link;
              SELECT ''''Console'''' as title, ''''/console'''' AS link;
              SELECT ''''Content'''' as title, ''''/console/content'''' AS link;
              SELECT '''''' || tabular_name  || '' '' || tabular_nature || '''''' as title, ''''#'''' AS link;

              SELECT ''''title'''' AS component, '''''' || tabular_name || '' ('' || tabular_nature || '') Content'''' as contents;

              SET total_rows = (SELECT COUNT(*) FROM '' || tabular_name || '');
              SET limit = COALESCE($limit, 50);
              SET offset = COALESCE($offset, 0);
              SET total_pages = ($total_rows + $limit - 1) / $limit;
              SET current_page = ($offset / $limit) + 1;

              SELECT ''''text'''' AS component, '''''' || info_schema_link_full_md || '''''' AS contents_md
              SELECT ''''text'''' AS component,
                ''''- Start Row: '''' || $offset || ''''
'''' ||
                ''''- Rows per Page: '''' || $limit || ''''
'''' ||
                ''''- Total Rows: '''' || $total_rows || ''''
'''' ||
                ''''- Current Page: '''' || $current_page || ''''
'''' ||
                ''''- Total Pages: '''' || $total_pages as contents_md
              WHERE $stats IS NOT NULL;

              -- Display uniform_resource table with pagination
              SELECT ''''table'''' AS component,
                    TRUE AS sort,
                    TRUE AS search,
                    TRUE AS hover,
                    TRUE AS striped_rows,
                    TRUE AS small;
            SELECT * FROM '' || tabular_name || ''
            LIMIT $limit
            OFFSET $offset;

            SELECT ''''text'''' AS component,
                (SELECT CASE WHEN $current_page > 1 THEN ''''[Previous](?limit='''' || $limit || ''''&offset='''' || ($offset - $limit) || '''')'''' ELSE '''''''' END) || '''' '''' ||
                ''''(Page '''' || $current_page || '''' of '''' || $total_pages || '''') '''' ||
                (SELECT CASE WHEN $current_page < $total_pages THEN ''''[Next](?limit='''' || $limit || ''''&offset='''' || ($offset + $limit) || '''')'''' ELSE '''''''' END)
                AS contents_md;''
        FROM console_content_tabular;

      INSERT OR IGNORE INTO sqlpage_files (path, contents)
        SELECT
            ''console/content/'' || tabular_nature || ''/'' || tabular_name || ''.sql'',
            ''SELECT ''''redirect'''' AS component, ''''/console/content/'' || tabular_nature || ''/'' || tabular_name || ''.auto.sql'''' AS link WHERE $stats IS NULL;
'' ||
            ''SELECT ''''redirect'''' AS component, ''''/console/content/'' || tabular_nature || ''/'' || tabular_name || ''.auto.sql?stats='''' || $stats AS link WHERE $stats IS NOT NULL;''
        FROM console_content_tabular;

      -- TODO: add ${this.upsertNavSQL(...)} if we want each of the above to be navigable through DB rows',
  'TODO',
  'A series of idempotent INSERT statements which will auto-generate "default" content for all tables and views'
);
      -- code provenance: `ConsoleSqlPages.infoSchemaContentDML` (file:///home/runner/work/www.surveilr.com/www.surveilr.com/lib/std/web-ui-content/console.ts)

      -- the "auto-generated" tables will be in '*.auto.sql' with redirects
      DELETE FROM sqlpage_files WHERE path like 'console/content/table/%.auto.sql';
      DELETE FROM sqlpage_files WHERE path like 'console/content/view/%.auto.sql';
      INSERT OR REPLACE INTO sqlpage_files (path, contents)
        SELECT
            'console/content/' || tabular_nature || '/' || tabular_name || '.auto.sql',
            'SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;

              SELECT ''breadcrumb'' AS component;
              SELECT ''Home'' as title, ''/'' AS link;
              SELECT ''Console'' as title, ''/console'' AS link;
              SELECT ''Content'' as title, ''/console/content'' AS link;
              SELECT ''' || tabular_name  || ' ' || tabular_nature || ''' as title, ''#'' AS link;

              SELECT ''title'' AS component, ''' || tabular_name || ' (' || tabular_nature || ') Content'' as contents;

              SET total_rows = (SELECT COUNT(*) FROM ' || tabular_name || ');
              SET limit = COALESCE($limit, 50);
              SET offset = COALESCE($offset, 0);
              SET total_pages = ($total_rows + $limit - 1) / $limit;
              SET current_page = ($offset / $limit) + 1;

              SELECT ''text'' AS component, ''' || info_schema_link_full_md || ''' AS contents_md
              SELECT ''text'' AS component,
                ''- Start Row: '' || $offset || ''
'' ||
                ''- Rows per Page: '' || $limit || ''
'' ||
                ''- Total Rows: '' || $total_rows || ''
'' ||
                ''- Current Page: '' || $current_page || ''
'' ||
                ''- Total Pages: '' || $total_pages as contents_md
              WHERE $stats IS NOT NULL;

              -- Display uniform_resource table with pagination
              SELECT ''table'' AS component,
                    TRUE AS sort,
                    TRUE AS search,
                    TRUE AS hover,
                    TRUE AS striped_rows,
                    TRUE AS small;
            SELECT * FROM ' || tabular_name || '
            LIMIT $limit
            OFFSET $offset;

            SELECT ''text'' AS component,
                (SELECT CASE WHEN $current_page > 1 THEN ''[Previous](?limit='' || $limit || ''&offset='' || ($offset - $limit) || '')'' ELSE '''' END) || '' '' ||
                ''(Page '' || $current_page || '' of '' || $total_pages || '') '' ||
                (SELECT CASE WHEN $current_page < $total_pages THEN ''[Next](?limit='' || $limit || ''&offset='' || ($offset + $limit) || '')'' ELSE '''' END)
                AS contents_md;'
        FROM console_content_tabular;

      INSERT OR IGNORE INTO sqlpage_files (path, contents)
        SELECT
            'console/content/' || tabular_nature || '/' || tabular_name || '.sql',
            'SELECT ''redirect'' AS component, ''/console/content/' || tabular_nature || '/' || tabular_name || '.auto.sql'' AS link WHERE $stats IS NULL;
' ||
            'SELECT ''redirect'' AS component, ''/console/content/' || tabular_nature || '/' || tabular_name || '.auto.sql?stats='' || $stats AS link WHERE $stats IS NOT NULL;'
        FROM console_content_tabular;

      -- TODO: add ${this.upsertNavSQL(...)} if we want each of the above to be navigable through DB rows
-- delete all /fhir-related entries and recreate them in case routes are changed
DELETE FROM sqlpage_aide_navigation WHERE path like '/fhir%';
INSERT INTO sqlpage_aide_navigation (namespace, parent_path, sibling_order, path, url, caption, abbreviated_caption, title, description,elaboration)
VALUES
    ('prime', '/', 1, '/ur', '/ur/', 'Uniform Resource', NULL, NULL, 'Explore ingested resources', NULL),
    ('prime', '/ur', 99, '/ur/info-schema.sql', '/ur/info-schema.sql', 'Uniform Resource Tables and Views', NULL, NULL, 'Information Schema documentation for ingested Uniform Resource database objects', NULL),
    ('prime', '/ur', 1, '/ur/uniform-resource-files.sql', '/ur/uniform-resource-files.sql', 'Uniform Resources (Files)', NULL, NULL, 'Files ingested into the `uniform_resource` table', NULL)
ON CONFLICT (namespace, parent_path, path)
DO UPDATE SET title = EXCLUDED.title, abbreviated_caption = EXCLUDED.abbreviated_caption, description = EXCLUDED.description, url = EXCLUDED.url, sibling_order = EXCLUDED.sibling_order;
DROP VIEW IF EXISTS uniform_resource_file;
CREATE VIEW uniform_resource_file AS
  SELECT ur.uniform_resource_id,
         ur.nature,
         p.root_path AS source_path,
         pe.file_path_rel,
         ur.size_bytes
  FROM uniform_resource ur
  LEFT JOIN ur_ingest_session_fs_path p ON ur.ingest_fs_path_id = p.ur_ingest_session_fs_path_id
  LEFT JOIN ur_ingest_session_fs_path_entry pe ON ur.uniform_resource_id = pe.uniform_resource_id
  WHERE ur.ingest_fs_path_id IS NOT NULL;
INSERT INTO sqlpage_aide_navigation (namespace, parent_path, sibling_order, path, url, caption, abbreviated_caption, title, description,elaboration)
VALUES
    ('prime', '/', 1, '/orchestration', '/orchestration/', 'Orchestration', NULL, NULL, 'Explore details about all orchestration', NULL),
    ('prime', '/orchestration', 99, '/orchestration/info-schema.sql', '/orchestration/info-schema.sql', 'Orchestration Tables and Views', NULL, NULL, 'Information Schema documentation for orchestrated objects', NULL)
ON CONFLICT (namespace, parent_path, path)
DO UPDATE SET title = EXCLUDED.title, abbreviated_caption = EXCLUDED.abbreviated_caption, description = EXCLUDED.description, url = EXCLUDED.url, sibling_order = EXCLUDED.sibling_order;
 DROP VIEW IF EXISTS orchestration_session_by_device;
 CREATE VIEW orchestration_session_by_device AS
 SELECT
     d.device_id,
     d.name AS device_name,
     COUNT(*) AS session_count
 FROM orchestration_session os
 JOIN device d ON os.device_id = d.device_id
 GROUP BY d.device_id, d.name;

 DROP VIEW IF EXISTS orchestration_session_duration;
 CREATE VIEW orchestration_session_duration AS
 SELECT
     os.orchestration_session_id,
     onature.nature AS orchestration_nature,
     os.orch_started_at,
     os.orch_finished_at,
     (JULIANDAY(os.orch_finished_at) - JULIANDAY(os.orch_started_at)) * 24 * 60 * 60 AS duration_seconds
 FROM orchestration_session os
 JOIN orchestration_nature onature ON os.orchestration_nature_id = onature.orchestration_nature_id
 WHERE os.orch_finished_at IS NOT NULL;

 DROP VIEW IF EXISTS orchestration_success_rate;
 CREATE VIEW orchestration_success_rate AS
 SELECT
     onature.nature AS orchestration_nature,
     COUNT(*) AS total_sessions,
     SUM(CASE WHEN oss.to_state = 'surveilr_orch_completed' THEN 1 ELSE 0 END) AS successful_sessions,
     (CAST(SUM(CASE WHEN oss.to_state = 'surveilr_orch_completed' THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*)) * 100 AS success_rate
 FROM orchestration_session os
 JOIN orchestration_nature onature ON os.orchestration_nature_id = onature.orchestration_nature_id
 JOIN orchestration_session_state oss ON os.orchestration_session_id = oss.session_id
 WHERE oss.to_state IN ('surveilr_orch_completed', 'surveilr_orch_failed') -- Consider other terminal states if applicable
 GROUP BY onature.nature;

 DROP VIEW IF EXISTS orchestration_session_script;
 CREATE VIEW orchestration_session_script AS
 SELECT
     os.orchestration_session_id,
     onature.nature AS orchestration_nature,
     COUNT(*) AS script_count
 FROM orchestration_session os
 JOIN orchestration_nature onature ON os.orchestration_nature_id = onature.orchestration_nature_id
 JOIN orchestration_session_entry ose ON os.orchestration_session_id = ose.session_id
 GROUP BY os.orchestration_session_id, onature.nature;

 DROP VIEW IF EXISTS orchestration_executions_by_type;
 CREATE VIEW orchestration_executions_by_type AS
 SELECT
     exec_nature,
     COUNT(*) AS execution_count
 FROM orchestration_session_exec
 GROUP BY exec_nature;

 DROP VIEW IF EXISTS orchestration_execution_success_rate_by_type;
 CREATE VIEW orchestration_execution_success_rate_by_type AS
 SELECT
     exec_nature,
     COUNT(*) AS total_executions,
     SUM(CASE WHEN exec_status = 0 THEN 1 ELSE 0 END) AS successful_executions,
     (CAST(SUM(CASE WHEN exec_status = 0 THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*)) * 100 AS success_rate
 FROM orchestration_session_exec
 GROUP BY exec_nature;

 DROP VIEW IF EXISTS orchestration_session_summary;
 CREATE VIEW orchestration_session_summary AS
 SELECT
     issue_type,
     COUNT(*) AS issue_count
 FROM orchestration_session_issue
 GROUP BY issue_type;

 DROP VIEW IF EXISTS orchestration_issue_remediation;
 CREATE VIEW orchestration_issue_remediation AS
 SELECT
     orchestration_session_issue_id,
     issue_type,
     issue_message,
     remediation
 FROM orchestration_session_issue
 WHERE remediation IS NOT NULL;

DROP VIEW IF EXISTS orchestration_logs_by_session;
 CREATE VIEW orchestration_logs_by_session AS
 SELECT
     os.orchestration_session_id,
     onature.nature AS orchestration_nature,
     osl.category,
     COUNT(*) AS log_count
 FROM orchestration_session os
 JOIN orchestration_nature onature ON os.orchestration_nature_id = onature.orchestration_nature_id
 JOIN orchestration_session_exec ose ON os.orchestration_session_id = ose.session_id
 JOIN orchestration_session_log osl ON ose.orchestration_session_exec_id = osl.parent_exec_id
 GROUP BY os.orchestration_session_id, onature.nature, osl.category;
-- delete all /drh-related entries and recreate them in case routes are changed
DELETE FROM sqlpage_aide_navigation WHERE path like '/drh%';
INSERT INTO sqlpage_aide_navigation (namespace, parent_path, sibling_order, path, url, caption, abbreviated_caption, title, description,elaboration)
VALUES
    ('prime', '/', 1, '/drh', '/drh/', 'DRH EDGE UI Home', NULL, NULL, 'Welcome to Diabetes Research Hub EDGE UI', NULL),
    ('prime', '/drh', 4, '/drh/researcher-related-data', '/drh/researcher-related-data/', 'Researcher And Associated Information', 'Researcher And Associated Information', NULL, 'Researcher And Associated Information', NULL),
    ('prime', '/drh', 5, '/drh/study-related-data', '/drh/study-related-data/', 'Study and Participant Information', 'Study and Participant Information', NULL, 'Study and Participant Information', NULL),
    ('prime', '/drh', 6, '/drh/uniform-resource-participant.sql', '/drh/uniform-resource-participant.sql', 'Uniform Resource Participant', NULL, NULL, 'Participant demographics with pagination', NULL),
    ('prime', '/drh', 7, '/drh/author-pub-data', '/drh/author-pub-data/', 'Author Publication Information', 'Author Publication Information', NULL, 'Author Publication Information', NULL),
    ('prime', '/drh', 8, '/drh/deidentification-log', '/drh/deidentification-log/', 'PHI DeIdentification Results', 'PHI DeIdentification Results', NULL, 'PHI DeIdentification Results', NULL),
    ('prime', '/drh', 21, '/drh/cgm-combined-data', '/drh/cgm-combined-data/', 'Combined CGM Tracing', 'Combined CGM Tracing', NULL, 'Combined CGM Tracing', NULL),
    ('prime', '/drh', 9, '/drh/cgm-associated-data', '/drh/cgm-associated-data/', 'CGM File MetaData Information', 'CGM File MetaData Information', NULL, 'CGM File MetaData Information', NULL),
    ('prime', '/drh', 10, '/drh/cgm-data', '/drh/cgm-data/', 'Raw CGM Data', 'Raw CGM Data', NULL, 'Raw CGM Data', NULL),
    ('prime', '/drh', 11, '/drh/ingestion-log', '/drh/ingestion-log/', 'Study Files', 'Study Files', NULL, 'Study Files', NULL),
    ('prime', '/drh', 20, '/drh/participant-info', '/drh/participant-info/', 'Participant Information', 'Participant Information', NULL, 'The Participants Detail page is a comprehensive report that includes glucose statistics, such as the Ambulatory Glucose Profile (AGP), Glycemia Risk Index (GRI), Daily Glucose Profile, and all other metrics data.', NULL),
    ('prime', '/drh', 12, '/drh/study-participant-dashboard', '/drh/study-participant-dashboard/', 'Study Participant Dashboard', 'Study Participant Dashboard', NULL, 'Study Participant Dashboard', NULL),
    ('prime', '/drh', 13, '/drh/verification-validation-log', '/drh/verification-validation-log/', 'Verfication And Validation Results', 'Verfication And Validation Results', NULL, 'Verfication And Validation Results', NULL),
    ('prime', '/drh', 19, '/drh/participant-related-data', '/drh/participant-related-data/', 'Participant Information', 'Participant Information', NULL, NULL, NULL)
ON CONFLICT (namespace, parent_path, path)
DO UPDATE SET title = EXCLUDED.title, abbreviated_caption = EXCLUDED.abbreviated_caption, description = EXCLUDED.description, url = EXCLUDED.url, sibling_order = EXCLUDED.sibling_order;
INSERT OR IGNORE INTO sqlpage_aide_navigation ("path", caption, namespace, parent_path, sibling_order, url, title, abbreviated_caption, description,elaboration) VALUES
(NULL, 'DRH Home', 'prime', '/external', 1, 'https://drh.diabetestechnology.org/', NULL, NULL, NULL,'{ "target": "_blank" }'),
(NULL, 'DTS Home', 'prime', '/external', 1, 'https://www.diabetestechnology.org/', NULL, NULL, NULL,'{ "target": "_blank" }');
DROP VIEW IF EXISTS drh_participant_cgm_dates;

CREATE VIEW drh_participant_cgm_dates As
SELECT 
    participant_id,
    MIN(Date_Time) AS cgm_start_date,
    MAX(Date_Time) AS cgm_end_date
FROM 
    combined_cgm_tracing
GROUP BY 
    participant_id;
   


DROP VIEW IF EXISTS drh_participant_metrics;

-- Create the 
CREATE VIEW drh_participant_metrics AS
SELECT 
    participant_id,
    MIN(Date_Time) AS cgm_start_date,
    MAX(Date_Time) AS cgm_end_date,
    ROUND(AVG(CGM_Value), 2) AS mean_glucose,
    COUNT(DISTINCT DATE(Date_Time)) AS number_of_days_cgm_worn,
    ROUND(
        (COUNT(DISTINCT DATE(Date_Time)) / 
        ROUND((julianday(MAX(Date_Time)) - julianday(MIN(Date_Time)) + 1))
        ) * 100, 2) AS percentage_active,
    ROUND(AVG(CGM_Value) * 0.155 + 95, 2) AS gmi,
    ROUND((SQRT(AVG(CGM_Value * CGM_Value) - AVG(CGM_Value) * AVG(CGM_Value)) / AVG(CGM_Value)) * 100, 2) AS coefficient_of_variation
FROM 
    combined_cgm_tracing
GROUP BY 
    participant_id;



DROP VIEW IF EXISTS drh_time_range_stacked_metrics;
   
CREATE VIEW drh_time_range_stacked_metrics AS
   WITH GlucoseMetrics AS (
    SELECT 
        participant_id, 
        COUNT(*) AS total_readings, 
        SUM(CASE WHEN CGM_Value BETWEEN 54 AND 69 THEN 1 ELSE 0 END) AS time_below_range_low, 
        SUM(CASE WHEN CGM_Value < 54 THEN 1 ELSE 0 END) AS time_below_range_very_low, 
        SUM(CASE WHEN CGM_Value BETWEEN 70 AND 180 THEN 1 ELSE 0 END) AS time_in_range, 
        SUM(CASE WHEN CGM_Value > 250 THEN 1 ELSE 0 END) AS time_above_vh, 
        SUM(CASE WHEN CGM_Value BETWEEN 181 AND 250 THEN 1 ELSE 0 END) AS time_above_range_high 
    FROM 
        combined_cgm_tracing
    GROUP BY 
        participant_id 
), Defaults AS (
    SELECT 
        0 AS total_readings, 
        0 AS time_below_range_low, 
        0 AS time_below_range_very_low, 
        0 AS time_in_range, 
        0 AS time_above_vh, 
        0 AS time_above_range_high 
)

SELECT 
    gm.participant_id,
    COALESCE(CASE WHEN gm.total_readings = 0 THEN 0 ELSE (gm.time_below_range_low * 100.0 / gm.total_readings) END, 0) AS time_below_range_low_percentage, 
    COALESCE(gm.time_below_range_low, 0) AS time_below_range_low, 
    COALESCE(CASE WHEN gm.total_readings = 0 THEN '00 hours, 00 minutes' ELSE printf('%02d hours, %02d minutes', (gm.time_below_range_low * 5) / 60, (gm.time_below_range_low * 5) % 60) END, '00 hours, 00 minutes') AS time_below_range_low_string, 
    COALESCE(CASE WHEN gm.total_readings = 0 THEN 0 ELSE (gm.time_below_range_very_low * 100.0 / gm.total_readings) END, 0) AS time_below_range_very_low_percentage, 
    COALESCE(gm.time_below_range_very_low, 0) AS time_below_range_very_low, 
    COALESCE(CASE WHEN gm.total_readings = 0 THEN '00 hours, 00 minutes' ELSE printf('%02d hours, %02d minutes', (gm.time_below_range_very_low * 5) / 60, (gm.time_below_range_very_low * 5) % 60) END, '00 hours, 00 minutes') AS time_below_range_very_low_string, 
    COALESCE(CASE WHEN gm.total_readings = 0 THEN 0 ELSE (gm.time_in_range * 100.0 / gm.total_readings) END, 0) AS time_in_range_percentage, 
    COALESCE(gm.time_in_range, 0) AS time_in_range, 
    COALESCE(CASE WHEN gm.total_readings = 0 THEN '00 hours, 00 minutes' ELSE printf('%02d hours, %02d minutes', (gm.time_in_range * 5) / 60, (gm.time_in_range * 5) % 60) END, '00 hours, 00 minutes') AS time_in_range_string, 
    COALESCE(CASE WHEN gm.total_readings = 0 THEN 0 ELSE (gm.time_above_vh * 100.0 / gm.total_readings) END, 0) AS time_above_vh_percentage, 
    COALESCE(gm.time_above_vh, 0) AS time_above_vh, 
    COALESCE(CASE WHEN gm.total_readings = 0 THEN '00 hours, 00 minutes' ELSE printf('%02d hours, %02d minutes', (gm.time_above_vh * 5) / 60, (gm.time_above_vh * 5) % 60) END, '00 hours, 00 minutes') AS time_above_vh_string, 
    COALESCE(CASE WHEN gm.total_readings = 0 THEN 0 ELSE (gm.time_above_range_high * 100.0 / gm.total_readings) END, 0) AS time_above_range_high_percentage, 
    COALESCE(gm.time_above_range_high, 0) AS time_above_range_high, 
    COALESCE(CASE WHEN gm.total_readings = 0 THEN '00 hours, 00 minutes' ELSE printf('%02d hours, %02d minutes', (gm.time_above_range_high * 5) / 60, (gm.time_above_range_high * 5) % 60) END, '00 hours, 00 minutes') AS time_above_range_high_string 
FROM 
    Defaults d 
    LEFT JOIN GlucoseMetrics gm ON 1=1;


DROP VIEW IF EXISTS drh_agp_metrics;
   
CREATE VIEW drh_agp_metrics AS
WITH glucose_data AS (
    SELECT
        gr.participant_id,
        gr.Date_Time AS timestamp,
        strftime('%Y-%m-%d %H', gr.Date_Time) AS hourValue,
        gr.CGM_Value AS glucose_level
    FROM
        combined_cgm_tracing gr
),
ranked_data AS (
    SELECT
        participant_id,
        hourValue,
        glucose_level,
        ROW_NUMBER() OVER (PARTITION BY participant_id, hourValue ORDER BY glucose_level) AS row_num,
        COUNT(*) OVER (PARTITION BY participant_id, hourValue) AS total_count
    FROM
        glucose_data
),
percentiles AS (
    SELECT
        participant_id,
        hourValue AS hour,
        MAX(CASE WHEN row_num = CAST(0.05 * total_count AS INT) THEN glucose_level END) AS p5,
        MAX(CASE WHEN row_num = CAST(0.25 * total_count AS INT) THEN glucose_level END) AS p25,
        MAX(CASE WHEN row_num = CAST(0.50 * total_count AS INT) THEN glucose_level END) AS p50,
        MAX(CASE WHEN row_num = CAST(0.75 * total_count AS INT) THEN glucose_level END) AS p75,
        MAX(CASE WHEN row_num = CAST(0.95 * total_count AS INT) THEN glucose_level END) AS p95
    FROM
        ranked_data
    GROUP BY
        participant_id, hour
),
hourly_averages AS (
    SELECT
        participant_id,
        SUBSTR(hour, 1, 10) AS date,
        SUBSTR(hour, 12) AS hour,
        COALESCE(AVG(p5), 0) AS p5,
        COALESCE(AVG(p25), 0) AS p25,
        COALESCE(AVG(p50), 0) AS p50,
        COALESCE(AVG(p75), 0) AS p75,
        COALESCE(AVG(p95), 0) AS p95
    FROM
        percentiles
    GROUP BY
        participant_id, hour
)
SELECT
    participant_id,
    hour,
    COALESCE(AVG(p5), 0) AS p5,
    COALESCE(AVG(p25), 0) AS p25,
    COALESCE(AVG(p50), 0) AS p50,
    COALESCE(AVG(p75), 0) AS p75,
    COALESCE(AVG(p95), 0) AS p95
FROM
    hourly_averages
GROUP BY
    participant_id, hour
ORDER BY
    participant_id, hour;



DROP VIEW IF EXISTS drh_glycemic_risk_indicator;

CREATE VIEW drh_glycemic_risk_indicator AS 
  SELECT 
    ROUND(COALESCE((SUM(CASE WHEN cgm_value > 250 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)), 0), 2) AS time_above_VH_percentage,
    ROUND(COALESCE((SUM(CASE WHEN cgm_value BETWEEN 181 AND 250 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)), 0), 2) AS time_above_H_percentage,
    ROUND(COALESCE((SUM(CASE WHEN cgm_value BETWEEN 70 AND 180 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)), 0), 2) AS time_in_range_percentage,
    ROUND(COALESCE((SUM(CASE WHEN cgm_value BETWEEN 54 AND 69 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)), 0), 2) AS time_below_low_percentage,
    ROUND(COALESCE((SUM(CASE WHEN cgm_value < 54 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)), 0), 2) AS time_below_VL_percentage,
    ROUND(COALESCE((SUM(CASE WHEN cgm_value < 54 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) + 
                   (0.8 * (SUM(CASE WHEN cgm_value BETWEEN 54 AND 69 THEN 1 ELSE 0 END) * 100.0 / COUNT(*))), 0), 2) AS Hypoglycemia_Component,
    ROUND(COALESCE((SUM(CASE WHEN cgm_value > 250 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) + 
                   (0.5 * (SUM(CASE WHEN cgm_value BETWEEN 181 AND 250 THEN 1 ELSE 0 END) * 100.0 / COUNT(*))), 0), 2) AS Hyperglycemia_Component,
    ROUND(COALESCE((3.0 * ((SUM(CASE WHEN cgm_value < 54 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) + 
                            (0.8 * (SUM(CASE WHEN cgm_value BETWEEN 54 AND 69 THEN 1 ELSE 0 END) * 100.0 / COUNT(*))))) + 
                   (1.6 * ((SUM(CASE WHEN cgm_value > 250 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) + 
                            (0.5 * (SUM(CASE WHEN cgm_value BETWEEN 181 AND 250 THEN 1 ELSE 0 END) * 100.0 / COUNT(*))))), 0), 2) AS GRI
FROM combined_cgm_tracing
GROUP BY participant_id;




DROP VIEW IF EXISTS drh_advanced_metrics;
CREATE  VIEW drh_advanced_metrics AS
WITH risk_scores AS (
    SELECT 
        participant_id,
        CGM_Value,
        CASE
            WHEN CGM_Value < 90 THEN 10 * (5 - (CGM_Value / 18.0)) * (5 - (CGM_Value / 18.0))
            WHEN CGM_Value > 180 THEN 10 * ((CGM_Value / 18.0) - 10) * ((CGM_Value / 18.0) - 10)
            ELSE 0
        END AS risk_score
    FROM combined_cgm_tracing
),
average_risk AS (
    SELECT 
        participant_id,
        AVG(risk_score) AS avg_risk_score
    FROM risk_scores
    GROUP BY participant_id
),
amplitude_data AS (
    SELECT 
        participant_id,
        ABS(MAX(CGM_Value) - MIN(CGM_Value)) AS amplitude
    FROM combined_cgm_tracing
    GROUP BY participant_id, DATE(Date_Time)
),
mean_amplitude AS (
    SELECT 
        participant_id,
        AVG(amplitude) AS mean_amplitude
    FROM amplitude_data
    GROUP BY participant_id
),
participant_min_max AS (
    SELECT 
        participant_id,
        MIN(CGM_Value) AS min_glucose,
        MAX(CGM_Value) AS max_glucose,
        MIN(DATETIME(Date_Time)) AS start_time,
        MAX(DATETIME(Date_Time)) AS end_time
    FROM combined_cgm_tracing
    GROUP BY participant_id
),
m_value AS (
    SELECT 
        participant_id,
        (max_glucose - min_glucose) / ((strftime('%s', end_time) - strftime('%s', start_time)) / 60.0) AS m_value
    FROM participant_min_max
),
daily_risk AS (
    SELECT 
        participant_id,
        DATE(Date_Time) AS day,
        MAX(CGM_Value) - MIN(CGM_Value) AS daily_range
    FROM combined_cgm_tracing
    GROUP BY participant_id, DATE(Date_Time)
),
average_daily_risk AS (
    SELECT 
        participant_id,
        AVG(daily_range) AS average_daily_risk
    FROM daily_risk
    GROUP BY participant_id
),
glucose_stats AS (
    SELECT
        participant_id,
        AVG(CGM_Value) AS mean_glucose,
        (AVG(CGM_Value * CGM_Value) - AVG(CGM_Value) * AVG(CGM_Value)) AS variance_glucose
    FROM combined_cgm_tracing
    GROUP BY participant_id
),
lbgi_hbgi AS (
    SELECT 
        participant_id,
        ROUND(SUM(CASE WHEN (CGM_Value - 2.5) / 2.5 > 0 THEN ((CGM_Value - 2.5) / 2.5) * ((CGM_Value - 2.5) / 2.5) ELSE 0 END) * 5, 2) AS lbgi, 
        ROUND(SUM(CASE WHEN (CGM_Value - 9.5) / 9.5 > 0 THEN ((CGM_Value - 9.5) / 9.5) * ((CGM_Value - 9.5) / 9.5) ELSE 0 END) * 5, 2) AS hbgi
    FROM combined_cgm_tracing
    GROUP BY participant_id
),
daily_diffs AS (
    SELECT
        participant_id,
        DATE(Date_Time) AS date,
        CGM_Value,
        CGM_Value - LAG(CGM_Value) OVER (PARTITION BY participant_id ORDER BY DATE(Date_Time)) AS daily_diff
    FROM combined_cgm_tracing
),
mean_daily_diff AS (
    SELECT
        participant_id,
        AVG(daily_diff) AS mean_daily_diff
    FROM daily_diffs
    WHERE daily_diff IS NOT NULL
    GROUP BY participant_id
),
lag_values AS (
    SELECT 
        participant_id,
        Date_Time,
        CGM_Value,
        LAG(CGM_Value) OVER (PARTITION BY participant_id ORDER BY Date_Time) AS lag_CGM_Value
    FROM combined_cgm_tracing
),
conga_hourly AS (
    SELECT 
        participant_id,
        SQRT(
            AVG(
                (CGM_Value - lag_CGM_Value) * (CGM_Value - lag_CGM_Value)
            ) OVER (PARTITION BY participant_id ORDER BY Date_Time)
        ) AS conga_hourly
    FROM lag_values
    WHERE lag_CGM_Value IS NOT NULL
    GROUP BY participant_id
),
liability_index AS (
    SELECT
        participant_id,
        SUM(CASE WHEN CGM_Value < 70 THEN 1 ELSE 0 END) AS hypoglycemic_episodes, 
        SUM(CASE WHEN CGM_Value BETWEEN 70 AND 180 THEN 1 ELSE 0 END) AS euglycemic_episodes, 
        SUM(CASE WHEN CGM_Value > 180 THEN 1 ELSE 0 END) AS hyperglycemic_episodes, 
        ROUND(CAST(
            (SUM(CASE WHEN CGM_Value < 70 THEN 1 ELSE 0 END) + SUM(CASE WHEN CGM_Value > 180 THEN 1 ELSE 0 END))
            AS REAL
        ) / COUNT(*), 2) AS liability_index
    FROM combined_cgm_tracing
    GROUP BY participant_id
),
j_index AS (
    SELECT
        participant_id,
        ROUND(0.001 * (mean_glucose + sqrt(variance_glucose)) * (mean_glucose + sqrt(variance_glucose)), 2) AS j_index
    FROM glucose_stats
),
time_in_tight_range AS ( 
    SELECT        
        participant_id,
        (SUM(CASE WHEN CGM_Value BETWEEN 70 AND 140 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS time_in_tight_range_percentage,
        SUM(CASE WHEN CGM_Value BETWEEN 70 AND 140 THEN 1 ELSE 0 END) AS time_in_tight_range        
    FROM combined_cgm_tracing
    GROUP BY participant_id
)
SELECT
    participant_id,
    COALESCE((SELECT time_in_tight_range_percentage FROM time_in_tight_range WHERE participant_id = p.participant_id), 0) AS time_in_tight_range_percentage,
    COALESCE((SELECT avg_risk_score FROM average_risk WHERE participant_id = p.participant_id), 0) AS grade,
    COALESCE((SELECT mean_amplitude FROM mean_amplitude WHERE participant_id = p.participant_id), 0) AS mean_amplitude,
    COALESCE((SELECT m_value FROM m_value WHERE participant_id = p.participant_id), 0) AS m_value,
    COALESCE((SELECT average_daily_risk FROM average_daily_risk WHERE participant_id = p.participant_id), 0) AS average_daily_risk,
    COALESCE((SELECT mean_glucose FROM glucose_stats WHERE participant_id = p.participant_id), 0) AS mean_glucose,
    COALESCE((SELECT lbgi FROM lbgi_hbgi WHERE participant_id = p.participant_id), 0) AS lbgi,
    COALESCE((SELECT hbgi FROM lbgi_hbgi WHERE participant_id = p.participant_id), 0) AS hbgi,
    COALESCE((SELECT mean_daily_diff FROM mean_daily_diff WHERE participant_id = p.participant_id), 0) AS mean_daily_diff,
    COALESCE((SELECT conga_hourly FROM conga_hourly WHERE participant_id = p.participant_id), 0) AS conga_hourly,
    COALESCE((SELECT hypoglycemic_episodes FROM liability_index WHERE participant_id = p.participant_id), 0) AS hypoglycemic_episodes,
    COALESCE((SELECT euglycemic_episodes FROM liability_index WHERE participant_id = p.participant_id), 0) AS euglycemic_episodes,
    COALESCE((SELECT hyperglycemic_episodes FROM liability_index WHERE participant_id = p.participant_id), 0) AS hyperglycemic_episodes,
    COALESCE((SELECT liability_index FROM liability_index WHERE participant_id = p.participant_id), 0) AS liability_index,
    COALESCE((SELECT j_index FROM j_index WHERE participant_id = p.participant_id), 0) AS j_index
FROM (
    SELECT DISTINCT participant_id 
    FROM combined_cgm_tracing
) AS p;



DROP VIEW IF EXISTS study_combined_dashboard_participant_metrics_view;
CREATE VIEW study_combined_dashboard_participant_metrics_view AS
WITH combined_data AS (
    SELECT 
        CAST(SUBSTR(dg.participant_id, 1, INSTR(dg.participant_id, '-') - 1) AS TEXT) AS study_id,        
        dg.participant_id,
        dg.gender,
        dg.age,
        dg.study_arm,
        dg.baseline_hba1c,
        ROUND(SUM(CASE WHEN dc.CGM_Value BETWEEN 70 AND 180 THEN 1 ELSE 0 END) * 1.0 / COUNT(dc.CGM_Value) * 100, 2) AS tir,
        ROUND(SUM(CASE WHEN dc.CGM_Value > 250 THEN 1 ELSE 0 END) * 1.0 / COUNT(dc.CGM_Value) * 100, 2) AS tar_vh,
        ROUND(SUM(CASE WHEN dc.CGM_Value BETWEEN 181 AND 250 THEN 1 ELSE 0 END) * 1.0 / COUNT(dc.CGM_Value) * 100, 2) AS tar_h,
        ROUND(SUM(CASE WHEN dc.CGM_Value BETWEEN 54 AND 69 THEN 1 ELSE 0 END) * 1.0 / COUNT(dc.CGM_Value) * 100, 2) AS tbr_l,
        ROUND(SUM(CASE WHEN dc.CGM_Value < 54 THEN 1 ELSE 0 END) * 1.0 / COUNT(dc.CGM_Value) * 100, 2) AS tbr_vl,
        ROUND(SUM(CASE WHEN dc.CGM_Value > 180 THEN 1 ELSE 0 END) * 1.0 / COUNT(dc.CGM_Value)*100, 2) AS tar,
        ROUND(SUM(CASE WHEN dc.CGM_Value < 70 THEN 1 ELSE 0 END) * 1.0 / COUNT(dc.CGM_Value)*100, 2) AS tbr,
        CEIL((AVG(dc.CGM_Value) * 0.155) + 95) AS gmi,
        ROUND((SQRT(AVG(dc.CGM_Value * dc.CGM_Value) - AVG(dc.CGM_Value) * AVG(dc.CGM_Value)) / AVG(dc.CGM_Value)) * 100, 2) AS percent_gv,
        ROUND((3.0 * ((SUM(CASE WHEN dc.CGM_Value < 54 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) + (0.8 * (SUM(CASE WHEN dc.CGM_Value BETWEEN 54 AND 69 THEN 1 ELSE 0 END) * 100.0 / COUNT(*))))) + (1.6 * ((SUM(CASE WHEN dc.CGM_Value > 250 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) + (0.5 * (SUM(CASE WHEN dc.CGM_Value BETWEEN 181 AND 250 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) ))), 2) AS gri,
        COUNT(DISTINCT DATE(dc.Date_Time)) AS days_of_wear,
        MIN(DATE(dc.Date_Time)) AS data_start_date,
        MAX(DATE(dc.Date_Time)) AS data_end_date
    FROM drh_participant dg 
    JOIN combined_cgm_tracing dc ON dg.participant_id = dc.participant_id
    GROUP BY study_id, dg.participant_id, dg.gender, dg.age, dg.study_arm, dg.baseline_hba1c
)
SELECT *,
    ROUND(
        COALESCE(
            (days_of_wear * 1.0 / 
            (JULIANDAY(data_end_date) - JULIANDAY(data_start_date) + 1)) * 100, 
            0), 
        2) AS wear_time_percentage FROM combined_data;


DROP VIEW IF EXISTS participant_cgm_date_range_view;
CREATE VIEW participant_cgm_date_range_view AS 
SELECT 
    participant_id,
    CAST(strftime('%Y-%m-%d', MIN(Date_Time)) AS TEXT) AS participant_cgm_start_date,
    CAST(strftime('%Y-%m-%d', MAX(Date_Time)) AS TEXT) AS participant_cgm_end_date,
    CAST(strftime('%Y-%m-%d', DATE(MAX(Date_Time), '-1 day')) AS TEXT) AS end_date_minus_1_day,
    CAST(strftime('%Y-%m-%d', DATE(MAX(Date_Time), '-7 day')) AS TEXT) AS end_date_minus_7_days,
    CAST(strftime('%Y-%m-%d', DATE(MAX(Date_Time), '-14 day')) AS TEXT) AS end_date_minus_14_days,
    CAST(strftime('%Y-%m-%d', DATE(MAX(Date_Time), '-30 day')) AS TEXT) AS end_date_minus_30_days,
    CAST(strftime('%Y-%m-%d', DATE(MAX(Date_Time), '-90 day')) AS TEXT) AS end_date_minus_90_days
FROM 
    combined_cgm_tracing  
GROUP BY 
    participant_id;







DROP TABLE IF EXISTS metric_definitions;
CREATE TABLE IF NOT EXISTS metric_definitions (
    metric_id TEXT PRIMARY KEY,
    metric_name TEXT NOT NULL UNIQUE,
    metric_info TEXT NOT NULL -- Stores JSON with "description" and "formula" details
);

-- Metric: Time CGM Active
INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info)
VALUES (
    'time_cgm_active', 
    'Time CGM Active', 
    '{"description": "This metric calculates the percentage of time during a specific period (e.g., a day, week, or month) that the CGM device is actively collecting data. It takes into account the total duration of the monitoring period and compares it to the duration during which the device was operational and recording glucose readings.", 
      "formula": "Percentage of time CGM is active = (Duration CGM is active / Total duration of monitoring period) × 100"}'
);

-- Metric: Number of Days CGM Worn
INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info)
VALUES (
    'number_of_days_cgm_worn', 
    'Number of Days CGM Worn', 
    '{"description": "This metric represents the total number of days the CGM device was worn by the user over a monitoring period. It helps in assessing the adherence to wearing the device as prescribed.", 
      "formula": "Number of days CGM worn = Count of days with CGM data recorded in the monitoring period"}'
);

-- Metric: Mean Glucose
INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info)
VALUES (
    'mean_glucose', 
    'Mean Glucose', 
    '{"description": "Mean glucose reflects the average glucose level over the monitoring period, serving as an indicator of overall glucose control. It is a simple yet powerful measure in glucose management.", 
      "formula": "Mean glucose = Sum of all glucose readings / Number of readings"}'
);

-- Metric: Glucose Management Indicator (GMI)
INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info)
VALUES (
    'gmi', 
    'Glucose Management Indicator (GMI)', 
    '{"description": "GMI provides an estimated A1C level based on mean glucose, which can be used as an indicator of long-term glucose control. GMI helps in setting and assessing long-term glucose goals.", 
      "formula": "GMI = (3.31 + 0.02392 × Mean glucose) × 100"}'
);

-- Metric: Glucose Variability
INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info)
VALUES (
    'glucose_variability', 
    'Glucose Variability', 
    '{"description": "Glucose variability measures fluctuations in glucose levels over time, calculated as the coefficient of variation (%CV). A lower %CV indicates more stable glucose control.", 
      "formula": "Glucose variability = (Standard deviation of glucose / Mean glucose) × 100"}'
);

-- Insert a single record for AGP metrics and axes
INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info)
VALUES (
    'AGP_metrics',
    'Ambulatory Glucose Profile (AGP)',
    '{"description": "The Ambulatory Glucose Profile (AGP) summarizes glucose monitoring data over a specified period, typically 14 to 90 days. It provides a visual representation of glucose levels, helping to identify patterns and variability in glucose management.",
        "metrics": {
            "time_in_target_range": {
                "description": "This metric indicates the percentage of time glucose levels are within the target range (typically 70-180 mg/dL). It is essential for evaluating the effectiveness of diabetes management.",
                "formula": "Percentage in Target Range = (Time in Target Range / Total Time) × 100"
            },
            "below_70": {
                "description": "Tracks the percentage of time glucose levels are below 70 mg/dL, indicating hypoglycemic episodes. Understanding these periods helps prevent severe lows.",
                "formula": "Percentage below 70 mg/dL = (Time below 70 mg/dL / Total Time) × 100"
            },
            "above_180": {
                "description": "Indicates the percentage of time glucose levels exceed 180 mg/dL, highlighting periods of hyperglycemia. Managing these episodes is critical for overall health.",
                "formula": "Percentage above 180 mg/dL = (Time above 180 mg/dL / Total Time) × 100"
            },
            "quartiles": {
                "description": "Quartiles divide glucose readings into four equal parts, helping to understand glucose level distribution. Q1 is the 25th percentile, Q2 is the median, and Q3 is the 75th percentile.",
                "formula": "Quartiles are calculated from sorted glucose readings: Q1 = 25th percentile, Q2 = 50th percentile (median), Q3 = 75th percentile."
            }
        },
        "axes": {
            "x_axis": {
                "description": "Time of Day - The X-axis represents the time of day, segmented into hourly intervals. It typically includes the following time points: 12 AM, 3 AM, 6 AM, 9 AM, 12 PM, 3 PM, 6 PM, 9 PM, and 11 PM."
            },
            "y_axis": {
                "description": "Glucose Levels -The Y-axis represents glucose levels measured in milligrams per deciliter (mg/dL). It typically displays a range from 0 mg/dL to 350 mg/dL, indicating when glucose levels are within, below, or above the target range."
            }
        }
    }'
);

-- Seed SQL for metrics definitions with JSON formatted metric_info

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('liability_index', 'Liability Index', '{"description": "The Liability Index quantifies the risk associated with glucose variability, measured in mg/dL.", "formula": "Liability Index = (Total Duration of monitoring period) * (Average of CGM_i)"}');

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('hypoglycemic_episodes', 'Hypoglycemic Episodes', '{"description": "This metric counts the number of occurrences when glucose levels drop below a specified hypoglycemic threshold, indicating potentially dangerous low blood sugar events.", "formula": "Hypoglycemic Episodes = COUNT(CASE WHEN CGM_i < Threshold THEN 1 END)"}');

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('euglycemic_episodes', 'Euglycemic Episodes', '{"description": "This metric counts the number of instances where glucose levels remain within the target range, indicating stable and healthy glucose control.", "formula": "Euglycemic Episodes = COUNT(CASE WHEN CGM_i BETWEEN LowThreshold AND HighThreshold THEN 1 END)"}');

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('hyperglycemic_episodes', 'Hyperglycemic Episodes', '{"description": "This metric counts the number of instances where glucose levels exceed a certain hyperglycemic threshold, indicating potentially harmful high blood sugar events.", "formula": "Hyperglycemic Episodes = COUNT(CASE WHEN CGM_i > Threshold THEN 1 END)"}');

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('m_value', 'M Value', '{"description": "The M Value provides a measure of glucose variability, calculated from the mean of the absolute differences between consecutive CGM values over a specified period.", "formula": "M Value = Mean(ABS(CGM_i - CGM_(i-1)))"}');

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('mean_amplitude', 'Mean Amplitude', '{"description": "Mean Amplitude quantifies the average degree of fluctuation in glucose levels over a given time frame, giving insight into glucose stability.", "formula": "Mean Amplitude = Mean(ABS(CGM_i - Mean(CGM)))"}');

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('average_daily_risk_range', 'Average Daily Risk Range', '{"description": "This metric assesses the average risk associated with daily glucose variations, expressed in mg/dL.", "formula": "Average Daily Risk Range = (Max(CGM) - Min(CGM)) / Number of Days"}');

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('j_index', 'J Index', '{"description": "The J Index calculates glycemic variability using both high and low glucose readings, offering a comprehensive view of glucose fluctuations.", "formula": "J Index = (3.0 * Hypoglycemia Component) + (1.6 * Hyperglycemia Component)"}');

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('low_blood_glucose_index', 'Low Blood Glucose Index', '{"description": "This metric quantifies the risk associated with low blood glucose levels over a specified period, measured in mg/dL.", "formula": "Low Blood Glucose Index = SUM(CASE WHEN CGM_i < LowThreshold THEN 1 ELSE 0 END)"}');

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('high_blood_glucose_index', 'High Blood Glucose Index', '{"description": "This metric quantifies the risk associated with high blood glucose levels over a specified period, measured in mg/dL.", "formula": "High Blood Glucose Index = SUM(CASE WHEN CGM_i > HighThreshold THEN 1 ELSE 0 END)"}');

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('glycemic_risk_assessment', 'Glycemic Risk Assessment Diabetes Equation (GRADE)', '{"description": "GRADE is a metric that combines various glucose metrics to assess overall glycemic risk in individuals with diabetes, calculated using multiple input parameters.", "formula": "GRADE = (Weights based on Low, Normal, High CGM values)"}');

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('continuous_overall_net_glycemic_action', 'Continuous Overall Net Glycemic Action (CONGA)', '{"description": "CONGA quantifies the net glycemic effect over time by evaluating the differences between CGM values at specified intervals.", "formula": "CONGA = Mean(ABS(CGM_i - CGM_(i-k))) for k=1 to n"}');

INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
('mean_of_daily_differences', 'Mean of Daily Differences', '{"description": "This metric calculates the average of the absolute differences between daily CGM readings, giving insight into daily glucose variability.", "formula": "Mean of Daily Differences = Mean(ABS(CGM_i - CGM_(i-1)))"}');


INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
(
    'daily_glucose_profile', 
    'Daily Glucose Profile', 
    '{
        "description": "The Daily Glucose Profile Chart visualizes a participant''s glucose levels over a specified timeframe, typically the last 14 days. Each point on the graph represents a glucose reading taken at a specific hour, indicating the participant''s response to food intake, exercise, medication, and other lifestyle factors. Monitoring these thresholds helps in identifying periods of risk: hypoglycemia, for glucose levels below 70 mg/dL, and hyperglycemia, for levels above 180 mg/dL. This analysis can guide interventions and adjustments in treatment. A consistently high or low profile may lead to further investigation and modifications in treatment plans.",
        "axes": {
            "y_axis": "The y-axis represents glucose levels in mg/dL, with a lower threshold of 70 mg/dL indicating hypoglycemia risk and an upper threshold of 180 mg/dL indicating hyperglycemia risk.",
            "x_axis": "The x-axis spans a week from Friday to Thursday, displaying data between 12 PM and 10 PM each day, focusing on peak active hours for glucose level variations."
        }
    }'
);


INSERT OR IGNORE INTO metric_definitions (metric_id, metric_name, metric_info) VALUES
(
    'goals_for_type_1_and_type_2_diabetes_chart_metrics', 
    'Goals for Type 1 and Type 2 Diabetes chart Metrics', 
    '{
        "description": "Goals for Type 1 and Type 2 Diabetes Chart provides a comprehensive view of a participant''s glucose readings categorized into different ranges over a specified period.",
        "metrics": {
            "very_low": {
                "description": "Represents the count and percentage of readings below 54 mg/dL, which may indicate critical hypoglycemia."
            },
            "low": {
                "description": "Represents the count and percentage of readings between 54 mg/dL and 69 mg/dL, indicating a potential risk of hypoglycemia."
            },
            "in_range": {
                "description": "The percentage and count of readings between 70 mg/dL and 180 mg/dL, considered the target glucose range for optimal health.",
                "target": "over 70%"
            },
            "high": {
                "description": "Includes readings between 181 mg/dL and 250 mg/dL, indicating borderline hyperglycemia."
            },
            "very_high": {
                "description": "Represents readings above 250 mg/dL, indicating potentially dangerous hyperglycemia."
            }
        },
        "formula": "The calculation for each category is performed by counting the total readings in each defined glucose range. The chart shows both the total time spent in each range and the percentage of total readings over a defined monitoring period. Example: If a participant has 100 readings and 10 are below 54 mg/dL, the percentage is calculated as (10 / 100) * 100, resulting in 10%. Usage: The chart aids healthcare providers and participants in understanding glucose variability and making informed decisions.",
        "axes": "x-axis: Time intervals and y-axis: Percentages of time in each range"
    }'
);


DROP VIEW IF EXISTS metric_info_view;
CREATE VIEW metric_info_view AS
SELECT 
    metric_id,
    metric_name,
    json_extract(metric_info, '$.description') AS "Metrics Description",
    json_extract(metric_info, '$.formula') AS formula,    
    json_extract(metric_info, '$.metrics') AS "Metrics Details",    
    json_extract(metric_info, '$.axes') AS "Axes Details"    
FROM 
    metric_definitions;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'shell/shell.json',
      '{
  "component": "shell",
  "title": "Diabetes Research Hub EDGE",
  "icon": "",
  "favicon": "https://drh.diabetestechnology.org/_astro/favicon.CcrFY5y9.ico",
  "image": "https://drh.diabetestechnology.org/images/diabetic-research-hub-logo.png",
  "layout": "fluid",
  "fixed_top_menu": true,
  "link": "/drh/",
  "menu_item": [
    {
      "link": "/",
      "title": "Home"
    }
  ],
  "javascript": [
    "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/highlight.min.js",
    "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/languages/sql.min.js",
    "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/languages/handlebars.min.js",
    "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/languages/json.min.js"
  ],
  "footer": "Resource Surveillance Web UI"
};',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'shell/shell.sql',
      'SELECT ''shell'' AS component,
       ''Diabetes Research Hub EDGE'' AS title,
       NULL AS icon,
       ''https://drh.diabetestechnology.org/_astro/favicon.CcrFY5y9.ico'' AS favicon,
       ''https://drh.diabetestechnology.org/images/diabetic-research-hub-logo.png'' AS image,
       ''fluid'' AS layout,
       true AS fixed_top_menu,
       ''/drh/'' AS link,
       ''{"link":"/","title":"Home"}'' AS menu_item,
       ''https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/highlight.min.js'' AS javascript,
       ''https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/languages/sql.min.js'' AS javascript,
       ''https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/languages/handlebars.min.js'' AS javascript,
       ''https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/languages/json.min.js'' AS javascript,
       json_object(
            ''link'', ''/ur'',
            ''title'', ''Uniform Resource'',      
            ''target'', '''',      
            ''submenu'', (
                SELECT json_group_array(
                    json_object(
                        ''title'', title,
                        ''link'', link,
                        ''description'', description,
                        ''target'', target                      
                    )
                )
                FROM (
                    SELECT
                        COALESCE(abbreviated_caption, caption) as title,
                        COALESCE(url, path) as link,
                        description,
                        elaboration as target
                    FROM sqlpage_aide_navigation
                    WHERE namespace = ''prime'' AND parent_path = ''/ur''
                    ORDER BY sibling_order
                )
            )
        ) as menu_item,
       json_object(
            ''link'', ''/console'',
            ''title'', ''Console'',      
            ''target'', '''',      
            ''submenu'', (
                SELECT json_group_array(
                    json_object(
                        ''title'', title,
                        ''link'', link,
                        ''description'', description,
                        ''target'', target                      
                    )
                )
                FROM (
                    SELECT
                        COALESCE(abbreviated_caption, caption) as title,
                        COALESCE(url, path) as link,
                        description,
                        elaboration as target
                    FROM sqlpage_aide_navigation
                    WHERE namespace = ''prime'' AND parent_path = ''/console''
                    ORDER BY sibling_order
                )
            )
        ) as menu_item,
       json_object(
            ''link'', ''/orchestration'',
            ''title'', ''Orchestration'',      
            ''target'', '''',      
            ''submenu'', (
                SELECT json_group_array(
                    json_object(
                        ''title'', title,
                        ''link'', link,
                        ''description'', description,
                        ''target'', target                      
                    )
                )
                FROM (
                    SELECT
                        COALESCE(abbreviated_caption, caption) as title,
                        COALESCE(url, path) as link,
                        description,
                        elaboration as target
                    FROM sqlpage_aide_navigation
                    WHERE namespace = ''prime'' AND parent_path = ''/orchestration''
                    ORDER BY sibling_order
                )
            )
        ) as menu_item,
       json_object(
            ''link'', ''https://drh.diabetestechnology.org/'',
            ''title'', ''DRH Home'',      
            ''target'', ''__blank'',      
            ''submenu'', (
                SELECT json_group_array(
                    json_object(
                        ''title'', title,
                        ''link'', link,
                        ''description'', description,
                        ''target'', target                      
                    )
                )
                FROM (
                    SELECT
                        COALESCE(abbreviated_caption, caption) as title,
                        COALESCE(url, path) as link,
                        description,
                        elaboration as target
                    FROM sqlpage_aide_navigation
                    WHERE namespace = ''prime'' AND parent_path = ''https://drh.diabetestechnology.org/''
                    ORDER BY sibling_order
                )
            )
        ) as menu_item,
       json_object(
            ''link'', ''https://www.diabetestechnology.org/'',
            ''title'', ''DTS Home'',      
            ''target'', ''__blank'',      
            ''submenu'', (
                SELECT json_group_array(
                    json_object(
                        ''title'', title,
                        ''link'', link,
                        ''description'', description,
                        ''target'', target                      
                    )
                )
                FROM (
                    SELECT
                        COALESCE(abbreviated_caption, caption) as title,
                        COALESCE(url, path) as link,
                        description,
                        elaboration as target
                    FROM sqlpage_aide_navigation
                    WHERE namespace = ''prime'' AND parent_path = ''https://www.diabetestechnology.org/''
                    ORDER BY sibling_order
                )
            )
        ) as menu_item,
       ''Resource Surveillance Web UI (v'' || sqlpage.version() || '') '' || ''📄 ['' || substr(sqlpage.path(), 2) || ''](/console/sqlpage-files/sqlpage-file.sql?path='' || substr(sqlpage.path(), 2) || '')'' as footer;',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              -- not including breadcrumbs from sqlpage_aide_navigation
              -- not including page title from sqlpage_aide_navigation

              SELECT ''list'' AS component;
SELECT caption as title, COALESCE(url, path) as link, description
  FROM sqlpage_aide_navigation
 WHERE namespace = ''prime'' AND parent_path = ''/''
 ORDER BY sibling_order;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'console/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/console''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              WITH console_navigation_cte AS (
    SELECT title, description
      FROM sqlpage_aide_navigation
     WHERE namespace = ''prime'' AND path = ''/console''
)
SELECT ''list'' AS component, title, description
  FROM console_navigation_cte;
SELECT caption as title, COALESCE(url, path) as link, description
  FROM sqlpage_aide_navigation
 WHERE namespace = ''prime'' AND parent_path = ''/console''
 ORDER BY sibling_order;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'console/info-schema/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/console/info-schema''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, ''Tables'' as contents;
SELECT ''table'' AS component,
      ''Table'' AS markdown,
      ''Column Count'' as align_right,
      ''Content'' as markdown,
      TRUE as sort,
      TRUE as search;
SELECT
    ''['' || table_name || ''](table.sql?name='' || table_name || '')'' AS "Table",
    COUNT(column_name) AS "Column Count",
    content_web_ui_link_abbrev_md as "Content"
FROM console_information_schema_table
GROUP BY table_name;

SELECT ''title'' AS component, ''Views'' as contents;
SELECT ''table'' AS component,
      ''View'' AS markdown,
      ''Column Count'' as align_right,
      ''Content'' as markdown,
      TRUE as sort,
      TRUE as search;
SELECT
    ''['' || view_name || ''](view.sql?name='' || view_name || '')'' AS "View",
    COUNT(column_name) AS "Column Count",
    content_web_ui_link_abbrev_md as "Content"
FROM console_information_schema_view
GROUP BY view_name;

SELECT ''title'' AS component, ''Migrations'' as contents;
SELECT ''table'' AS component,
      ''Table'' AS markdown,
      ''Column Count'' as align_right,
      TRUE as sort,
      TRUE as search;
SELECT from_state, to_state, transition_reason, transitioned_at
FROM code_notebook_state
ORDER BY transitioned_at;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'console/info-schema/table.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              -- not including breadcrumbs from sqlpage_aide_navigation
              -- not including page title from sqlpage_aide_navigation

              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/console/info-schema''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
SELECT $name || '' Table'' AS title, ''#'' AS link;

SELECT ''title'' AS component, $name AS contents;
SELECT ''table'' AS component;
SELECT
    column_name AS "Column",
    data_type AS "Type",
    is_primary_key AS "PK",
    is_not_null AS "Required",
    default_value AS "Default"
FROM console_information_schema_table
WHERE table_name = $name;

SELECT ''title'' AS component, ''Foreign Keys'' as contents, 2 as level;
SELECT ''table'' AS component;
SELECT
    column_name AS "Column Name",
    foreign_key AS "Foreign Key"
FROM console_information_schema_table_col_fkey
WHERE table_name = $name;

SELECT ''title'' AS component, ''Indexes'' as contents, 2 as level;
SELECT ''table'' AS component;
SELECT
    column_name AS "Column Name",
    index_name AS "Index Name"
FROM console_information_schema_table_col_index
WHERE table_name = $name;

SELECT ''title'' AS component, ''SQL DDL'' as contents, 2 as level;
SELECT ''code'' AS component;
SELECT ''sql'' as language, (SELECT sql_ddl FROM console_information_schema_table WHERE table_name = $name) as contents;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'console/info-schema/view.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              -- not including breadcrumbs from sqlpage_aide_navigation
              -- not including page title from sqlpage_aide_navigation

              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/console/info-schema''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
SELECT $name || '' View'' AS title, ''#'' AS link;

SELECT ''title'' AS component, $name AS contents;
SELECT ''table'' AS component;
SELECT
    column_name AS "Column",
    data_type AS "Type"
FROM console_information_schema_view
WHERE view_name = $name;

SELECT ''title'' AS component, ''SQL DDL'' as contents, 2 as level;
SELECT ''code'' AS component;
SELECT ''sql'' as language, (SELECT sql_ddl FROM console_information_schema_view WHERE view_name = $name) as contents;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'console/sqlpage-files/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/console/sqlpage-files''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, ''SQLPage pages in sqlpage_files table'' AS contents;
SELECT ''table'' AS component,
      ''Path'' as markdown,
      ''Size'' as align_right,
      TRUE as sort,
      TRUE as search;
SELECT
  ''[🚀](/'' || path || '') [📄 '' || path || ''](sqlpage-file.sql?path='' || path || '')'' AS "Path",
  LENGTH(contents) as "Size", last_modified
FROM sqlpage_files
ORDER BY path;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'console/sqlpage-files/sqlpage-file.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              -- not including breadcrumbs from sqlpage_aide_navigation
              -- not including page title from sqlpage_aide_navigation

              
      SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/console/sqlpage-files''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
SELECT $path || '' Path'' AS title, ''#'' AS link;

      SELECT ''title'' AS component, $path AS contents;
      SELECT ''text'' AS component,
             ''```sql
'' || (select contents FROM sqlpage_files where path = $path) || ''
```'' as contents_md;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'console/sqlpage-files/content.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/console/sqlpage-files/content.sql''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, ''SQLPage pages generated from tables and views'' AS contents;
SELECT ''text'' AS component, ''
  - `*.auto.sql` pages are auto-generated "default" content pages for each table and view defined in the database.
  - The `*.sql` companions may be auto-generated redirects to their `*.auto.sql` pair or an app/service might override the `*.sql` to not redirect and supply custom content for any table or view.
  - [View regenerate-auto.sql](/console/sqlpage-files/sqlpage-file.sql?path=console/content/action/regenerate-auto.sql)
  '' AS contents_md;

SELECT ''button'' AS component, ''center'' AS justify;
SELECT ''/console/content/action/regenerate-auto.sql'' AS link, ''info'' AS color, ''Regenerate all "default" table/view content pages'' AS title;

SELECT ''title'' AS component, ''Redirected or overriden content pages'' as contents;
SELECT ''table'' AS component,
      ''Path'' as markdown,
      ''Size'' as align_right,
      TRUE as sort,
      TRUE as search;
SELECT
  ''[🚀](/'' || path || '') [📄 '' || path || ''](sqlpage-file.sql?path='' || path || '')'' AS "Path",
  LENGTH(contents) as "Size", last_modified
FROM sqlpage_files
WHERE path like ''console/content/%''
      AND NOT(path like ''console/content/%.auto.sql'')
      AND NOT(path like ''console/content/action%'')
ORDER BY path;

SELECT ''title'' AS component, ''Auto-generated "default" content pages'' as contents;
SELECT ''table'' AS component,
      ''Path'' as markdown,
      ''Size'' as align_right,
      TRUE as sort,
      TRUE as search;
SELECT
  ''[🚀](/'' || path || '') [📄 '' || path || ''](sqlpage-file.sql?path='' || path || '')'' AS "Path",
  LENGTH(contents) as "Size", last_modified
FROM sqlpage_files
WHERE path like ''console/content/%.auto.sql''
ORDER BY path;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'console/content/action/regenerate-auto.sql',
      '      -- code provenance: `ConsoleSqlPages.infoSchemaContentDML` (file:///home/runner/work/www.surveilr.com/www.surveilr.com/lib/std/web-ui-content/console.ts)

      -- the "auto-generated" tables will be in ''*.auto.sql'' with redirects
      DELETE FROM sqlpage_files WHERE path like ''console/content/table/%.auto.sql'';
      DELETE FROM sqlpage_files WHERE path like ''console/content/view/%.auto.sql'';
      INSERT OR REPLACE INTO sqlpage_files (path, contents)
        SELECT
            ''console/content/'' || tabular_nature || ''/'' || tabular_name || ''.auto.sql'',
            ''SELECT ''''dynamic'''' AS component, sqlpage.run_sql(''''shell/shell.sql'''') AS properties;

              SELECT ''''breadcrumb'''' AS component;
              SELECT ''''Home'''' as title, ''''/'''' AS link;
              SELECT ''''Console'''' as title, ''''/console'''' AS link;
              SELECT ''''Content'''' as title, ''''/console/content'''' AS link;
              SELECT '''''' || tabular_name  || '' '' || tabular_nature || '''''' as title, ''''#'''' AS link;

              SELECT ''''title'''' AS component, '''''' || tabular_name || '' ('' || tabular_nature || '') Content'''' as contents;

              SET total_rows = (SELECT COUNT(*) FROM '' || tabular_name || '');
              SET limit = COALESCE($limit, 50);
              SET offset = COALESCE($offset, 0);
              SET total_pages = ($total_rows + $limit - 1) / $limit;
              SET current_page = ($offset / $limit) + 1;

              SELECT ''''text'''' AS component, '''''' || info_schema_link_full_md || '''''' AS contents_md
              SELECT ''''text'''' AS component,
                ''''- Start Row: '''' || $offset || ''''
'''' ||
                ''''- Rows per Page: '''' || $limit || ''''
'''' ||
                ''''- Total Rows: '''' || $total_rows || ''''
'''' ||
                ''''- Current Page: '''' || $current_page || ''''
'''' ||
                ''''- Total Pages: '''' || $total_pages as contents_md
              WHERE $stats IS NOT NULL;

              -- Display uniform_resource table with pagination
              SELECT ''''table'''' AS component,
                    TRUE AS sort,
                    TRUE AS search,
                    TRUE AS hover,
                    TRUE AS striped_rows,
                    TRUE AS small;
            SELECT * FROM '' || tabular_name || ''
            LIMIT $limit
            OFFSET $offset;

            SELECT ''''text'''' AS component,
                (SELECT CASE WHEN $current_page > 1 THEN ''''[Previous](?limit='''' || $limit || ''''&offset='''' || ($offset - $limit) || '''')'''' ELSE '''''''' END) || '''' '''' ||
                ''''(Page '''' || $current_page || '''' of '''' || $total_pages || '''') '''' ||
                (SELECT CASE WHEN $current_page < $total_pages THEN ''''[Next](?limit='''' || $limit || ''''&offset='''' || ($offset + $limit) || '''')'''' ELSE '''''''' END)
                AS contents_md;''
        FROM console_content_tabular;

      INSERT OR IGNORE INTO sqlpage_files (path, contents)
        SELECT
            ''console/content/'' || tabular_nature || ''/'' || tabular_name || ''.sql'',
            ''SELECT ''''redirect'''' AS component, ''''/console/content/'' || tabular_nature || ''/'' || tabular_name || ''.auto.sql'''' AS link WHERE $stats IS NULL;
'' ||
            ''SELECT ''''redirect'''' AS component, ''''/console/content/'' || tabular_nature || ''/'' || tabular_name || ''.auto.sql?stats='''' || $stats AS link WHERE $stats IS NOT NULL;''
        FROM console_content_tabular;

      -- TODO: add ${this.upsertNavSQL(...)} if we want each of the above to be navigable through DB rows

-- code provenance: `ConsoleSqlPages.console/content/action/regenerate-auto.sql` (file:///home/runner/work/www.surveilr.com/www.surveilr.com/lib/std/web-ui-content/console.ts)
SELECT ''redirect'' AS component, ''/console/sqlpage-files/content.sql'' as link WHERE $redirect is NULL;
SELECT ''redirect'' AS component, $redirect as link WHERE $redirect is NOT NULL;',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'console/sqlpage-nav/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/console/sqlpage-nav''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, ''SQLPage navigation in sqlpage_aide_navigation table'' AS contents;
SELECT ''table'' AS component, TRUE as sort, TRUE as search;
SELECT path, caption, description FROM sqlpage_aide_navigation ORDER BY namespace, parent_path, path, sibling_order;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'console/notebooks/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/console/notebooks''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, ''Code Notebooks'' AS contents;
SELECT ''table'' as component, ''Cell'' as markdown, 1 as search, 1 as sort;
SELECT c.notebook_name,
       ''['' || c.cell_name || ''](notebook-cell.sql?notebook='' || replace(c.notebook_name, '' '', ''%20'') || ''&cell='' || replace(c.cell_name, '' '', ''%20'') || '')'' as Cell,
       c.description,
       k.kernel_name as kernel
  FROM code_notebook_kernel k, code_notebook_cell c
 WHERE k.code_notebook_kernel_id = c.notebook_kernel_id;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'console/notebooks/notebook-cell.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              -- not including breadcrumbs from sqlpage_aide_navigation
              -- not including page title from sqlpage_aide_navigation

              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/console/notebooks''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
SELECT ''Notebook '' || $notebook || '' Cell'' || $cell AS title, ''#'' AS link;

SELECT ''code'' as component;
SELECT $notebook || ''.'' || $cell || '' ('' || k.kernel_name ||'')'' as title,
       COALESCE(c.cell_governance -> ''$.language'', ''sql'') as language,
       c.interpretable_code as contents
  FROM code_notebook_kernel k, code_notebook_cell c
 WHERE c.notebook_name = $notebook
   AND c.cell_name = $cell
   AND k.code_notebook_kernel_id = c.notebook_kernel_id;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'ur/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/ur''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              WITH navigation_cte AS (
    SELECT COALESCE(title, caption) as title, description
      FROM sqlpage_aide_navigation
     WHERE namespace = ''prime'' AND path = ''/ur''
)
SELECT ''list'' AS component, title, description
  FROM navigation_cte;
SELECT caption as title, COALESCE(url, path) as link, description
  FROM sqlpage_aide_navigation
 WHERE namespace = ''prime'' AND parent_path = ''/ur''
 ORDER BY sibling_order;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'ur/info-schema.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/ur/info-schema.sql''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, ''Uniform Resource Tables and Views'' as contents;
SELECT ''table'' AS component,
      ''Name'' AS markdown,
      ''Column Count'' as align_right,
      TRUE as sort,
      TRUE as search;

SELECT
    ''Table'' as "Type",
    ''['' || table_name || ''](/console/info-schema/table.sql?name='' || table_name || '')'' AS "Name",
    COUNT(column_name) AS "Column Count"
FROM console_information_schema_table
WHERE table_name = ''uniform_resource'' OR table_name like ''ur_%''
GROUP BY table_name

UNION ALL

SELECT
    ''View'' as "Type",
    ''['' || view_name || ''](/console/info-schema/view.sql?name='' || view_name || '')'' AS "Name",
    COUNT(column_name) AS "Column Count"
FROM console_information_schema_view
WHERE view_name like ''ur_%''
GROUP BY view_name;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'ur/uniform-resource-files.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              -- not including breadcrumbs from sqlpage_aide_navigation
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/ur/uniform-resource-files.sql'') as contents;
    ;

-- sets up $limit, $offset, and other variables (use pagination.debugVars() to see values in web-ui)
SET total_rows = (SELECT COUNT(*) FROM uniform_resource_file);
SET limit = COALESCE($limit, 50);
SET offset = COALESCE($offset, 0);
SET total_pages = ($total_rows + $limit - 1) / $limit;
SET current_page = ($offset / $limit) + 1;

-- Display uniform_resource table with pagination
SELECT ''table'' AS component,
      ''Uniform Resources'' AS title,
      "Size (bytes)" as align_right,
      TRUE AS sort,
      TRUE AS search,
      TRUE AS hover,
      TRUE AS striped_rows,
      TRUE AS small;
SELECT * FROM uniform_resource_file ORDER BY uniform_resource_id
 LIMIT $limit
OFFSET $offset;

SELECT ''text'' AS component,
    (SELECT CASE WHEN $current_page > 1 THEN ''[Previous](?limit='' || $limit || ''&offset='' || ($offset - $limit) || '')'' ELSE '''' END) || '' '' ||
    ''(Page '' || $current_page || '' of '' || $total_pages || ") " ||
    (SELECT CASE WHEN $current_page < $total_pages THEN ''[Next](?limit='' || $limit || ''&offset='' || ($offset + $limit) || '')'' ELSE '''' END)
    AS contents_md;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'orchestration/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/orchestration''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              WITH navigation_cte AS (
SELECT COALESCE(title, caption) as title, description
    FROM sqlpage_aide_navigation
WHERE namespace = ''prime'' AND path = ''/orchestration''
)
SELECT ''list'' AS component, title, description
    FROM navigation_cte;
SELECT caption as title, COALESCE(url, path) as link, description
    FROM sqlpage_aide_navigation
WHERE namespace = ''prime'' AND parent_path = ''/orchestration''
ORDER BY sibling_order;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'orchestration/info-schema.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/orchestration/info-schema.sql''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, ''Orchestration Tables and Views'' as contents;
SELECT ''table'' AS component,
      ''Name'' AS markdown,
      ''Column Count'' as align_right,
      TRUE as sort,
      TRUE as search;

SELECT
    ''Table'' as "Type",
    ''['' || table_name || ''](/console/info-schema/table.sql?name='' || table_name || '')'' AS "Name",
    COUNT(column_name) AS "Column Count"
FROM console_information_schema_table
WHERE table_name = ''orchestration_session'' OR table_name like ''orchestration_%''
GROUP BY table_name

UNION ALL

SELECT
    ''View'' as "Type",
    ''['' || view_name || ''](/console/info-schema/view.sql?name='' || view_name || '')'' AS "Name",
    COUNT(column_name) AS "Column Count"
FROM console_information_schema_view
WHERE view_name like ''orchestration_%''
GROUP BY view_name;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT
      ''card''                      as component,
      ''Welcome to the Diabetes Research Hub EDGE UI'' as title,
      1                           as columns;

SELECT
      ''About'' as title,
      ''green''                        as color,
      ''white''                  as background_color,
      ''The Diabetes Research Hub (DRH) addresses a growing need for a centralized platform to manage and analyze continuous glucose monitor (CGM) data.Our primary focus is to collect data from studies conducted by various researchers. Initially, we are concentrating on gathering CGM data, with plans to collect additional types of data in the future.'' as description,
      ''home''                 as icon;

SELECT
      ''card''                  as component,
      ''Files Log'' as title,
      1                     as columns;


SELECT
    ''Study Files Log''  as title,
    ''/drh/ingestion-log/index.sql'' as link,
    ''This section provides an overview of the files that have been accepted and converted into database format for research purposes'' as description,
    ''book''                as icon,
    ''red''                    as color;

;

SELECT
      ''card''                  as component,
      ''File Verification Results'' as title,
      1                     as columns;

SELECT
    ''Verification Log'' AS title,
    ''/drh/verification-validation-log/index.sql'' AS link,
    ''Use this section to review the issues identified in the file content and take appropriate corrective actions.'' AS description,
    ''table'' AS icon,
    ''red'' AS color;



SELECT
      ''card''                  as component,
      ''Features '' as title,
      9                     as columns;


SELECT
    ''Study Participant Dashboard''  as title,
    ''/drh/study-participant-dashboard/index.sql'' as link,
    ''The dashboard presents key study details and participant-specific metrics in a clear, organized table format'' as description,
    ''table''                as icon,
    ''red''                    as color;
;




SELECT
    ''Researcher and Associated Information''  as title,
    ''/drh/researcher-related-data/index.sql'' as link,
    ''This section provides detailed information about the individuals , institutions and labs involved in the research study.'' as description,
    ''book''                as icon,
    ''red''                    as color;
;

SELECT
    ''Study ResearchSite Details''  as title,
    ''/drh/study-related-data/index.sql'' as link,
    ''This section provides detailed information about the study , and sites involved in the research study.'' as description,
    ''book''                as icon,
    ''red''                    as color;
;

SELECT
    ''Participant Demographics''  as title,
    ''/drh/participant-related-data/index.sql'' as link,
    ''This section provides detailed information about the the participants involved in the research study.'' as description,
    ''book''                as icon,
    ''red''                    as color;
;

SELECT
    ''Author and Publication Details''  as title,
    ''/drh/author-pub-data/index.sql'' as link,
    ''Information about research publications and the authors involved in the studies are also collected, contributing to the broader understanding and dissemination of research findings.'' as description,
     ''book'' AS icon,
    ''red''                    as color;
;



SELECT
    ''CGM Meta Data and Associated information''  as title,
    ''/drh/cgm-associated-data/index.sql'' as link,
    ''This section provides detailed information about the CGM device used, the relationship between the participant''''s raw CGM tracing file and related metadata, and other pertinent information.'' as description,
    ''book''                as icon,
    ''red''                    as color;

;


SELECT
    ''Raw CGM Data Description'' AS title,
    ''/drh/cgm-data/index.sql'' AS link,
    ''Explore detailed information about glucose levels over time, including timestamp, and glucose value.'' AS description,
    ''book''                as icon,
    ''red''                    as color;                

SELECT
    ''Combined CGM Tracing'' AS title,
    ''/drh/cgm-combined-data/index.sql'' AS link,
    ''Explore the comprehensive CGM dataset, integrating glucose monitoring data from all participants for in-depth analysis of glycemic patterns and trends across the study.'' AS description,
    ''book''                as icon,
    ''red''                    as color;         


SELECT
    ''PHI De-Identification Results'' AS title,
    ''/drh/deidentification-log/index.sql'' AS link,
    ''Explore the results of PHI de-identification and review which columns have been modified.'' AS description,
    ''book''                as icon,
    ''red''                    as color;
;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/researcher-related-data/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/researcher-related-data''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

               SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/researcher-related-data/index.sql'') as contents;
    ;

SELECT
  ''text'' as component,
  ''The Diabetes Research Hub collaborates with a diverse group of researchers or investigators dedicated to advancing diabetes research. This section provides detailed information about the individuals and institutions involved in the research studies.'' as contents;


SELECT
  ''text'' as component,
  ''Researcher / Investigator '' as title;
SELECT
  ''These are scientific professionals and medical experts who design and conduct studies related to diabetes management and treatment. Their expertise ranges from clinical research to data analysis, and they are crucial in interpreting results and guiding future research directions.Principal investigators lead the research projects, overseeing the study design, implementation, and data collection. They ensure the research adheres to ethical standards and provides valuable insights into diabetes management.'' as contents;
SELECT ''table'' as component, 1 as search, 1 as sort, 1 as hover, 1 as striped_rows;
SELECT * from drh_investigator;

SELECT
  ''text'' as component,
  ''Institution'' as title;
SELECT
  ''The researchers and investigators are associated with various institutions, including universities, research institutes, and hospitals. These institutions provide the necessary resources, facilities, and support for conducting high-quality research. Each institution brings its unique strengths and expertise to the collaborative research efforts.'' as contents;
SELECT ''table'' as component, 1 as search, 1 as sort, 1 as hover, 1 as striped_rows;
SELECT * from drh_institution;


SELECT
  ''text'' as component,
  ''Lab'' as title;
SELECT
  ''Within these institutions, specialized labs are equipped with state-of-the-art technology to conduct diabetes research. These labs focus on different aspects of diabetes studies, such as glucose monitoring, metabolic analysis, and data processing. They play a critical role in executing experiments, analyzing samples, and generating data that drive research conclusions.'' as contents;
SELECT ''table'' as component, 1 as search, 1 as sort, 1 as hover, 1 as striped_rows;
SELECT * from drh_lab;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/study-related-data/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/study-related-data''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              
  SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/study-related-data/index.sql'') as contents;
    ;
    SELECT
  ''text'' as component,
  ''
  In Continuous Glucose Monitoring (CGM) research, studies are designed to evaluate the effectiveness, accuracy, and impact of CGM systems on diabetes management. Each study aims to gather comprehensive data on glucose levels, treatment efficacy, and patient outcomes to advance our understanding of diabetes care.

  ### Study Details

  - **Study ID**: A unique identifier assigned to each study.
  - **Study Name**: The name or title of the study.
  - **Start Date**: The date when the study begins.
  - **End Date**: The date when the study concludes.
  - **Treatment Modalities**: Different treatment methods or interventions used in the study.
  - **Funding Source**: The source(s) of financial support for the study.
  - **NCT Number**: ClinicalTrials.gov identifier for the study.
  - **Study Description**: A description of the study’s objectives, methodology, and scope.

  '' as contents_md;

  SELECT ''table'' as component, 1 as search, 1 as sort, 1 as hover, 1 as striped_rows;
  SELECT * from drh_study;


      SELECT
          ''text'' as component,
          ''

## Site Information

Research sites are locations where the studies are conducted. They include clinical settings where participants are recruited, monitored, and data is collected.

### Site Details

  - **Study ID**: A unique identifier for the study associated with the site.
  - **Site ID**: A unique identifier for each research site.
  - **Site Name**: The name of the institution or facility where the research is carried out.
  - **Site Type**: The type or category of the site (e.g., hospital, clinic).

      '' as contents_md;

      SELECT ''table'' as component, 1 as search, 1 as sort, 1 as hover, 1 as striped_rows;
      SELECT * from drh_site;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/uniform-resource-participant.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/uniform-resource-participant.sql''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/uniform-resource-participant.sql'') as contents;
    ;


SET total_rows = (SELECT COUNT(*) FROM drh_participant);
SET limit = COALESCE($limit, 50);
SET offset = COALESCE($offset, 0);
SET total_pages = ($total_rows + $limit - 1) / $limit;
SET current_page = ($offset / $limit) + 1;

-- Display uniform_resource table with pagination
SELECT ''table'' AS component,
      TRUE AS sort,
      TRUE AS search;
SELECT * FROM drh_participant
 LIMIT $limit
OFFSET $offset;

SELECT ''text'' AS component,
    (SELECT CASE WHEN $current_page > 1 THEN ''[Previous](?limit='' || $limit || ''&offset='' || ($offset - $limit) || '')'' ELSE '''' END) || '' '' ||
    ''(Page '' || $current_page || '' of '' || $total_pages || ") " ||
    (SELECT CASE WHEN $current_page < $total_pages THEN ''[Next](?limit='' || $limit || ''&offset='' || ($offset + $limit) || '')'' ELSE '''' END)
    AS contents_md;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/author-pub-data/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/author-pub-data''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              
  SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/author-pub-data/index.sql'') as contents;
    ;

  SELECT
  ''text'' as component,
  ''

## Authors

This section contains information about the authors involved in study publications. Each author plays a crucial role in contributing to the research, and their details are important for recognizing their contributions.

### Author Details

- **Author ID**: A unique identifier for the author.
- **Name**: The full name of the author.
- **Email**: The email address of the author.
- **Investigator ID**: A unique identifier for the investigator the author is associated with.
- **Study ID**: A unique identifier for the study associated with the author.


      '' as contents_md;

  SELECT ''table'' as component, 1 as search, 1 as sort, 1 as hover, 1 as striped_rows;
  SELECT * from drh_author;
  SELECT
  ''text'' as component,
  ''
## Publications Overview

This section provides information about the publications resulting from a study. Publications are essential for sharing research findings with the broader scientific community.

### Publication Details

- **Publication ID**: A unique identifier for the publication.
- **Publication Title**: The title of the publication.
- **Digital Object Identifier (DOI)**: Identifier for the digital object associated with the publication.
- **Publication Site**: The site or journal where the publication was released.
- **Study ID**: A unique identifier for the study associated with the publication.


  '' as contents_md;

  SELECT ''table'' as component, 1 as search, 1 as sort, 1 as hover, 1 as striped_rows;
  SELECT * from drh_publication;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/deidentification-log/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/deidentification-log''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/deidentification-log/index.sql'') as contents;
    ;

/*
SELECT
''breadcrumb'' as component;
SELECT
    ''Home'' as title,
    ''index.sql''    as link;
SELECT
    ''DeIdentificationResults'' as title;
    */

SELECT
  ''text'' as component,
  ''DeIdentification Results'' as title;
 SELECT
  ''The DeIdentification Results section provides a view of the outcomes from the de-identification process '' as contents;


SELECT ''table'' as component, 1 as search, 1 as sort, 1 as hover, 1 as striped_rows;
SELECT input_text as "deidentified column", orch_started_at,orch_finished_at ,diagnostics_md from drh_vw_orchestration_deidentify;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/cgm-combined-data/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/cgm-combined-data''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              
  SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/cgm-combined-data/index.sql'') as contents;
    ;


    SELECT
''text'' as component,
''

The **Combined CGM Tracing** refers to a consolidated dataset of continuous glucose monitoring (CGM) data, collected from multiple participants in a research study. CGM devices track glucose levels at regular intervals throughout the day, providing detailed insights into the participants'''' glycemic control over time.

In a research study, this combined dataset is crucial for analyzing glucose trends across different participants and understanding overall patterns in response to interventions or treatments. The **Combined CGM Tracing** dataset typically includes:
- **Participant ID**: A unique identifier for each participant, ensuring the data is de-identified while allowing for tracking individual responses.
- **Date_Time**: The timestamp for each CGM reading, formatted uniformly to allow accurate time-based analysis.(YYYY-MM-DD HH:MM:SS)
- **CGM_Value**: The recorded glucose level at each time point, often converted to a standard unit (e.g., mg/dL or mmol/L) and stored as a real number for precise calculations.

This combined view enables researchers to perform comparative analyses, evaluate glycemic variability, and assess overall glycemic control across participants, which is essential for understanding the efficacy of treatments or interventions in the study. By aggregating data from multiple sources, researchers can identify population-level trends while maintaining the integrity of individual data. 

'' as contents_md;

SET total_rows = (SELECT COUNT(*) FROM combined_cgm_tracing);
SET limit = COALESCE($limit, 50);
SET offset = COALESCE($offset, 0);
SET total_pages = ($total_rows + $limit - 1) / $limit;
SET current_page = ($offset / $limit) + 1;

-- Display uniform_resource table with pagination
SELECT ''table'' AS component,
    TRUE AS sort,
    TRUE AS search;
SELECT * FROM combined_cgm_tracing 
LIMIT $limit
OFFSET $offset;

SELECT ''text'' AS component,
    (SELECT CASE WHEN $current_page > 1 THEN ''[Previous](?limit='' || $limit || ''&offset='' || ($offset - $limit) || '')'' ELSE '''' END) || '' '' ||
    ''(Page '' || $current_page || '' of '' || $total_pages || ") " ||
    (SELECT CASE WHEN $current_page < $total_pages THEN ''[Next](?limit='' || $limit || ''&offset='' || ($offset + $limit) || '')'' ELSE '''' END)
    AS contents_md;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/cgm-associated-data/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/cgm-associated-data''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              
  SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/cgm-associated-data/index.sql'') as contents;
    ;

      /*SELECT
  ''breadcrumb'' as component;
  SELECT
      ''Home'' as title,
      ''index.sql''    as link;
  SELECT
      ''CGM File Meta Data'' as title;
      */



    SELECT
''text'' as component,
''

CGM file metadata provides essential information about the Continuous Glucose Monitoring (CGM) data files used in research studies. This metadata is crucial for understanding the context and quality of the data collected.

### Metadata Details

- **Metadata ID**: A unique identifier for the metadata record.
- **Device Name**: The name of the CGM device used to collect the data.
- **Device ID**: A unique identifier for the CGM device.
- **Source Platform**: The platform or system from which the CGM data originated.
- **Patient ID**: A unique identifier for the patient from whom the data was collected.
- **File Name**: The name of the uploaded CGM data file.
- **File Format**: The format of the uploaded file (e.g., CSV, Excel).
- **File Upload Date**: The date when the file was uploaded to the system.
- **Data Start Date**: The start date of the data period covered by the file.
- **Data End Date**: The end date of the data period covered by the file.
- **Study ID**: A unique identifier for the study associated with the CGM data.


'' as contents_md;

SET total_rows = (SELECT COUNT(*) FROM drh_cgmfilemetadata_view);
SET limit = COALESCE($limit, 50);
SET offset = COALESCE($offset, 0);
SET total_pages = ($total_rows + $limit - 1) / $limit;
SET current_page = ($offset / $limit) + 1;

-- Display uniform_resource table with pagination
SELECT ''table'' AS component,
    TRUE AS sort,
    TRUE AS search;
SELECT * FROM drh_cgmfilemetadata_view
LIMIT $limit
OFFSET $offset;

SELECT ''text'' AS component,
    (SELECT CASE WHEN $current_page > 1 THEN ''[Previous](?limit='' || $limit || ''&offset='' || ($offset - $limit) || '')'' ELSE '''' END) || '' '' ||
    ''(Page '' || $current_page || '' of '' || $total_pages || ") " ||
    (SELECT CASE WHEN $current_page < $total_pages THEN ''[Next](?limit='' || $limit || ''&offset='' || ($offset + $limit) || '')'' ELSE '''' END)
    AS contents_md;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/cgm-data/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/cgm-data''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/cgm-data/index.sql'') as contents;
    ;

SELECT
''text'' as component,
''
The raw CGM data includes the following key elements.

- **Date_Time**:
The exact date and time when the glucose level was recorded. This is crucial for tracking glucose trends and patterns over time. The timestamp is usually formatted as YYYY-MM-DD HH:MM:SS.
- **CGM_Value**:
The measured glucose level at the given timestamp. This value is typically recorded in milligrams per deciliter (mg/dL) or millimoles per liter (mmol/L) and provides insight into the participant''''s glucose fluctuations throughout the day.'' as contents_md;

SELECT ''table'' AS component,
        ''Table'' AS markdown,
        ''Column Count'' as align_right,
        TRUE as sort,
        TRUE as search;
SELECT ''['' || table_name || ''](raw-cgm/'' || table_name || ''.sql)'' AS "Table"
FROM drh_raw_cgm_table_lst;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/cgm-data/data.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              -- not including breadcrumbs from sqlpage_aide_navigation
              -- not including page title from sqlpage_aide_navigation

              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/cgm-data''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
SELECT $name || '' Table'' AS title, ''#'' AS link;


SELECT ''title'' AS component, $name AS contents;

-- Initialize pagination
SET total_rows = (SELECT COUNT(*) FROM $name);
SET limit = COALESCE($limit, 50);
SET offset = COALESCE($offset, 0);
SET total_pages = ($total_rows + $limit - 1) / $limit;
SET current_page = ($offset / $limit) + 1;

-- Display table with pagination
SELECT ''table'' AS component,
      TRUE AS sort,
      TRUE AS search;
SELECT * FROM $name
LIMIT $limit
OFFSET $offset;

SELECT ''text'' AS component,
    (SELECT CASE WHEN $current_page > 1 THEN ''[Previous](?limit='' || $limit || ''&offset='' || ($offset - $limit) || '')'' ELSE '''' END) || '' '' ||
    ''(Page '' || $current_page || '' of '' || $total_pages || ") " ||
    (SELECT CASE WHEN $current_page < $total_pages THEN ''[Next](?limit='' || $limit || ''&offset='' || ($offset + $limit) || '')'' ELSE '''' END)
    AS contents_md;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/ingestion-log/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/ingestion-log''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/ingestion-log/index.sql'') as contents;
    ;

SELECT
  ''text'' as component,
  ''Study Files'' as title;
 SELECT
  ''
  This section provides an overview of the files that have been accepted and converted into database format for research purposes. The conversion process ensures that data from various sources is standardized, making it easier for researchers to analyze and draw meaningful insights.
  Additionally, the corresponding database table names generated from these files are listed for reference.'' as contents;

 SET total_rows = (SELECT COUNT(*) FROM drh_study_files_table_info);
SET limit = COALESCE($limit, 50);
SET offset = COALESCE($offset, 0);
SET total_pages = ($total_rows + $limit - 1) / $limit;
SET current_page = ($offset / $limit) + 1;

  SELECT ''table'' AS component,
  TRUE AS sort,
  TRUE AS search;
  SELECT file_name,file_format, table_name FROM drh_study_files_table_info
  LIMIT $limit
  OFFSET $offset;

  SELECT ''text'' AS component,
    (SELECT CASE WHEN $current_page > 1 THEN ''[Previous](?limit='' || $limit || ''&offset='' || ($offset - $limit) || '')'' ELSE '''' END) || '' '' ||
    ''(Page '' || $current_page || '' of '' || $total_pages || ") " ||
    (SELECT CASE WHEN $current_page < $total_pages THEN ''[Next](?limit='' || $limit || ''&offset='' || ($offset + $limit) || '')'' ELSE '''' END)
    AS contents_md;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/participant-info/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/participant-info''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              
  SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/participant-info/index.sql'') as contents;
    ;

    SELECT
     ''card''     as component,
     '''' as title,
      1         as columns;
    SELECT 
     ''The Participants Detail page is a comprehensive report that includes glucose statistics, such as the Ambulatory Glucose Profile (AGP), Glycemia Risk Index (GRI), Daily Glucose Profile, and all other metrics data.'' as description;
  
select 
    ''form''            as component,
    ''Filter by Date Range''   as title,
    ''Submit'' as validate,    
    ''Clear''           as reset;
select 
    ''start_date'' as name,
    ''Start Date'' as label,
    ''2017-11-02'' as value,
    ''date''       as type,
    6            as width;
select 
    ''end_date'' as name,
    ''End Date'' as label,
    ''2018-02-23''  as value,
    ''date''       as type,
    6             as width;



  SELECT
    ''datagrid'' AS component;
  SELECT
      ''MRN: '' || participant_id || '''' AS title,
      '' '' AS description
  FROM
      drh_participant
  WHERE participant_id = $participant_id;

  SELECT
      ''Study: '' || study_arm || '''' AS title,
      '' '' AS description
  FROM
      drh_participant
  WHERE participant_id = $participant_id;

  
  SELECT
      ''Age: ''|| age || '' Years'' AS title,
      '' '' AS description
  FROM
      drh_participant
  WHERE participant_id = $participant_id;

  SELECT
      ''hba1c: '' || baseline_hba1c || '''' AS title,
      '' '' AS description
  FROM
      drh_participant
  WHERE participant_id = $participant_id;

  SELECT
      ''BMI: ''|| bmi || '''' AS title,
      '' '' AS description
  FROM
      drh_participant
  WHERE participant_id = $participant_id;

  SELECT
      ''Diabetes Type: ''|| diabetes_type || ''''  AS title,
      '' '' AS description
  FROM
      drh_participant
  WHERE participant_id = $participant_id;

  SELECT
      strftime(''Generated: %Y-%m-%d %H:%M:%S'', ''now'') AS title,
      '' '' AS description
  

  SELECT
     ''card''     as component,
     '''' as title,
      2         as columns;

  SELECT
     ''GLUCOSE STATISTICS AND TARGETS'' AS title,
     '''' AS description
  FROM
      drh_study_vanity_metrics_details;

  SELECT

      ''Goals for Type 1 and Type 2 Diabetes'' AS title,
     '''' AS description
  FROM
    drh_number_cgm_count;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/study-participant-dashboard/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/study-participant-dashboard''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/study-participant-dashboard/index.sql'') as contents;
    ;


SELECT
''datagrid'' AS component;

SELECT
    ''Study Name'' AS title,
    '''' || study_name || '''' AS description
FROM
    drh_study_vanity_metrics_details;

SELECT
    ''Start Date'' AS title,
    '''' || start_date || '''' AS description
FROM
    drh_study_vanity_metrics_details;

SELECT
    ''End Date'' AS title,
    '''' || end_date || '''' AS description
FROM
    drh_study_vanity_metrics_details;

SELECT
    ''NCT Number'' AS title,
    '''' || nct_number || '''' AS description
FROM
    drh_study_vanity_metrics_details;




SELECT
   ''card''     as component,
   '''' as title,
    4         as columns;

SELECT
   ''Total Number Of Participants'' AS title,
   '''' || total_number_of_participants || '''' AS description
FROM
    drh_study_vanity_metrics_details;

SELECT

    ''Total CGM Files'' AS title,
   '''' || number_of_cgm_raw_files || '''' AS description
FROM
  drh_number_cgm_count;



SELECT
   ''% Female'' AS title,
   '''' || percentage_of_females || '''' AS description
FROM
    drh_study_vanity_metrics_details;


SELECT
   ''Average Age'' AS title,
   '''' || average_age || '''' AS description
FROM
    drh_study_vanity_metrics_details;




SELECT
''datagrid'' AS component;


SELECT
    ''Study Description'' AS title,
    '''' || study_description || '''' AS description
FROM
    drh_study_vanity_metrics_details;

    SELECT
    ''Study Team'' AS title,
    '''' || investigators || '''' AS description
FROM
    drh_study_vanity_metrics_details;


    SELECT
   ''card''     as component,
   '''' as title,
    1         as columns;

    SELECT
    ''Device Wise Raw CGM File Count'' AS title,
    GROUP_CONCAT('' '' || devicename || '': '' || number_of_files || '''') AS description
    FROM
        drh_device_file_count_view;

        SELECT
''text'' as component,
''# Participant Dashboard'' as contents_md;

    SET total_rows = (SELECT COUNT(*) FROM study_combined_dashboard_participant_metrics_view);
SET limit = COALESCE($limit, 50);
SET offset = COALESCE($offset, 0);
SET total_pages = ($total_rows + $limit - 1) / $limit;
SET current_page = ($offset / $limit) + 1;

  -- Display uniform_resource table with pagination
  SELECT ''table'' AS component,
        ''participant_id'' as markdown,
        TRUE AS sort,
        TRUE AS search;        
  SELECT format(''[%s](/drh/participant-info/index.sql?participant_id=%s)'',participant_id, participant_id) as participant_id,gender,age,study_arm,baseline_hba1c,tir,tar_vh,tar_h,tbr_l,tbr_vl,tar,tbr,gmi,percent_gv,gri,days_of_wear,data_start_date,data_end_date FROM study_combined_dashboard_participant_metrics_view
  LIMIT $limit
  OFFSET $offset;

  SELECT ''text'' AS component,
    (SELECT CASE WHEN $current_page > 1 THEN ''[Previous](?limit='' || $limit || ''&offset='' || ($offset - $limit) || '')'' ELSE '''' END) || '' '' ||
    ''(Page '' || $current_page || '' of '' || $total_pages || ") " ||
    (SELECT CASE WHEN $current_page < $total_pages THEN ''[Next](?limit='' || $limit || ''&offset='' || ($offset + $limit) || '')'' ELSE '''' END)
    AS contents_md;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/verification-validation-log/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/verification-validation-log''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              
  SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/verification-validation-log/index.sql'') as contents;
    ;

  SELECT
    ''text'' as component,
    ''
    Validation is a detailed process where we assess if the data within the files conforms to expecuted rules or constraints. This step ensures that the content of the files is both correct and meaningful before they are utilized for further processing.'' as contents;



SELECT
  ''steps'' AS component,
  TRUE AS counter,
  ''green'' AS color;


SELECT
  ''Check the Validation Log'' AS title,
  ''file'' AS icon,
  ''#'' AS link,
  ''If the log is empty, no action is required. Your files are good to go! If the log has entries, follow the steps below to fix any issues.'' AS description;


SELECT
  ''Note the Issues'' AS title,
  ''note'' AS icon,
  ''#'' AS link,
  ''Review the log to see what needs fixing for each file. Note them down to make a note on what needs to be changed in each file.'' AS description;


SELECT
  ''Stop the Edge UI'' AS title,
  ''square-rounded-x'' AS icon,
  ''#'' AS link,
  ''Make sure to stop the UI (press CTRL+C in the terminal).'' AS description;


SELECT
  ''Make Corrections in Files'' AS title,
  ''edit'' AS icon,
  ''#'' AS link,
  ''Edit the files according to the instructions provided in the log. For example, if a file is empty, fill it with the correct data.'' AS description;


SELECT
  ''Copy the modified Files to the folder'' AS title,
  ''copy'' AS icon,
  ''#'' AS link,
  ''Once you’ve made the necessary changes, replace the old files with the updated ones in the folder.'' AS description;


SELECT
  ''Execute the automated script again'' AS title,
  ''retry'' AS icon,
  ''#'' AS link,
  ''Run the command again to perform file conversion.'' AS description;


SELECT
  ''Repeat the steps until issues are resolved'' AS title,
  ''refresh'' AS icon,
  ''#'' AS link,
  ''Continue this process until the log is empty and all issues are resolved'' AS description;


SELECT
    ''text'' as component,
    ''
    Reminder: Keep updating and re-running the process until you see no entries in the log below.'' as contents;


    SET total_rows = (SELECT COUNT(*) FROM drh_vandv_orch_issues);
SET limit = COALESCE($limit, 50);
SET offset = COALESCE($offset, 0);
SET total_pages = ($total_rows + $limit - 1) / $limit;
SET current_page = ($offset / $limit) + 1;

    SELECT ''table'' AS component,
    TRUE AS sort,
    TRUE AS search;
    SELECT * FROM drh_vandv_orch_issues
    LIMIT $limit
    OFFSET $offset;

    SELECT ''text'' AS component,
    (SELECT CASE WHEN $current_page > 1 THEN ''[Previous](?limit='' || $limit || ''&offset='' || ($offset - $limit) || '')'' ELSE '''' END) || '' '' ||
    ''(Page '' || $current_page || '' of '' || $total_pages || ") " ||
    (SELECT CASE WHEN $current_page < $total_pages THEN ''[Next](?limit='' || $limit || ''&offset='' || ($offset + $limit) || '')'' ELSE '''' END)
    AS contents_md;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;
INSERT INTO sqlpage_files (path, contents, last_modified) VALUES (
      'drh/participant-related-data/index.sql',
      '              SELECT ''dynamic'' AS component, sqlpage.run_sql(''shell/shell.sql'') AS properties;
              SELECT ''breadcrumb'' as component;
WITH RECURSIVE breadcrumbs AS (
    SELECT
        COALESCE(abbreviated_caption, caption) AS title,
        COALESCE(url, path) AS link,
        parent_path, 0 AS level,
        namespace
    FROM sqlpage_aide_navigation
    WHERE namespace = ''prime'' AND path = ''/drh/participant-related-data''
    UNION ALL
    SELECT
        COALESCE(nav.abbreviated_caption, nav.caption) AS title,
        COALESCE(nav.url, nav.path) AS link,
        nav.parent_path, b.level + 1, nav.namespace
    FROM sqlpage_aide_navigation nav
    INNER JOIN breadcrumbs b ON nav.namespace = b.namespace AND nav.path = b.parent_path
)
SELECT title, link FROM breadcrumbs ORDER BY level DESC;
              -- not including page title from sqlpage_aide_navigation

              
  SELECT ''title'' AS component, (SELECT COALESCE(title, caption)
    FROM sqlpage_aide_navigation
   WHERE namespace = ''prime'' AND path = ''/drh/participant-related-data/index.sql'') as contents;
    ;

  SELECT
      ''text'' as component,
      ''
## Participant Information

Participants are individuals who volunteer to take part in CGM research studies. Their data is crucial for evaluating the performance of CGM systems and their impact on diabetes management.

### Participant Details

  - **Participant ID**: A unique identifier assigned to each participant.
  - **Study ID**: A unique identifier for the study in which the participant is involved.
  - **Site ID**: The identifier for the site where the participant is enrolled.
  - **Diagnosis ICD**: The diagnosis code based on the International Classification of Diseases (ICD) system.
  - **Med RxNorm**: The medication code based on the RxNorm system.
  - **Treatment Modality**: The type of treatment or intervention administered to the participant.
  - **Gender**: The gender of the participant.
  - **Race Ethnicity**: The race and ethnicity of the participant.
  - **Age**: The age of the participant.
  - **BMI**: The Body Mass Index (BMI) of the participant.
  - **Baseline HbA1c**: The baseline Hemoglobin A1c level of the participant.
  - **Diabetes Type**: The type of diabetes diagnosed for the participant.
  - **Study Arm**: The study arm or group to which the participant is assigned.


      '' as contents_md;

      SET total_rows = (SELECT COUNT(*) FROM drh_participant);
SET limit = COALESCE($limit, 50);
SET offset = COALESCE($offset, 0);
SET total_pages = ($total_rows + $limit - 1) / $limit;
SET current_page = ($offset / $limit) + 1;

    -- Display uniform_resource table with pagination
    SELECT ''table'' AS component,
          TRUE AS sort,
          TRUE AS search;
    SELECT * FROM drh_participant
     LIMIT $limit
    OFFSET $offset;

    SELECT ''text'' AS component,
    (SELECT CASE WHEN $current_page > 1 THEN ''[Previous](?limit='' || $limit || ''&offset='' || ($offset - $limit) || '')'' ELSE '''' END) || '' '' ||
    ''(Page '' || $current_page || '' of '' || $total_pages || ") " ||
    (SELECT CASE WHEN $current_page < $total_pages THEN ''[Next](?limit='' || $limit || ''&offset='' || ($offset + $limit) || '')'' ELSE '''' END)
    AS contents_md;
            ',
      CURRENT_TIMESTAMP)
  ON CONFLICT(path) DO UPDATE SET contents = EXCLUDED.contents, last_modified = CURRENT_TIMESTAMP;