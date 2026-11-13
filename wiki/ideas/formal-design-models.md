# Checking designs with formal models

Writing a system's design as a small formal model and letting a tool explore every possible interleaving of it, to find design bugs before or apart from the code ([research 08](../../research/08-correctness-first-databases.md)).

## What it is

*TLA+* is a language for describing a system's design as states and steps. A *model checker* explores every interleaving of a small instance of the model and reports the shortest path to a violated property ([research 08](../../research/08-correctness-first-databases.md)). AWS now favours *P*, which models designs as communicating state machines familiar to its engineers ([AWS, CACM 2025](https://cacm.acm.org/practice/systems-correctness-practices-at-amazon-web-services/)).

## The problem it solves

Design bugs that hide many steps deep. On [DynamoDB](../systems/dynamodb.md)'s replication, 939 lines of TLA+ "found three bugs requiring traces of up to 35 steps". The worst could lose data, and had "passed unnoticed through extensive design reviews, code reviews, and testing" ([Amazon, 2015](https://cacm.acm.org/research/how-amazon-web-services-uses-formal-methods/)).

## What it costs

The specification is a second program that must be kept matched to the code ([research 08](../../research/08-correctness-first-databases.md)).

- [MongoDB](../systems/mongodb.md) tried to check that real server traces matched its TLA+ spec: "This whole experiment failed. Our traces never matched our specification." Generating tests from the spec did work for a smaller algorithm ([VLDB 2020](https://vldb.org/pvldb/vol13/p1346-davis.pdf); [MongoDB blog](https://www.mongodb.com/company/blog/engineering/conformance-checking-at-mongodb-testing-our-code-matches-our-tla-specs)).
- AWS's PObserve checks production logs against the P specification, one way of keeping the two matched ([AWS, CACM 2025](https://cacm.acm.org/practice/systems-correctness-practices-at-amazon-web-services/)).

## Systems that use it

- [DynamoDB](../systems/dynamodb.md): TLA+ on replication (2015); P today, along with S3, EBS, MemoryDB and Aurora ([AWS, CACM 2025](https://cacm.acm.org/practice/systems-correctness-practices-at-amazon-web-services/)).
- [MongoDB](../systems/mongodb.md): TLA+ specs, a failed trace-checking experiment, and working test generation for a smaller algorithm.
- [CockroachDB](../systems/cockroachdb.md) publishes TLA+ specifications ([parallel commits](https://www.cockroachlabs.com/blog/parallel-commits/)).
- Azure Cosmos DB publishes TLA+ specifications ([azure-cosmos-tla](https://github.com/Azure/azure-cosmos-tla)).

## Sources

- [research 08: Correctness-first databases](../../research/08-correctness-first-databases.md)
- How AWS uses formal methods: https://cacm.acm.org/research/how-amazon-web-services-uses-formal-methods/
- Systems correctness practices at AWS: https://cacm.acm.org/practice/systems-correctness-practices-at-amazon-web-services/
- MongoDB, VLDB 2020: https://vldb.org/pvldb/vol13/p1346-davis.pdf
- MongoDB conformance checking: https://www.mongodb.com/company/blog/engineering/conformance-checking-at-mongodb-testing-our-code-matches-our-tla-specs
- CockroachDB parallel commits: https://www.cockroachlabs.com/blog/parallel-commits/
- Azure Cosmos DB TLA+: https://github.com/Azure/azure-cosmos-tla
