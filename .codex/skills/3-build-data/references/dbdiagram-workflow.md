# DBML + dbdiagram Workflow

## Recommended Flow

1. Maintain schema in `docs/5. DB 명세서/schema.dbml` (single source of truth).
2. Open dbdiagram.io and paste DBML for visual validation.
3. Export SQL from dbdiagram when local CLI is unavailable.
4. Save export result to `docs/5. DB 명세서/schema.sql`.
5. Update `ERD.md` with link/image and change summary.

## Optional Local CLI

If `dbml2sql` is installed:

```bash
dbml2sql "docs/5. DB 명세서/schema.dbml" -o "docs/5. DB 명세서/schema.sql"
```

## Guardrails

- Do not edit SQL first. Always edit DBML first.
- Keep table/column names in snake_case.
- Add PK/FK/index with explicit reason.
