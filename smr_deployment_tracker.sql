BEGIN;

DROP SCHEMA IF EXISTS smr CASCADE;
CREATE SCHEMA smr;
SET search_path = smr, public;

-- 1. Lookups

CREATE TABLE countries (
  country_id BIGSERIAL PRIMARY KEY,
  name       TEXT NOT NULL UNIQUE,
  iso2       CHAR(2) NOT NULL UNIQUE CHECK (iso2 ~ '^[A-Z]{2}$'),
  region     TEXT NULL
);

CREATE TABLE org_types (
  org_type_id BIGSERIAL PRIMARY KEY,
  code        TEXT NOT NULL UNIQUE,     -- developer, utility, vendor, regulator
  description TEXT NOT NULL
);

CREATE TABLE organizations (
  organization_id BIGSERIAL PRIMARY KEY,
  name            TEXT NOT NULL UNIQUE,
  org_type_id     BIGINT NOT NULL REFERENCES org_types(org_type_id),
  country_id      BIGINT REFERENCES countries(country_id),
  website         TEXT NULL
);

-- Project status categories
CREATE TABLE status_lu (
  status_id  BIGSERIAL PRIMARY KEY,
  code       TEXT NOT NULL UNIQUE,      -- CONCEPT, FEED, LICENSING, SITE_PREP, UNDER_CONSTRUCTION, OPERATIONAL, CANCELLED, PAUSED
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL UNIQUE
);

-- 2. SMR designs

CREATE TABLE reactor_technologies (
  tech_id     BIGSERIAL PRIMARY KEY,
  code        TEXT NOT NULL UNIQUE,     -- PWR, BWR, PHWR, MSR, HTGR, SFR, LFR, MMR
  description TEXT NOT NULL
);

CREATE TABLE smr_designs (
  design_id          BIGSERIAL PRIMARY KEY,
  name               TEXT NOT NULL UNIQUE,        -- e.g. NuScale VOYGR-6, BWRX-300, XE-100, Natrium
  developer_id       BIGINT REFE_
