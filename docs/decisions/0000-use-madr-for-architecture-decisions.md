---
status: proposed
date: 2026-01-19
---

# Use MADR for Architecture Decision Records

## Context and Problem Statement

We need a way to document architecture decisions made in this project so that future contributors can understand the reasoning behind key choices. How should we record these decisions?

## Decision Drivers

* Need for lightweight, easy-to-maintain documentation
* Desire to keep decision records close to the code
* Want a standardized format that is easy to read and write
* Want AI agents to be able to easily gather insights about the project's past decisions

## Considered Options

* MADR 4.0.0 (Markdown Any Decision Records)
* Plain markdown files without a template
* Confluence
* No formal documentation

## Decision Outcome

Chosen option: "MADR 4.0.0", because it provides a lightweight, standardized template that lives alongside the code and is easy to maintain in version control.

### Consequences

* Good, because decisions are documented in a consistent format
* Good, because ADRs are version-controlled alongside the code
* Good, because the markdown format is readable without special tooling
* Neutral, because contributors need to learn the MADR format

### Confirmation

The presence of ADR files in `docs/decisions/` following the MADR template confirms compliance with this decision.

## Pros and Cons of the Options

### MADR 4.0.0

[MADR 4.0.0](https://adr.github.io/madr/) is a lean template for recording architecture decisions in markdown.

* Good, because it is lightweight and easy to use
* Good, because it is widely adopted and well-documented
* Good, because it supports version control workflows
* Good, because it keeps documentation close to the code
* Good, because it provides a lot of context to AI agents
* Bad, because non-developers would require access and knowledge of the existence of the repository

### Plain markdown files without a template

* Good, because it requires no learning curve
* Bad, because inconsistent formats make decisions harder to find and compare
* Bad, because important sections might be omitted
* Good, because it provides context to AI agents
* Neutral, because it might not provide recognizable documentation patterns to AI agents

### Confluence

* Good, because it may be more discoverable for some teams
* Bad, because it separates documentation from code
* Bad, because it locks the documentation to Atlassian's products
* Bad, because it is not accessible by AI agents without MCP servers and more complex setups

### No formal documentation

* Good, because it requires no effort
* Bad, because knowledge is lost when team members leave
* Bad, because decisions are questioned repeatedly
* Bad, because AI agents are more likely to propose solutions that go against the team's past decisions

## More Information

For more information about MADR, see the [official MADR repository](https://github.com/adr/madr).
