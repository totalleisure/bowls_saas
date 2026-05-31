# Bowls SaaS — Production Readiness

## Purpose

This document defines the strategy and engineering standards required to move Bowls SaaS from active development into a stable production-grade system.

The primary focus is:

* data integrity
* transactional consistency
* operational reliability
* recoverability
* concurrency safety
* auditability

The goal is to ensure that all business-critical operations remain correct under real-world conditions including:

* asynchronous UI behaviour
* re-entrant client calls
* partial failures
* concurrent edits
* network interruption
* duplicate requests

---

# Core Principles

## Data Integrity First

The database is the primary source of truth.

UI behaviour must never compromise:

* referential integritymemb
* business rules
* transactional correctness
* consistency between related records

---

## Multi-Step Operations Must Be Atomic

Operations affecting multiple tables or records should execute within a single transaction boundary.

Examples include:

* Create Fixture
* Publish Team
* Repeat Fixtures
* Assign Rinks
* Move/Swap Rinks
* Notification Processing

Preferred implementation:

* server-side RPC
* single transaction
* commit or rollback

---

## Client Code Must Be Treated as Re-Entrant

Flutter asynchronous processing and UI rebuilds may result in:

* repeated calls
* duplicate submissions
* stale state
* overlapping requests

Server-side logic must assume this can occur.

---

## Idempotency Is Essential

Repeated execution of the same operation must not corrupt data.

Protection mechanisms include:

* unique constraints
* state validation
* transactional safeguards
* duplicate prevention logic

---

# Critical Operations Register

## Fixture Operations

* [x] Create Fixture
* [ ] Repeat Fixture
* [ ] Edit Fixture
* [ ] Delete Fixture

---

## Team Selection Operations

* [ ] Create Team Selection
* [ ] Publish Team
* [ ] Edit Team
* [ ] Remove Team Members

---

## Rink Operations

* [ ] Assign Physical Rinks
* [ ] Move Rinks
* [ ] Swap Rinks
* [ ] Validate Capacity

---

## RSVP & Open Session Operations

* [ ] RSVP Processing
* [ ] Open Session Booking
* [ ] Acceptance Processing

---

## Notifications & Messaging

* [ ] Notification Queue
* [ ] Email Distribution
* [ ] Team Sheet Distribution

---

# Initial System Invariants

## Fixture Invariants

* fixture_rinks count must equal fixtures.rinks_required
* no duplicate rink labels within a fixture
* fixture start time must precede end time

---

## Team Selection Invariants

* one active team selection per fixture/team
* member cannot occupy multiple positions in same fixture
* inactive team members must not remain selectable

---

## Rink Allocation Invariants

* no overlapping physical rink allocation
* fixture_rink_assignments must reference valid fixture_rinks rows

---

# Planned Protection Strategies

## Database

* foreign keys
* unique constraints
* transactional RPCs
* validation triggers
* RLS enforcement

---

## Client

* _isSaving protection
* button disabling during save
* mounted checks
* duplicate submission prevention
* retry handling

---

# Planned Audit & Repair Processes

* stale team_selection_members cleanup
* orphaned row detection
* duplicate notification detection
* fixture/rink reconciliation
* failed queue retry handling

---

# Release Readiness Checklist

## Data Integrity

* [ ] Critical operations reviewed
* [ ] Transaction boundaries defined
* [ ] Invariants documented
* [ ] Unique constraints verified
* [ ] RLS policies reviewed

---

## Operational Stability

* [ ] Error handling standardised
* [ ] Network interruption tested
* [ ] Concurrent editing tested
* [ ] Retry behaviour reviewed

---

## Deployment

* [ ] Backup strategy defined
* [ ] Restore procedure tested
* [ ] Release process documented
* [ ] Monitoring/logging reviewed

---

# Long-Term Goal

Bowls SaaS should evolve into a robust transactional platform where:

* operations are deterministic
* failures are recoverable
* concurrent access is safe
* data integrity is preserved
* operational support is manageable

