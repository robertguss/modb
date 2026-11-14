# What earlier work binds a write or a read to a purpose and an approval?

Type: research
Status: closed

## Question

The survey missed earlier systems that come close to the accountable write. For each, find what it does, what pays for it, what became of it and how far it is from a write that states who made it, under which grant, for which task and why, checked against rules a person approved:

- Hippocratic databases (Agrawal, Kiernan, Srikant and Xu, VLDB 2002) and the purpose-based access control work that followed;
- Hyperledger Fabric: proposals, endorsement policies and what is checked at commit;
- Datomic: facts recorded on the transaction itself, and checks that run at transaction time. The wiki calls these "optional, unchecked"; an outside review says they can be required and checked at commit. Settle which, and whether the engine can force the check on every writer;
- purpose-based access control (2005 and after);
- record-keeping rules in regulated industries that require who, under what authority and why on every change, such as FDA 21 CFR Part 11 and the systems built to meet it;
- anything else found on the way that binds a purpose or an approval to a transaction.

Say plainly whether the accountable write is new, a new combination, or an existing idea under another name.

**2026-11-14, closed unanswered.** Robert stopped the map before this ticket was answered. See [the map](../map.md).
