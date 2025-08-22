-- Insurance Management System - Initial Schema Migration (MySQL)
-- Migration: 001_init.sql
-- Purpose: Create core normalized schema, constraints, indexes, and seed reference data.

-- Notes:
-- - Engine: InnoDB for FK support, utf8mb4 charset for wide unicode.
-- - Timestamp fields use DEFAULT CURRENT_TIMESTAMP and ON UPDATE where applicable.
-- - Audit logging provided via audit_log table; application should insert upon changes.
-- - Monetary values stored as DECIMAL(12,2); adjust as necessary.
-- - All names and enums are stored in reference tables to avoid tight coupling.

-- Ensure the database is selected (adjust if needed by deployment tooling)
-- USE `myapp`;

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- Disable FK checks during migration
SET FOREIGN_KEY_CHECKS = 0;

-- Drop existing tables if re-running migration (idempotent for development)
DROP TABLE IF EXISTS audit_log;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS claim_status_history;
DROP TABLE IF EXISTS claims;
DROP TABLE IF EXISTS customer_policies;
DROP TABLE IF EXISTS policies;
DROP TABLE IF EXISTS policy_types;
DROP TABLE IF EXISTS user_roles;
DROP TABLE IF EXISTS roles;
DROP TABLE IF EXISTS users;

-- USERS
CREATE TABLE users (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  email            VARCHAR(255) NOT NULL,
  password_hash    VARCHAR(255) NOT NULL,
  first_name       VARCHAR(100) NOT NULL,
  last_name        VARCHAR(100) NOT NULL,
  phone_number     VARCHAR(32) NULL,
  is_active        TINYINT(1) NOT NULL DEFAULT 1,
  created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_users_email (email),
  KEY idx_users_last_first (last_name, first_name),
  KEY idx_users_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ROLES
CREATE TABLE roles (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name        VARCHAR(64) NOT NULL, -- e.g., ADMIN, AGENT, CUSTOMER
  description VARCHAR(255) NULL,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_roles_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- USER_ROLES (many-to-many)
CREATE TABLE user_roles (
  user_id     BIGINT UNSIGNED NOT NULL,
  role_id     BIGINT UNSIGNED NOT NULL,
  assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  assigned_by BIGINT UNSIGNED NULL,
  PRIMARY KEY (user_id, role_id),
  KEY idx_user_roles_role (role_id),
  KEY idx_user_roles_assigned_by (assigned_by),
  CONSTRAINT fk_user_roles_user
    FOREIGN KEY (user_id) REFERENCES users(id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_user_roles_role
    FOREIGN KEY (role_id) REFERENCES roles(id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_user_roles_assigned_by
    FOREIGN KEY (assigned_by) REFERENCES users(id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- POLICY_TYPES (reference)
CREATE TABLE policy_types (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code             VARCHAR(64) NOT NULL, -- e.g., HEALTH, AUTO, HOME, LIFE
  name             VARCHAR(128) NOT NULL,
  description      TEXT NULL,
  coverage_details TEXT NULL,
  created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_policy_types_code (code),
  KEY idx_policy_types_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- POLICIES (catalog/plan definitions)
CREATE TABLE policies (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  policy_type_id     BIGINT UNSIGNED NOT NULL,
  policy_code        VARCHAR(64) NOT NULL, -- unique per catalog item
  name               VARCHAR(255) NOT NULL,
  description        TEXT NULL,
  premium_amount     DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  coverage_amount    DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  deductible_amount  DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  term_months        INT NOT NULL DEFAULT 12,
  is_active          TINYINT(1) NOT NULL DEFAULT 1,
  created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_policies_policy_code (policy_code),
  KEY idx_policies_type_active (policy_type_id, is_active),
  CONSTRAINT fk_policies_policy_type
    FOREIGN KEY (policy_type_id) REFERENCES policy_types(id)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- CUSTOMER_POLICIES (enrollments/purchases)
CREATE TABLE customer_policies (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  customer_id          BIGINT UNSIGNED NOT NULL, -- references users
  policy_id            BIGINT UNSIGNED NOT NULL, -- references policies
  agent_id             BIGINT UNSIGNED NULL,     -- optional assigned agent (user with AGENT role)
  start_date           DATE NOT NULL,
  end_date             DATE NOT NULL,
  premium_amount       DECIMAL(12,2) NOT NULL,   -- locked at purchase time
  coverage_amount      DECIMAL(12,2) NOT NULL,   -- locked at purchase time
  policy_number        VARCHAR(64) NOT NULL,     -- customer-visible identifier
  status               VARCHAR(32) NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, LAPSED, CANCELLED, EXPIRED
  created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_customer_policies_policy_number (policy_number),
  KEY idx_customer_policies_customer (customer_id),
  KEY idx_customer_policies_agent (agent_id),
  KEY idx_customer_policies_status (status),
  KEY idx_customer_policies_policy (policy_id),
  CONSTRAINT fk_customer_policies_customer
    FOREIGN KEY (customer_id) REFERENCES users(id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_customer_policies_policy
    FOREIGN KEY (policy_id) REFERENCES policies(id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_customer_policies_agent
    FOREIGN KEY (agent_id) REFERENCES users(id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- CLAIMS
-- Statuses are tracked via claim_status_history; latest status is denormalized in claims.status for quick access.
CREATE TABLE claims (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  customer_policy_id   BIGINT UNSIGNED NOT NULL,
  claim_number         VARCHAR(64) NOT NULL,
  incident_date        DATE NOT NULL,
  filed_date           DATE NOT NULL,
  status               VARCHAR(32) NOT NULL DEFAULT 'SUBMITTED', -- denormalized latest status for fast queries
  description          TEXT NULL,
  claimed_amount       DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  approved_amount      DECIMAL(12,2) NULL,
  assigned_agent_id    BIGINT UNSIGNED NULL, -- user acting on claim (e.g., AGENT/ADJUSTER)
  created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uk_claims_claim_number (claim_number),
  KEY idx_claims_customer_policy (customer_policy_id),
  KEY idx_claims_status (status),
  KEY idx_claims_assigned_agent (assigned_agent_id),
  CONSTRAINT fk_claims_customer_policy
    FOREIGN KEY (customer_policy_id) REFERENCES customer_policies(id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_claims_assigned_agent
    FOREIGN KEY (assigned_agent_id) REFERENCES users(id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- CLAIM STATUS HISTORY (reference of statuses over time)
CREATE TABLE claim_status_history (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  claim_id       BIGINT UNSIGNED NOT NULL,
  status         VARCHAR(32) NOT NULL, -- SUBMITTED, IN_REVIEW, APPROVED, REJECTED, PAID, CLOSED, etc.
  changed_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  changed_by     BIGINT UNSIGNED NULL, -- user who changed
  reason         VARCHAR(512) NULL,
  PRIMARY KEY (id),
  KEY idx_claim_status_history_claim (claim_id),
  KEY idx_claim_status_history_status (status),
  KEY idx_claim_status_history_changed_by (changed_by),
  CONSTRAINT fk_claim_status_history_claim
    FOREIGN KEY (claim_id) REFERENCES claims(id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_claim_status_history_changed_by
    FOREIGN KEY (changed_by) REFERENCES users(id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- PAYMENTS (for premiums or claim payouts)
CREATE TABLE payments (
  id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  customer_policy_id  BIGINT UNSIGNED NULL, -- for premium payments
  claim_id            BIGINT UNSIGNED NULL, -- for claim payouts
  amount              DECIMAL(12,2) NOT NULL,
  currency            CHAR(3) NOT NULL DEFAULT 'USD',
  payment_date        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  method              VARCHAR(32) NOT NULL, -- CARD, BANK_TRANSFER, CASH, CHECK, etc.
  status              VARCHAR(32) NOT NULL DEFAULT 'COMPLETED', -- PENDING, COMPLETED, FAILED, REFUNDED
  reference_number    VARCHAR(128) NULL, -- gateway reference or check #
  created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_payments_customer_policy (customer_policy_id),
  KEY idx_payments_claim (claim_id),
  KEY idx_payments_status (status),
  KEY idx_payments_reference (reference_number),
  CONSTRAINT fk_payments_customer_policy
    FOREIGN KEY (customer_policy_id) REFERENCES customer_policies(id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_payments_claim
    FOREIGN KEY (claim_id) REFERENCES claims(id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_payments_link CHECK (
    (customer_policy_id IS NOT NULL) XOR (claim_id IS NOT NULL)
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- AUDIT LOG (generic append-only auditing)
CREATE TABLE audit_log (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  entity_type   VARCHAR(64) NOT NULL,    -- e.g., USER, POLICY, CLAIM, PAYMENT
  entity_id     BIGINT UNSIGNED NOT NULL,
  action        VARCHAR(64) NOT NULL,    -- CREATED, UPDATED, DELETED, STATUS_CHANGED, etc.
  changed_by    BIGINT UNSIGNED NULL,    -- user id
  changed_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  details       JSON NULL,               -- JSON payload with before/after or arbitrary details
  PRIMARY KEY (id),
  KEY idx_audit_entity (entity_type, entity_id),
  KEY idx_audit_action (action),
  KEY idx_audit_changed_by (changed_by),
  CONSTRAINT fk_audit_changed_by
    FOREIGN KEY (changed_by) REFERENCES users(id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Re-enable FK checks
SET FOREIGN_KEY_CHECKS = 1;

-- Seed base reference data
START TRANSACTION;

-- Roles
INSERT INTO roles (name, description) VALUES
  ('ADMIN', 'System administrator with full permissions'),
  ('AGENT', 'Insurance agent who manages policies and claims'),
  ('CUSTOMER', 'End user who purchases policies and files claims')
ON DUPLICATE KEY UPDATE description = VALUES(description);

-- Typical claim statuses (stored as initial history references and for denormalized claims.status values)
-- Using a small helper table for status seeds would be another approach; here we just enumerate canonical values.
-- Canonical statuses: SUBMITTED, IN_REVIEW, APPROVED, REJECTED, PAID, CLOSED
-- Note: Application should enforce status transitions.

-- Policy types
INSERT INTO policy_types (code, name, description, coverage_details) VALUES
  ('HEALTH', 'Health Insurance', 'Covers medical expenses', 'Hospitalization, outpatient, medications'),
  ('AUTO', 'Auto Insurance', 'Covers vehicle-related damages and liability', 'Collision, comprehensive, liability'),
  ('HOME', 'Home Insurance', 'Covers property and liability for homeowners', 'Dwelling, personal property, liability'),
  ('LIFE', 'Life Insurance', 'Provides a death benefit to beneficiaries', 'Term or whole life coverage')
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  description = VALUES(description),
  coverage_details = VALUES(coverage_details);

COMMIT;

-- Convenience views (optional, non-critical)
-- Latest claim status as a view using the denormalized claims.status.
-- CREATE OR REPLACE VIEW v_claims_summary AS
-- SELECT c.id as claim_id, c.claim_number, c.customer_policy_id, c.status as latest_status,
--        c.claimed_amount, c.approved_amount, c.assigned_agent_id, c.created_at
-- FROM claims c;

-- Indexing review:
--  - users.email unique: login/auth
--  - policies.policy_code unique: catalog code
--  - customer_policies.policy_number unique: external reference
--  - FKs indexed by default definitions above via explicit KEY lines
--  - audit_log entity_type+entity_id composite for fast lookup
--  - payments reference_number indexed for reconciliation
