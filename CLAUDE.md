@AGENTS.md

## Task tracking: always use the task-board MCP

All work on this project is tracked on the **Politicool** board (board id `16`) in the `task-board` MCP server. Always use it, and don't keep a separate todo list in chat or in files.

Lists (in order): **Backlog** (69) → **ToDo** (70) → **Doing** (71) → **Testing** (72) → **Done** (73)

Labels: Bug, Feature, Urgent, Design, Research

### Workflow

1. **Before starting work**, call `get_board` with `board_id: 16` (or `search_cards`) to find the matching card, then `get_card` to read its spec, checklist and comments.
2. **No card for the work?** Create one with `create_card` in ToDo, using a fitting label and priority, before you write code.
3. **When you start**, use `move_card` to put the card in **Doing**. Use `create_branch` if the work needs a branch.
4. **While working**, tick checklist items with `set_checklist_item`. Use `add_comment` to log decisions, blockers and notable findings on the card.
5. **When the code is done** and `mix precommit` passes, move the card to **Testing** and comment with a short summary of what changed.
6. **Move a card to Done** only after the user confirms it, or once it's verified end to end.
7. **Bugs or follow-ups found along the way** become new cards (label `Bug`, or Backlog for later). Don't fix them silently and don't drop them.

Respect card assignees. Cards assigned to Damian Swiney are his (the UI/LiveView work), so don't pick them up unless asked.
