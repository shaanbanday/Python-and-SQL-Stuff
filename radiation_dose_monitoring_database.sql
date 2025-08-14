BEGIN;

DROP SCHEMA IF EXISTS raddose CASCADE;
CREATE SCHEMA raddose;
SET search_path = raddose, public;

-- 1. Lookups and reference data

CREATE TABLE countries (
  country_id BIGSERIAL PRIMARY KEY,
  name       TEXT NOT NULL UNIQUE,
  iso2       CHAR(2) NOT NULL UNIQUE CHECK (iso2 ~ '^[A-Z]{2}$')
);

CREATE TABLE departments (
  department_id BIGSERIAL PRIMARY KEY,
  name          TEXT NOT NULL UNIQUE
);

CREATE TABLE job_roles (
  job_role_id BIGSERIAL PRIMARY KEY,
  code        TEXT NOT NULL UNIQUE,      -- e.g. RPT, HP Tech, Mech Tech
  title       TEXT NOT NULL
);

-- Dose metric types so the system is extensible
CREATE TABLE dose_types (
  dose_type_id BIGSERIAL PRIMARY KEY,
  code         TEXT NOT NULL UNIQUE,     -- DE, Hp(10), Hp(0.07), Neutron, Tritium
  description  TEXT NOT NULL
);

-- Regulatory and program limits by role and calendar year
-- Example: annual deep dose equivalent limit 50 mSv for radiation workers
CREATE TABLE dose_limits (
  dose_limit_id  BIGSERIAL PRIMARY KEY,
  job_role_id    BIGINT NOT NULL REFERENCES job_roles(job_role_id),
  dose_type_id   BIGINT NOT NULL REFERENCES dose_types(dose_type_id),
  calendar_year  INTEGER NOT NULL CHECK (calendar_year BETWEEN 1990 AND 2100),
  annual_limit_msv NUMERIC(8,3) NOT NULL CHECK (annual_limit_msv >= 0),
  quarterly_limit_msv NUMERIC(8,3) NULL CHECK (quarterly_limit_msv IS NULL OR quarterly_limit_msv >= 0),
  CONSTRAINT uq_limits UNIQUE (job_role_id, dose_type_id, calendar_year)
);

-- 2. People and authorization

CREATE TABLE people (
  person_id     BIGSERIAL PRIMARY KEY,
  employee_no   TEXT NOT NULL UNIQUE,
  first_name    TEXT NOT NULL,
  last_name     TEXT NOT NULL,
  country_id    BIGINT REFERENCES countries(country_id),
  email         TEXT NULL,
  active        BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE person_roles (
  person_role_id BIGSERIAL PRIMARY KEY,
  person_id      BIGINT NOT NULL REFERENCES people(person_id) ON DELETE CASCADE,
  job_role_id    BIGINT NOT NULL REFERENCES job_roles(job_role_id),
  department_id  BIGINT NOT NULL REFERENCES departments(department_id),
  valid_from     DATE NOT NULL DEFAULT CURRENT_DATE,
  valid_to       DATE NULL,
  CONSTRAINT uq_person_role_active UNIQUE (person_id, job_role_id, department_id, valid_from)
);

-- 3. Work locations and tasks

CREATE TABLE work_locations (
  location_id BIGSERIAL PRIMARY KEY,
  code        TEXT NOT NULL UNIQUE,      -- e.g. RXB-235, Hotlab-01
  name        TEXT NOT NULL,
  description TEXT NULL
);

CREATE TABLE work_tasks (
  task_id         BIGSERIAL PRIMARY KEY,
  task_code       TEXT NOT NULL UNIQUE,
  description     TEXT NOT NULL,
  location_id     BIGINT REFERENCES work_locations(location_id),
  alara_category  TEXT NULL CHECK (alara_category IN ('I','II','III')) -- simple ALARA screening tiers
);

-- 4. Dosimetry

-- A dosimeter assignment record, e.g. TLD badge or electronic dosimeter
CREATE TABLE dosimeters (
  dosimeter_id   BIGSERIAL PRIMARY KEY,
  serial_no      TEXT NOT NULL UNIQUE,
  type           TEXT NOT NULL CHECK (type IN ('TLD','OSL','Electronic','Neutron','Extremity')),
  assigned_to    BIGINT REFERENCES people(person_id),
  assigned_from  DATE NOT NULL DEFAULT CURRENT_DATE,
  assigned_to_dt DATE NULL
);

-- Individual dose entries, typically coming from vendor reports or EPD logs
CREATE TABLE dose_records (
  dose_record_id   BIGSERIAL PRIMARY KEY,
  person_id        BIGINT NOT NULL REFERENCES people(person_id) ON DELETE CASCADE,
  dose_type_id     BIGINT NOT NULL REFERENCES dose_types(dose_type_id),
  period_start     DATE NOT NULL,
  period_end       DATE NOT NULL,
  perio
