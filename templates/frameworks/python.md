# Python rules

- All dependencies live in the project venv. Run through `.venv/bin/python` or the project entrypoint — bare `python` will `ModuleNotFoundError`.
- Entry scripts and CLIs orchestrate only; logic lives in `lib/<domain>/` (or the project's package layout). To add a command, add the thin command layer and put the behavior in the domain module.
- Config-first: behavior changes go to config files first, code second.
- No new dependency without justification.
- Respect the established folder structure; ask before restructuring.
