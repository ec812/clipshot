# Follow-up task: git commit + branch convention

The user has run `git init` and `git remote add origin https://github.com/ec812/clipshot.git` (already done — do not re-init, do not add remotes). Some files are already staged.

1. Review what's staged/untracked (`git status`), make sure `.gitignore` sensibly excludes build products (DerivedData, build/, .DS_Store, xcuserdata) — do NOT ignore source, project files, plans, or docs.
2. Commit everything as the initial commit on main. Message: "Clipshot v1: clipboard manager + Bitly shortener, rich previews (colors, OG images, app-icon accents)". A single commit is fine. Do NOT push (user handles the remote push).
3. From now on the convention is: NEW features go on a git branch (`feature/<short-name>`), commit there, and report the branch name; main only receives completed features. Note this convention at the top of README.md under a "Development" heading. Do not create a branch for work already finished — just commit to main.
4. Reply with: commit hash, `git log --oneline` output, and confirmation of the .gitignore contents.

No build/test gate needed for this task (nothing code-changed), but do not modify any source files.
