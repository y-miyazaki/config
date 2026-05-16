## Error Handling Review Guidance

### Purpose

Use this reference when reviewing failure behavior in workflows.

### Focus Areas

- `continue-on-error` usage and whether failure masking is justified
- Required `if:` guards for cleanup or rollback steps
- Retry behavior and timeout handling for flaky integrations
- Failure notifications and escalation paths
