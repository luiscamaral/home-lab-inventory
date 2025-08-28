# Role: Generate a Task List from a PRD

## Goal

To guide an AI assistant in creating a detailed, step-by-step task list in Markdown format based on an existing Product Requirements Document (PRD). The task list should guide a junior manager through coordinating junior developers or specialists on the tactical plan, it's verification and measurable KPIs and success metrics.

## Process

1.  **Receive PRD Reference:** The user points the AI to a specific PRD file. File would be read from `<project_root>/mcp/work/<project_requirement_name>/prd.md`, where `<project_requirement_name>` is the name of the project requirements.
2.  **Analyze PRD:** The AI reads and analyzes the plans details or requirements.
3.  **Phase 1: Generate Parent Tasks:** Based on the PRD analysis, create the file and generate the main, high-level tasks required to implement each feature. Use your judgement on how many high-level tasks to use. It's likely to be between 5 or 8. Present these tasks to the user in the specified format (without sub-tasks yet). Inform the user: "I have generated the high-level tasks based on the PRD. Ready to generate the sub-tasks? Respond with 'Go' to proceed."
4.  **Wait for Confirmation:** Pause and wait for the user to respond with "Go".
5.  **Phase 2: Generate Sub-Tasks:** Once the user confirms, break down each parent task into smaller, actionable sub-tasks necessary to complete the parent task. Ensure sub-tasks logically follow from the parent task and cover the implementation details from the PRD.
6.  **Identify Relevant Files:** Based on the tasks and PRD, identify potential files that will need to be created or modified. List these under the `Relevant Files` section, including corresponding test files if applicable.
7.  **Generate Final Output:** Combine the parent tasks, sub-tasks, relevant files, and notes into the final Markdown structure.
8.  **Save Task List:** Save the generated document in the `<project_root>/mcp/work/<project_requirement_name>/tasks.md` file with the filename.

## Output Format

The generated task list _must_ be based on this structure:

```markdown
## Relevant Files

- `path/to/potential/file1.py` - Brief description of why this file is relevant (e.g., Contains the main component for this feature)
- `path/to/file1.test.py` - Unit tests for `file1.py`
- `path/to/another/file.tsx` - Brief description (e.g., API route handler for data submission)
- `path/to/another/file.test.tsx` - Unit tests for `another/file.tsx`
- `lib/utils/helpers.sh` - Brief description (e.g., Utility functions needed for calculations)
- `lib/utils/helpers.test.sh` - Unit tests for `helpers.sh`
- 'docs/development.md' - Documentation need to be updated
- 'docs/README.md' - Project read me need to be updated

### Notes

- Unit tests should typically be placed in a specific path according to the project styling or documented standards.
- Use project standards when running unit tests, testing hooks or local validations.
- If necessary, suggest a new project standard and document it on the appropriated place. Add a reference for the file on CLAUDE.md for AI future references.

## Tasks

- [ ] 1.0 Parent Task Title
  - [ ] 1.1 [Sub-task description 1.1]
  - [ ] 1.2 [Sub-task description 1.2]
- [ ] 2.0 Parent Task Title
  - [ ] 2.1 [Sub-task description 2.1]
- [ ] 3.0 Parent Task Title (may not require sub-tasks if purely structural or configuration)
```

## Interaction Model

The process explicitly requires a pause after generating parent tasks to get user confirmation ("Go") before proceeding to generate the detailed sub-tasks. This ensures the high-level plan aligns with user expectations before diving into details.

## Target Audience

Assume the primary reader of the detailed tactical plan task list is a **junior developer** who will implement the feature. But prepare it to be coordinated with purposeful separation of concerns, by multiple specialized agents.
