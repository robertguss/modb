# Encryption at rest and confidential computing

Computation runs in a hardware enclave, a *TEE* (trusted execution environment), whose memory the machine's operator cannot read. The enclave proves which code it runs by *attestation*. This is encryption *in use*; encryption *at rest* covers stored disks and backups.

## What it is

Model inference, or any other work, runs inside a TEE ([20](../../research/20-keeping-sensitive-data-from-agents.md)). Cohere sells this on NVIDIA H100 GPUs (vendor claim, https://cohere.com/blog/introducing-confidential-computing-on-cohere-model-vault). Anthropic has published a design it is "working on" (https://www.anthropic.com/research/confidential-inference-trusted-vms); when it reaches customers is not confirmed ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## The problem it solves

- **In use:** it hides data from the model provider's operators ([20](../../research/20-keeping-sensitive-data-from-agents.md)), or from curious operators of the machine ([21](../../research/21-security-of-a-database-agents-use.md)).
- **At rest:** it stops theft of disks and backups, not theft of a login, since the database decrypts for whoever logs in ([21](../../research/21-security-of-a-database-agents-use.md)).

## What it costs

- **A hardware trust chain** ([20](../../research/20-keeping-sensitive-data-from-agents.md)), and key management for encryption at rest ([21](../../research/21-security-of-a-database-agents-use.md)).
- **Physical attacks break it.** TEE.fail (October 2025) used cheap off-the-shelf equipment on DDR5 memory to extract attestation keys, then used them against NVIDIA GPU confidential computing (https://tee.fail/). It needs physical access, which is exactly the operator a TEE is meant to exclude ([20](../../research/20-keeping-sensitive-data-from-agents.md)). Vendors exclude physical attacks from their threat model, so this marks the edge of the promise ([21](../../research/21-security-of-a-database-agents-use.md)).
- **It hides data from the provider, never from the model** ([20](../../research/20-keeping-sensitive-data-from-agents.md)).

## Systems that use it

Cohere Model Vault (vendor claim, https://cohere.com/blog/introducing-confidential-computing-on-cohere-model-vault).

## Disagreements

- **What TEE.fail broke.** [20](../../research/20-keeping-sensitive-data-from-agents.md) says it extracted attestation keys from Intel TDX and AMD SEV-SNP, then used them against NVIDIA GPU confidential computing. [21](../../research/21-security-of-a-database-agents-use.md) says it extracted attestation keys from Intel SGX and TDX and broke AMD SEV-SNP, and does not mention NVIDIA. Both cite https://tee.fail/ and agree it needs physical access to DDR5 memory.

## Sources

- [research/20-keeping-sensitive-data-from-agents.md](../../research/20-keeping-sensitive-data-from-agents.md)
- [research/21-security-of-a-database-agents-use.md](../../research/21-security-of-a-database-agents-use.md)
- https://cohere.com/blog/introducing-confidential-computing-on-cohere-model-vault
- https://www.anthropic.com/research/confidential-inference-trusted-vms
- https://tee.fail/
