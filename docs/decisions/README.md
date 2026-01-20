# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for this project.

## What is an ADR?

An Architecture Decision Record (ADR) is a document that captures an important architectural decision made along with its context and consequences.

## Format

We use [MADR](https://adr.github.io/madr/) (Markdown Any Decision Records) format for our ADRs.

## Creating a New ADR

1. Copy `adr-template.md` to a new file named `NNNN-title-of-decision.md` where `NNNN` is the next sequential number
2. Fill in the template sections
3. Submit the ADR for review via pull request
4. Add a row to the index table in this `README.md`

## ADR Statuses

- **proposed** - The decision is under discussion
- **accepted** - The decision has been accepted and should be followed
- **rejected** - The decision was considered but not accepted
- **deprecated** - The decision is no longer relevant
- **superseded by ADR-NNNN** - The decision has been replaced by another ADR

## Index

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [0000](0000-use-madr-for-architecture-decisions.md) | Use MADR for Architecture Decision Records | accepted | 2026-01-19 |
