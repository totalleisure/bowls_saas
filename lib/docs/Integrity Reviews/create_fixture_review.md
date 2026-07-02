# Create Fixture Integrity Review

**Date:** 30-May-2026

## Purpose

Review the Create Fixture process from a production readiness and data integrity perspective.

---

## Current Implementation

The Create Fixture process is primarily client-driven.

The Flutter application performs a sequence of database operations to create:

* Fixture
* Team Selection (where applicable)
* Fixture Rinks
* Fixture Rink Assignments
* Team Selection Members
* Related setup records

These operations are executed sequentially from the client.

---

## Findings

### Finding 1 – Multi-Step Client Transaction

**Risk Level:** High

The Create Fixture process performs multiple related database updates.

If one operation succeeds and a later operation fails, the database may be left in a partially-created state.

#### Example

* Fixture created
* Fixture rinks created
* Team selection created
* Assignment creation fails

Result:

* Fixture exists
* Supporting records may be incomplete

#### Recommendation

Long-term objective:

Move fixture creation into a single server-side RPC that performs all related updates within a single database transaction.

Expected behaviour:

* All changes commit successfully; or
* All changes rollback.

---

### Finding 2 – Repeat Fixture Processing

**Risk Level:** Medium

Repeat Fixture processing creates fixtures individually.

#### Assessment

This approach is acceptable.

A failure when creating one fixture should not necessarily rollback previously-created fixtures in the batch.

#### Recommendation

Each fixture creation should eventually be transactional, but the entire batch should not be treated as a single transaction.

---

### Finding 3 – Duplicate Submit Protection

**Risk Level:** Low

The screen already contains protection against duplicate save requests using a loading guard.

#### Assessment

Current implementation is acceptable.

#### Future Improvement

Separate loading and saving state variables if required.

Example:

* _isLoading
* _isSaving

---

### Finding 4 – Rink Availability Race Condition

**Risk Level:** High

Availability is checked before saving.

A second administrator could potentially book the same capacity between the availability check and final save.

#### Recommendation

The final capacity validation should ultimately occur within the same database transaction that creates the fixture.

---

## Summary

### Strengths

* Good screen structure
* Existing duplicate-save protection
* Repeat fixture processing already isolated

### Long-Term Improvements

* Transactional RPC-based fixture creation
* Server-side capacity validation
* Reduced dependency on client-side sequencing

---

## Status

Review completed.

Implementation work deferred until Production Readiness phase.

---

## Implementation Status

Completed: May 2026

Implemented:
- create_fixture_with_setup RPC
- Transactional fixture creation
- Server-side rink availability validation
- Single and repeat fixture creation unified
- Enum-safe inserts
- Client-side duplicate save protection retained

Outcome:
Fixture creation is now transaction-safe and no longer relies upon multiple independent client-side database updates.
