# Task List Management

Guidelines for managing task lists in markdown files to track progress, document, and give standard instructions for a tactical manager agent to coordinate tasks execution between multiple sub-agents, maximizing context optimization, conciseness and quality.

## Task Implementation

- **One **task** at a time:** Do **NOT** start the next task until you ask the user for permission and they say “yes” or "y"
- **Completion protocol:**
  1. When you finish a **sub‑task**, immediately mark it as completed by changing `[ ]` to `[x]`.
  2. If the current **sub-task** is a test for the previous **sub-task** and test fails. Uncheck the previous **sub-task** and consider the fixing part of it. Reiterate the test as many times as needed.
  3. If **all** subtasks underneath a parent task are now `[x]`, also mark the **parent task** as completed.
- Stop after each **task** and wait for the user’s go‑ahead.

## Task List Maintenance

1. **Update the task list as you work:**
   - Mark tasks and subtasks as completed (`[x]`) per the protocol above.
   - Add new tasks as they emerge. Consider the new **task** on the plan and give it for the best **sub-agent** to complete it when adequated. Always add test **sub-task** pair to the new task created.

2. **Maintain the “Relevant Files” section:**
   - List every file created or modified.
   - Give each file a one‑line description of its purpose.

## AI General Instructions

When working with task lists, the AI must:

1. Regularly update the task list file after finishing any significant work.
2. Follow the completion protocol:
   - Mark each finished **sub‑task** `[x]`.
   - Mark the **parent task** `[x]` once **all** its subtasks are `[x]`.
3. Add newly discovered tasks.
4. Keep “Relevant Files” accurate and up to date.
5. Before starting work, check which sub‑task is next.
6. After implementing a **task**, update the file and then pause for user approval.
