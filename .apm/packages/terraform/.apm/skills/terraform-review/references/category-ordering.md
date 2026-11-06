# Ordering (ORD)

**ORD-01 (MUST): Alphabetize argument keys inside resource/module/data/local blocks**

Check: Are argument keys inside each resource, module, data, and local block sorted alphabetically (A-Z)?
Why: Inconsistent ordering adds diff noise and makes change detection harder
Fix: Sort argument keys alphabetically within each block
Note: Also detected by terraform validation with `--check-order`. When validation output is supplied, take this ItemID's status from that result and cite the tool instead of re-reporting it.
