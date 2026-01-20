# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for this project.

## What is an ADR?

An Architecture Decision Record (ADR) is a document that captures an important architectural decision made along with its context and consequences.

## Format

We use [MADR](https://adr.github.io/madr/) 4.0.0 (Markdown Any Decision Records) format for our ADRs.

## Creating a New ADR

For new ADRs, please use one of the following templates as a starting point:

* [adr-template.md](adr-template.md) has all sections, with explanations about them.
* [adr-template-minimal.md](adr-template-minimal.md) only contains mandatory sections, with explanations about them.
* [adr-template-bare.md](adr-template-bare.md) has all sections, which are empty (no explanations).
* [adr-template-bare-minimal.md](adr-template-bare-minimal.md) has the mandatory sections, without explanations.

1. Copy a template to a new file named `NNNN-title-of-decision.md` where `NNNN` is the next sequential number
2. Fill in the template sections
3. Submit the ADR for review via pull request
4. Add a row to the ADR index table below in this `README.md`, following the format of the existing entry

The MADR documentation is available at <https://adr.github.io/madr/> while general information about ADRs is available at <https://adr.github.io/>.

## ADR Statuses

* **proposed** - The decision is under discussion
* **accepted** - The decision has been accepted and should be followed
* **rejected** - The decision was considered but not accepted
* **deprecated** - The decision is no longer relevant
* **superseded by ADR-NNNN** - The decision has been replaced by another ADR

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [0000](0000-use-madr-for-architecture-decisions.md) | Use MADR for Architecture Decision Records | proposed | 2026-01-19 |
