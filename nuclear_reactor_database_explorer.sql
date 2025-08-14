BEGIN;

-- Drop and recreate schema for a clean build during development.
DROP SCHEMA IF EXISTS nuclear CASCADE;
CREATE SCHEMA nuclear;
SET search_path = nuclear, public;

-- Optional, but nice for name consistency.
SET client_min_messages = WARNING;

-- 1. Lookup tables and domains
--    Keep enumerations in tables for transparency and easy updates.

-- 1.1 Countries
CREATE TABLE countries (
    country_id       BIGSERIAL PRIMARY KEY,
    name             TEXT        NOT NULL,
    iso2             CHAR(2)     NOT NULL,
    iso3             CHAR(3)     NOT NULL,
    region           TEXT        NULL,
    CONSTRAINT uq_countries_iso2 UNIQUE (iso2),
    CONSTRAINT uq_countries_iso3 UNIQUE (iso3),
    CONSTRAINT uq_countries_name UNIQUE (name),
    CONSTRAINT ck_countries_iso2 CHECK (iso2 ~ '^[A-Z]{2}$'),
    CONSTRAINT ck_countries_iso3 CHECK (iso3 ~ '^[A-Z]{3}$')
);

-- 1.2 Organization types, for operators, owners, developers, etc.
CREATE TABLE organization_types (
    organization_type_id BIGSERIAL PRIMARY KEY,
    code                 TEXT NOT NULL UNIQUE,   -- operator, owner, developer, regulator, vendor
    description          TEXT NOT NULL
);

-- 1.3 Organizations, such as operators and owners
CREATE TABLE organizations (
    organization_id      BIGSERIAL PRIMARY KEY,
    name                 TEXT NOT NULL,
    organization_type_id BIGINT NOT NULL REFERENCES organization_types(organization_type_id),
    country_id           BIGINT NOT NULL REFERENCES countries(country_id),
    website              TEXT NULL,
    CONSTRAINT uq_organizations_name UNIQUE (name)
);

-- 1.4 Reactor type families, such as PWR, BWR, PHWR, etc.
CREATE TABLE reactor_families (
    reactor_family_id BIGSERIAL PRIMARY KEY,
    code              TEXT NOT NULL UNIQUE,   -- PWR, BWR, PHWR, GCR, AGR, FBR, HTGR, MSR, Other
    description       TEXT NOT NULL
);

-- 1.5 Detailed reactor designs, linked to a family
--     You can add attributes that are useful for analytics.
CREATE TABLE reactor_designs (
    reactor_design_id       BIGSERIAL PRIMARY KEY,
    name                    TEXT NOT NULL UNIQUE,      -- e.g., AP1000, EPR, CANDU 6, VVER-1200
    reactor_family_id       BIGINT NOT NULL REFERENCES reactor_families(reactor_family_id),
    neutron_spectrum        TEXT NOT NULL CHECK (neutron_spectrum IN ('thermal', 'fast', 'epithermal')),
    primary_coolant         TEXT NULL,                 -- e.g., light water, heavy water, helium, liquid sodium
    moderator               TEXT NULL,                 -- e.g., light water, heavy water, graphite, none
    typical_thermal_mw      NUMERIC(8,2) NULL CHECK (typical_thermal_mw IS NULL OR typical_thermal_mw > 0),
    typical_electric_mw     NUMERIC(8,2) NULL CHECK (typical_electric_mw IS NULL OR typical_electric_mw > 0),
    fuel_form               TEXT NULL,                 -- e.g., UO2, MOX, TRISO, metallic U
    typical_enrichment_pct  NUMERIC(4,2) NULL CHECK (typical_enrichment_pct IS NULL OR typical_enrichment_pct >= 0)
);

-- 1.6 Unit status lookup
CREATE TABLE unit_status_lu (
    unit_status_id BIGSERIAL PRIMARY KEY,
    code           TEXT NOT NULL UNIQUE,   -- PLANNED, UNDER_CONSTRUCTION, OPERATIONAL, SHUTDOWN, DECOMMISSIONED
    description    TEXT NOT NULL,
    is_active      BOOLEAN NOT NULL DEFAULT FALSE
);

-- 2. Physical sites and units

-- 2.1 Sites, that can host one or more reactor units
CREATE TABLE sites (
    site_id        BIGSERIAL PRIMARY KEY,
    name           TEXT NOT NULL,
    country_id     BIGINT NOT NULL REFERENCES countries(country_id),
    location_name  TEXT NULL,             -- province, state, or locality
    latitude_deg   NUMERIC(9,6) NULL CHECK (latitude_deg BETWEEN -90 AND 90),
    longitude_deg  NUMERIC(9,6) NULL CHECK (longitude_deg BETWEEN -180 AND 180),
    CONSTRAINT uq_site_name_country UNIQUE (name, country_id)
);

-- 2.2 Reactor units
CREATE TABLE units (
    unit_id                     BIGSERIAL PRIMARY KEY,
    site_id                     BIGINT NOT NULL REFERENCES sites(site_id),
    unit_name                   TEXT NOT NULL,     -- local name or number, e.g., Unit 1
    reactor_design_id           BIGINT NOT NULL REFERENCES reactor_designs(reactor_design_id),
    operator_id                 BIGINT NOT NULL REFERENCES organizations(organization_id),
    owner_id                    BIGINT NULL  REFERENCES organizations(organization_id),

    thermal_power_mw            NUMERIC(8,2) NULL CHECK (thermal_power_mw IS NULL OR thermal_power_mw > 0),
    gross_electric_mw           NUMERIC(8,2) NULL CHECK (gross_electric_mw IS NULL OR gross_electric_mw > 0),
    net_electric_mw             NUMERIC(8,2) NULL CHECK (net_electric_mw   IS NULL OR net_electric_mw   > 0),
    load_factor_design_pct      NUMERIC(5,2) NULL CHECK (load_factor_design_pct IS NULL OR (load_factor_design_pct >= 0 AND load_factor_design_pct <= 100)),
    design_life_years           INTEGER NULL CHECK (design_life_years IS NULL OR design_life_years > 0),

    construction_start_date     DATE NULL,
    first_criticality_date      DATE NULL,
    grid_connection_date        DATE NULL,
    commercial_operation_date   DATE NULL,
    permanent_shutdown_date     DATE NULL,

    unit_status_id              BIGINT NOT NULL REFERENCES unit_status_lu(unit_status_id),

    -- Simple quality checks on chronology
    CONSTRAINT uq_unit_name_per_site UNIQUE (site_id, unit_name),
    CONSTRAINT ck_units_dates_order CHECK (
        (construction_start_date IS NULL OR first_criticality_date    IS NULL OR construction_start_date    <= first_criticality_date)
        AND (first_criticality_date  IS NULL OR grid_connection_date  IS NULL OR first_criticality_date     <= grid_connection_date)
        AND (grid_connection_date     IS NULL OR commercial_operation_date IS NULL OR grid_connection_date  <= commercial_operation_date)
        AND (commercial_operation_date IS NULL OR permanent_shutdown_date   IS NULL OR commercial_operation_date <= permanent_shutdown_date)
    )
);

-- 2.3 Unit status history to preserve changes over time
CREATE TABLE unit_status_history (
    unit_status_history_id BIGSERIAL PRIMARY KEY,
    unit_id                BIGINT NOT NULL REFERENCES units(unit_id) ON DELETE CASCADE,
    unit_status_id         BIGINT NOT NULL REFERENCES unit_status_lu(unit_status_id),
    valid_from             TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_to               TIMESTAMPTZ NULL,
    note                   TEXT NULL
);

-- 3. Generation statistics
--    Store annual generation to compute capacity factors and trends.
CREATE TABLE generation_stats (
    generation_id     BIGSERIAL PRIMARY KEY,
    unit_id           BIGINT NOT NULL REFERENCES units(unit_id) ON DELETE CASCADE,
    calendar_year     INTEGER NOT NULL CHECK (calendar_year BETWEEN 1950 AND 2100),
    net_generation_mwh NUMERIC(14,2) NOT NULL CHECK (net_generation_mwh >= 0),
    -- Optional override for average net capacity this year if uprates or derates occurred.
    avg_net_capacity_mw NUMERIC(8,2) NULL CHECK (avg_net_capacity_mw IS NULL OR avg_net_capacity_mw > 0),
    CONSTRAINT uq_generation_unit_year UNIQUE (unit_id, calendar_year)
);

-- 4. Indexing strategy
CREATE INDEX idx_sites_country ON sites(country_id);
CREATE INDEX idx_units_status  ON units(unit_status_id);
CREATE INDEX idx_units_comop   ON units(commercial_operation_date);
CREATE INDEX idx_units_design  ON units(reactor_design_id);
CREATE INDEX idx_gen_unit_year ON generation_stats(unit_id, calendar_year);

-- 5. Triggers and helper functions

-- 5.1 When a unit status changes, close the open history row and insert a new one.
CREATE OR REPLACE FUNCTION trg_units_status_audit()
RETURNS TRIGGER LANGUAGE plpgsql AS
$$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO unit_status_history(unit_id, unit_status_id, valid_from, note)
        VALUES (NEW.unit_id, NEW.unit_status_id, now(), 'Initial status on insert');
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' AND NEW.unit_status_id <> OLD.unit_status_id THEN
        -- Close previous open interval
        UPDATE unit_status_history
           SET valid_to = now()
         WHERE unit_id = OLD.unit_id
           AND valid_to IS NULL;
        -- Insert new status interval
        INSERT INTO unit_status_history(unit_id, unit_status_id, valid_from, note)
        VALUES (NEW.unit_id, NEW.unit_status_id, now(), 'Status changed via UPDATE on units');
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_units_status_insert
AFTER INSERT ON units
FOR EACH ROW EXECUTE FUNCTION trg_units_status_audit();

CREATE TRIGGER trg_units_status_update
AFTER UPDATE OF unit_status_id ON units
FOR EACH ROW EXECUTE FUNCTION trg_units_status_audit();

-- 6. Views for common explorations

-- 6.1 Current operational units
CREATE OR REPLACE VIEW vw_operational_units AS
SELECT
    u.unit_id,
    s.name AS site_name,
    c.name AS country,
    u.unit_name,
    rd.name AS reactor_design,
    rf.code AS family,
    u.net_electric_mw,
    u.commercial_operation_date
FROM units u
JOIN sites s               ON s.site_id = u.site_id
JOIN countries c           ON c.country_id = s.country_id
JOIN reactor_designs rd    ON rd.reactor_design_id = u.reactor_design_id
JOIN reactor_families rf   ON rf.reactor_family_id = rd.reactor_family_id
JOIN unit_status_lu us     ON us.unit_status_id = u.unit_status_id
WHERE us.code = 'OPERATIONAL';

-- 6.2 Country level summary, counts and capacity
CREATE OR REPLACE VIEW vw_country_reactor_summary AS
SELECT
    c.country_id,
    c.name AS country,
    COUNT(*) FILTER (WHERE us.code = 'OPERATIONAL')            AS units_operational,
    COUNT(*) FILTER (WHERE us.code = 'UNDER_CONSTRUCTION')      AS units_under_construction,
    COUNT(*) FILTER (WHERE us.code = 'PLANNED')                 AS units_planned,
    COUNT(*) FILTER (WHERE us.code IN ('SHUTDOWN','DECOMMISSIONED')) AS units_retired,
    SUM(u.net_electric_mw) FILTER (WHERE us.code = 'OPERATIONAL')    AS net_mw_operational
FROM countries c
LEFT JOIN sites s ON s.country_id = c.country_id
LEFT JOIN units u ON u.site_id = s.site_id
LEFT JOIN unit_status_lu us ON us.unit_status_id = u.unit_status_id
GROUP BY c.country_id, c.name;

-- 6.3 Annual capacity factor per unit
--     CF = net_generation_mwh / (hours_in_year * reference_capacity_mw) * 100
--     Uses avg_net_capacity_mw if provided, otherwise unit.net_electric_mw.
CREATE OR REPLACE VIEW vw_unit_capacity_factor AS
SELECT
    g.unit_id,
    g.calendar_year,
    u.unit_name,
    s.name AS site_name,
    COALESCE(g.avg_net_capacity_mw, u.net_electric_mw) AS reference_capacity_mw,
    g.net_generation_mwh,
    (g.net_generation_mwh
     / (COALESCE(g.avg_net_capacity_mw, u.net_electric_mw) * 24 * (CASE
            WHEN EXTRACT(YEAR FROM make_date(g.calendar_year,12,31))::INT % 4 = 0
                 AND (g.calendar_year % 100 <> 0 OR g.calendar_year % 400 = 0)
            THEN 366 ELSE 365 END))) * 100
        AS capacity_factor_pct
FROM generation_stats g
JOIN units u ON u.unit_id = g.unit_id
JOIN sites s ON s.site_id = u.site_id;

-- 7. Seed data
--    Small, illustrative dataset. Values are approximate and only for demo.
--    You should replace or extend with authoritative data later.

-- 7.1 Countries
INSERT INTO countries(name, iso2, iso3, region) VALUES
('United States', 'US', 'USA', 'North America'),
('Canada',         'CA', 'CAN', 'North America'),
('United Kingdom', 'GB', 'GBR', 'Europe'),
('Finland',        'FI', 'FIN', 'Europe'),
('Romania',        'RO', 'ROU', 'Europe');

-- 7.2 Organization types
INSERT INTO organization_types(code, description) VALUES
('operator',  'Entity that operates one or more nuclear units'),
('owner',     'Entity that owns one or more nuclear units'),
('developer', 'Entity developing new reactors'),
('regulator', 'Government regulator');

-- 7.3 Organizations
INSERT INTO organizations(name, organization_type_id, country_id, website)
SELECT 'PG&E', organization_type_id, (SELECT country_id FROM countries WHERE iso2 = 'US'), 'https://www.pge.com'
FROM organization_types WHERE code = 'operator';

INSERT INTO organizations(name, organization_type_id, country_id, website)
SELECT 'Southern Nuclear', organization_type_id, (SELECT country_id FROM countries WHERE iso2 = 'US'), 'https://www.southernnuclear.com'
FROM organization_types WHERE code = 'operator';

INSERT INTO organizations(name, organization_type_id, country_id, website)
SELECT 'EDF Energy', organization_type_id, (SELECT country_id FROM countries WHERE iso2 = 'GB'), 'https://www.edfenergy.com'
FROM organization_types WHERE code = 'operator';

INSERT INTO organizations(name, organization_type_id, country_id, website)
SELECT 'TVO', organization_type_id, (SELECT country_id FROM countries WHERE iso2 = 'FI'), 'https://www.tvo.fi'
FROM organization_types WHERE code = 'operator';

INSERT INTO organizations(name, organization_type_id, country_id, website)
SELECT 'Nuclearelectrica', organization_type_id, (SELECT country_id FROM countries WHERE iso2 = 'RO'), 'https://www.nuclearelectrica.ro'
FROM organization_types WHERE code = 'operator';

INSERT INTO organizations(name, organization_type_id, country_id, website)
SELECT 'Ontario Power Generation', organization_type_id, (SELECT country_id FROM countries WHERE iso2 = 'CA'), 'https://www.opg.com'
FROM organization_types WHERE code = 'operator';

-- 7.4 Reactor families
INSERT INTO reactor_families(code, description) VALUES
('PWR',  'Pressurized Water Reactor'),
('BWR',  'Boiling Water Reactor'),
('PHWR', 'Pressurized Heavy Water Reactor'),
('EPR',  'European Pressurized Reactor family marker'),   -- you may keep EPR under PWR family in practice
('VVER', 'Russian PWR lineage'),                           -- likewise, commonly grouped under PWR
('Other','Other or advanced type');

-- 7.5 Reactor designs, link to the most appropriate family
INSERT INTO reactor_designs(name, reactor_family_id, neutron_spectrum, primary_coolant, moderator, typical_thermal_mw, typical_electric_mw, fuel_form, typical_enrichment_pct)
VALUES
('PWR Generic', (SELECT reactor_family_id FROM reactor_families WHERE code='PWR'),
 'thermal','light water','light water', 3000, 1000, 'UO2', 3.50),
('AP1000', (SELECT reactor_family_id FROM reactor_families WHERE code='PWR'),
 'thermal','light water','light water', 3400, 1110, 'UO2', 4.50),
('EPR', (SELECT reactor_family_id FROM reactor_families WHERE code='PWR'),
 'thermal','light water','light water', 4300, 1600, 'UO2', 4.95),
('CANDU 6', (SELECT reactor_family_id FROM reactor_families WHERE code='PHWR'),
 'thermal','heavy water','heavy water', 2065, 700, 'Natural U', 0.71),
('BWR Generic', (SELECT reactor_family_id FROM reactor_families WHERE code='BWR'),
 'thermal','light water','light water', 3000, 1000, 'UO2', 3.00);

-- 7.6 Status lookup
INSERT INTO unit_status_lu(code, description, is_active) VALUES
('PLANNED',             'Planned but not under construction', FALSE),
('UNDER_CONSTRUCTION',  'First concrete or similar milestone achieved', TRUE),
('OPERATIONAL',         'In commercial operation', TRUE),
('SHUTDOWN',            'Shutdown, not generating, may be temporary or long term', FALSE),
('DECOMMISSIONED',      'Permanent shutdown, decommissioning state', FALSE);

-- 7.7 Sites
INSERT INTO sites(name, country_id, location_name, latitude_deg, longitude_deg) VALUES
('Diablo Canyon', (SELECT country_id FROM countries WHERE iso2='US'), 'California', 35.211, -120.855),
('Vogtle',        (SELECT country_id FROM countries WHERE iso2='US'), 'Georgia',    33.137,  -81.765),
('Hinkley Point', (SELECT country_id FROM countries WHERE iso2='GB'), 'Somerset',   51.209,   -3.128),
('Olkiluoto',     (SELECT country_id FROM countries WHERE iso2='FI'), 'Eurajoki',   61.236,   21.445),
('Cernavoda',     (SELECT country_id FROM countries WHERE iso2='RO'), 'Constanța',  44.343,   28.033),
('Darlington',    (SELECT country_id FROM countries WHERE iso2='CA'), 'Ontario',    43.875,   -78.728);

-- 7.8 Units, simplified attributes for demo
INSERT INTO units(
    site_id, unit_name, reactor_design_id, operator_id, owner_id,
    thermal_power_mw, gross_electric_mw, net_electric_mw,
    load_factor_design_pct, design_life_years,
    construction_start_date, first_criticality_date, grid_connection_date,
    commercial_operation_date, permanent_shutdown_date, unit_status_id
)
VALUES
-- Diablo Canyon Units 1 and 2, PWRs, operational
((SELECT site_id FROM sites WHERE name='Diablo Canyon'), 'Unit 1',
 (SELECT reactor_design_id FROM reactor_designs WHERE name='PWR Generic'),
 (SELECT organization_id FROM organizations WHERE name='PG&E'),
 NULL,
 3000, 1130, 1100, 92, 40,
 DATE '1968-01-01', NULL, NULL,
 DATE '1985-05-01', NULL,
 (SELECT unit_status_id FROM unit_status_lu WHERE code='OPERATIONAL')),

((SELECT site_id FROM sites WHERE name='Diablo Canyon'), 'Unit 2',
 (SELECT reactor_design_id FROM reactor_designs WHERE name='PWR Generic'),
 (SELECT organization_id FROM organizations WHERE name='PG&E'),
 NULL,
 3000, 1130, 1100, 92, 40,
 DATE '1970-01-01', NULL, NULL,
 DATE '1986-05-01', NULL,
 (SELECT unit_status_id FROM unit_status_lu WHERE code='OPERATIONAL')),

-- Vogtle 3, AP1000, operational
((SELECT site_id FROM sites WHERE name='Vogtle'), 'Unit 3',
 (SELECT reactor_design_id FROM reactor_designs WHERE name='AP1000'),
 (SELECT organization_id FROM organizations WHERE name='Southern Nuclear'),
 NULL,
 3400, 1150, 1110, 92, 60,
 DATE '2013-03-01', NULL, NULL,
 DATE '2023-07-31', NULL,
 (SELECT unit_status_id FROM unit_status_lu WHERE code='OPERATIONAL')),

-- Vogtle 4, AP1000, under construction or recent operation depending on data. Mark as UNDER_CONSTRUCTION for demo.
((SELECT site_id FROM sites WHERE name='Vogtle'), 'Unit 4',
 (SELECT reactor_design_id FROM reactor_designs WHERE name='AP1000'),
 (SELECT organization_id FROM organizations WHERE name='Southern Nuclear'),
 NULL,
 3400, 1150, 1110, 92, 60,
 DATE '2015-11-01', NULL, NULL,
 NULL, NULL,
 (SELECT unit_status_id FROM unit_status_lu WHERE code='UNDER_CONSTRUCTION')),

-- Hinkley Point C Unit 1 and 2, EPR design, under construction
((SELECT site_id FROM sites WHERE name='Hinkley Point'), 'Unit C1',
 (SELECT reactor_design_id FROM reactor_designs WHERE name='EPR'),
 (SELECT organization_id FROM organizations WHERE name='EDF Energy'),
 NULL,
 4300, 1630, 1600, 92, 60,
 DATE '2018-12-01', NULL, NULL,
 NULL, NULL,
 (SELECT unit_status_id FROM unit_status_lu WHERE code='UNDER_CONSTRUCTION')),

((SELECT site_id FROM sites WHERE name='Hinkley Point'), 'Unit C2',
 (SELECT reactor_design_id FROM reactor_designs WHERE name='EPR'),
 (SELECT organization_id FROM organizations WHERE name='EDF Energy'),
 NULL,
 4300, 1630, 1600, 92, 60,
 DATE '2020-09-01', NULL, NULL,
 NULL, NULL,
 (SELECT unit_status_id FROM unit_status_lu WHERE code='UNDER_CONSTRUCTION')),

-- Olkiluoto 3, EPR, operational
((SELECT site_id FROM sites WHERE name='Olkiluoto'), 'Unit 3',
 (SELECT reactor_design_id FROM reactor_designs WHERE name='EPR'),
 (SELECT organization_id FROM organizations WHERE name='TVO'),
 NULL,
 4300, 1630, 1600, 92, 60,
 DATE '2005-08-01', NULL, NULL,
 DATE '2023-04-16', NULL,
 (SELECT unit_status_id FROM unit_status_lu WHERE code='OPERATIONAL')),

-- Cernavoda 1, CANDU 6, operational
((SELECT site_id FROM sites WHERE name='Cernavoda'), 'Unit 1',
 (SELECT reactor_design_id FROM reactor_designs WHERE name='CANDU 6'),
 (SELECT organization_id FROM organizations WHERE name='Nuclearelectrica'),
 NULL,
 2065, 705, 700, 90, 40,
 DATE '1982-07-01', NULL, NULL,
 DATE '1996-12-02', NULL,
 (SELECT unit_status_id FROM unit_status_lu WHERE code='OPERATIONAL')),

-- Darlington 1, CANDU 6 style in this demo model
((SELECT site_id FROM sites WHERE name='Darlington'), 'Unit 1',
 (SELECT reactor_design_id FROM reactor_designs WHERE name='CANDU 6'),
 (SELECT organization_id FROM organizations WHERE name='Ontario Power Generation'),
 NULL,
 2065, 705, 700, 90, 40,
 DATE '1985-01-01', NULL, NULL,
 DATE '1990-12-31', NULL,
 (SELECT unit_status_id FROM unit_status_lu WHERE code='OPERATIONAL'));

-- 7.9 Generation stats, a few demo rows to enable capacity factor analytics
INSERT INTO generation_stats(unit_id, calendar_year, net_generation_mwh, avg_net_capacity_mw)
SELECT u.unit_id, 2023, 8_100_000, NULL FROM units u
WHERE (SELECT code FROM unit_status_lu WHERE unit_status_id = u.unit_status_id) = 'OPERATIONAL'
AND u.unit_name IN ('Unit 1','Unit 2','Unit 3');

INSERT INTO generation_stats(unit_id, calendar_year, net_generation_mwh, avg_net_capacity_mw)
SELECT u.unit_id, 2024, 8_300_000, NULL FROM units u
WHERE (SELECT code FROM unit_status_lu WHERE unit_status_id = u.unit_status_id) = 'OPERATIONAL'
AND u.unit_name IN ('Unit 1','Unit 2','Unit 3');

COMMIT;

-- 8. Example analytic queries
--    You can run these as needed.

-- 8.1 Average net capacity by reactor family
/* Returns one row per family, with the average net capacity across units */
SELECT
    rf.code AS reactor_family,
    ROUND(AVG(u.net_electric_mw)::numeric, 2) AS avg_net_mw,
    COUNT(*) AS unit_count
FROM units u
JOIN reactor_designs rd  ON rd.reactor_design_id = u.reactor_design_id
JOIN reactor_families rf ON rf.reactor_family_id = rd.reactor_family_id
GROUP BY rf.code
ORDER BY avg_net_mw DESC;

-- 8.2 Reactors commissioned after a given year
/* Replace :year_threshold with your value */
WITH params AS (SELECT 2000::INT AS year_threshold)
SELECT
    s.name AS site,
    u.unit_name,
    c.name AS country,
    rd.name AS design,
    u.commercial_operation_date
FROM units u
JOIN sites s            ON s.site_id = u.site_id
JOIN countries c        ON c.country_id = s.country_id
JOIN reactor_designs rd ON rd.reactor_design_id = u.reactor_design_id
JOIN params p           ON TRUE
WHERE u.commercial_operation_date >= make_date(p.year_threshold, 1, 1)
ORDER BY u.commercial_operation_date;

-- 8.3 Countries with the most operational reactors
SELECT
    country,
    units_operational,
    net_mw_operational
FROM vw_country_reactor_summary
ORDER BY units_operational DESC, net_mw_operational DESC;

-- 8.4 Capacity factor rankings for a given year
WITH params AS (SELECT 2023::INT AS y)
SELECT
    v.site_name,
    u.unit_name,
    c.name AS country,
    ROUND(v.capacity_factor_pct::numeric, 2) AS capacity_factor_pct
FROM vw_unit_capacity_factor v
JOIN units u     ON u.unit_id = v.unit_id
JOIN sites s     ON s.site_id = u.site_id
JOIN countries c ON c.country_id = s.country_id
JOIN params p    ON v.calendar_year = p.y
ORDER BY capacity_factor_pct DESC NULLS LAST;

-- 8.5 Units under construction for more than N years
WITH params AS (SELECT 5::INT AS years_threshold)
SELECT
    s.name AS site,
    u.unit_name,
    c.name AS country,
    u.construction_start_date,
    EXTRACT(YEAR FROM age(now(), u.construction_start_date)) AS years_since_start
FROM units u
JOIN sites s     ON s.site_id = u.site_id
JOIN countries c ON c.country_id = s.country_id
JOIN unit_status_lu us ON us.unit_status_id = u.unit_status_id
JOIN params p    ON TRUE
WHERE us.code = 'UNDER_CONSTRUCTION'
  AND u.construction_start_date IS NOT NULL
  AND age(now(), u.construction_start_date) > make_interval(years => p.years_threshold)
ORDER BY years_since_start DESC;

-- 8.6 Data completeness checks
-- Find units missing basic capacity attributes
SELECT site_id, unit_name
FROM units
WHERE net_electric_mw IS NULL OR thermal_power_mw IS NULL;

-- 8.7 Status history for a specific unit
/* Replace :unit_name as needed */
SELECT
    u.unit_name,
    us.code AS status,
    h.valid_from,
    h.valid_to,
    h.note
FROM units u
JOIN unit_status_history h ON h.unit_id = u.unit_id
JOIN unit_status_lu us     ON us.unit_status_id = h.unit_status_id
WHERE u.unit_name = 'Unit 3'
ORDER BY h.valid_from;

-- 9. Helper query templates you can adapt

-- 9.1 Search by free text across sites, designs, and organizations
--     For full text search, consider adding pg_trgm extension and trigram indexes.
SELECT
    s.name AS site,
    u.unit_name,
    rd.name AS design,
    o.name AS operator
FROM units u
JOIN sites s            ON s.site_id = u.site_id
JOIN reactor_designs rd ON rd.reactor_design_id = u.reactor_design_id
JOIN organizations o    ON o.organization_id = u.operator_id
WHERE
    s.name ILIKE '%' || $1 || '%'
    OR u.unit_name ILIKE '%' || $1 || '%'
    OR rd.name ILIKE '%' || $1 || '%'
    OR o.name ILIKE '%' || $1 || '%';

-- 9.2 Year by year generation trend for a unit
SELECT
    g.calendar_year,
    g.net_generation_mwh,
    ROUND(
        (g.net_generation_mwh
        / (COALESCE(g.avg_net_capacity_mw, u.net_electric_mw) * 24
           * (CASE WHEN (g.calendar_year % 400 = 0) OR (g.calendar_year % 4 = 0 AND g.calendar_year % 100 <> 0) THEN 366 ELSE 365 END)
          ) * 100
        )::numeric, 2
    ) AS capacity_factor_pct
FROM generation_stats g
JOIN units u ON u.unit_id = g.unit_id
WHERE u.unit_name = $1
ORDER BY g.calendar_year;

-- End of script
