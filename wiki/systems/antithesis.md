# Antithesis

Antithesis sells deterministic simulation testing as a service. It runs ordinary software, which was not written to be deterministic, inside a hypervisor that controls every source of randomness, so the code needs no rewrite ([Antithesis DST](https://antithesis.com/docs/resources/deterministic_simulation_testing/); [research 08](../../research/08-correctness-first-databases.md)).

## What it is for

Getting the benefits of [deterministic simulation testing](../ideas/deterministic-simulation-testing.md) without rebuilding a system the way FoundationDB and TigerBeetle were built. Retrofitting determinism into existing code is hard, which is why Antithesis works at the hypervisor level ([research 08](../../research/08-correctness-first-databases.md)).

## Core idea

A *deterministic hypervisor* is a virtual machine whose every source of randomness is controlled ([deterministic hypervisor](https://antithesis.com/blog/deterministic_hypervisor/)). The whole system under test, "including dependencies like Kafka and Postgres", runs "on a single CPU core" ([product](https://antithesis.com/product/)). Each event can branch into alternate timelines, and one run often finds many timelines where a bug triggered ([how Antithesis works](https://antithesis.com/docs/introduction/how_antithesis_works/)).

## Strengths and what pays for each

- **Simulation without rewriting code.** Paid for by: a paid outside service, and one core per simulated system ([research 08](../../research/08-correctness-first-databases.md)).
- **Simulation of the user's own system.** It is the closest thing research 08 found to deterministic testing of the user's workload, but it is sold as a service outside the database ([research 08](../../research/08-correctness-first-databases.md)). See [simulating the user's own workload](../ideas/simulating-the-users-own-workload.md).

## Weaknesses

- The properties to check are still yours to write ([research 08](../../research/08-correctness-first-databases.md)).
- Research 08 could not confirm its current pricing or customer list.

## Sources

- [research 08: Correctness-first databases](../../research/08-correctness-first-databases.md)
- Deterministic simulation testing: https://antithesis.com/docs/resources/deterministic_simulation_testing/
- Deterministic hypervisor: https://antithesis.com/blog/deterministic_hypervisor/
- Product: https://antithesis.com/product/
- How Antithesis works: https://antithesis.com/docs/introduction/how_antithesis_works/
