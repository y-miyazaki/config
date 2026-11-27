# Migration & Refactor (MIG)

**MIG-01 (SHOULD): Use moved blocks to avoid resource recreation on refactors**

Check: Do refactors use moved blocks where appropriate?
Why: Resource recreation during refactoring and downtime cause service interruption, data loss, and user impact
Fix: Use `moved` block for state migration, avoid destructive changes

**MIG-02 (SHOULD): Replace deprecated or end-of-support features**

Check: Does the code use a resource, argument, module input, runtime, engine, or platform version that its official documentation marks as deprecated or end-of-support?
Why: Deprecated features and end-of-support versions stop receiving fixes, then fail or get blocked on a published date, causing operation failures and security risks
Fix: Replace with the documented successor before the stated date; cite the documentation page under `Problem` and the date in `Impact`
Note: Deprecated means the vendor documentation says so (deprecation notice, end-of-support date, or removal). A value that is older but still supported is not a MIG-02 finding; judge it under MIG-04. `tflint` reports deprecated resources and arguments covered by the enabled provider ruleset. When validation output is supplied, take the status of those findings from tflint and cite it; still evaluate deprecations the ruleset does not cover (for example provider upgrade notes, deprecated module inputs, or runtime and engine versions it does not list).

**MIG-03 (SHOULD): State-address changes are called out with their migration path**

Check: When a change alters resource addresses (`count` to `for_each`, key changes, renames, moving into a module), is the migration path stated, and is it correct for the keys involved? `moved` blocks cannot target dynamically computed keys
Why: Address changes plan as destroy and create. For security-sensitive, permission-bearing or stateful resources this can detach permissions, break connections or lose data, even when the final configuration is right
Fix: Use `moved` blocks where the new address is static, otherwise document the `terraform state mv` steps; call out resources whose destroy and create has runtime impact and ask for a `terraform plan` review before apply

**MIG-04 (SHOULD): Switch superseded versions and policies to the current recommended one**

Check: Where an argument selects a policy, runtime, engine, or platform version (for example a TLS or security policy, a function runtime, a database engine version, a cluster version), does the value match what the official documentation currently recommends, or is a newer recommended option available? The value is still supported and not deprecated; deprecated values belong to MIG-02
Why: A supported but superseded selection lags on security hardening and fixes and becomes deprecated later; switching while it is still supported avoids a forced change under a deadline
Fix: Switch to the documented recommended value and state the compatibility impact (client or protocol support, extensions, downtime of an in-place version upgrade); for stateful resources, ask for a `terraform plan` review before apply
Note: Method: Do not keep or rely on a list of "old" values; they go stale. Read the argument's documentation at the provider version pinned in the code (the version in the lock file when the constraint is a range; the latest documentation, stated as such, when none is pinned), then the service's official documentation for the recommended or latest option, and cite the page and the date it was read under `Problem`. When the two sources disagree, the pinned provider documentation decides which values the argument accepts. When the argument is unset, read the documented default and judge that. When the pages cannot be read, defer the check or report the claim under `Unverified`. Report each value once: a deprecated or end-of-support value is MIG-02 only. `Impact` states "no end date published" for MIG-04, so the reader can tell it from a MIG-02 deadline. When validation output is supplied, do not re-report values `tflint` or `trivy` already flag; evaluate the arguments they do not cover
