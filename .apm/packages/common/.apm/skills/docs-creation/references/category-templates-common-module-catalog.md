## module-catalog

Templates are guidance and review rubrics, not rigid prose generators.
Adapt structure and depth to the repository and context.
Remove sections that cannot be populated with concrete information.

**Depth guidance:** List every module/package in the repository with its purpose, consumers, and key inputs/outputs. For monorepos with 10+ modules, group by domain but still enumerate all of them. Include version constraints, compatibility notes, and inter-module dependencies.

```markdown
# Module Catalog

<!-- Answer: What modules/components does this repository contain? Source: read top-level package structure, go.mod, or module directories. -->

Focus on:
- module responsibilities and ownership
- intended usage and consumers
- composition patterns
- operational notes

Avoid:
- modules that are purely internal implementation details with no external consumers

## <Category or Domain>

### `<module/path>`

<!-- Answer: What does this module do? Who uses it? Source: read the module's package doc or main file. -->

#### Purpose

#### Responsibilities

#### Consumers

#### Dependencies

## Decision Prompts

Consider:
- Which modules are reusable vs environment-specific?
- Which modules are operationally sensitive?
- Which modules expose unstable interfaces?
```
