cd ~/binf6610-pipeline
cat > TROUBLESHOOTING.md <<'EOF'
# Troubleshooting log — Assignment 1

## 1. Setup commands failed in PowerShell
**Symptom:** The tool-check loop failed with `Missing opening '(' after keyword 'for'` and `The token '||' is not a valid statement separator`.
**Evidence:** The prompt was `PS C:\WINDOWS\system32>`, so the commands were going to Windows PowerShell, which parses a different language from bash.
**Cause:** The pipeline and its commands are bash. Also, bwa, samtools, fastp and GATK from bioconda do not run natively on Windows at all.
**Fix:** Ran everything inside Ubuntu under WSL2 (`wsl -l -v` confirmed VERSION 2). The same loop then printed a path for every tool.

## 2. The conda environment "disappeared"
**Symptom:** After Ubuntu closed and reopened, `conda activate binf6610` gave `EnvironmentNameNotFound`.
**Evidence:** The prompt now read `molly_k@DESKTOP-MBJ0599` instead of `molly@DESKTOP-MBJ0599`. `whoami` returned `molly_k`, and `conda env list` showed only `base` and `molly`, both under `/home/molly_k/miniforge3`.
**Cause:** I was logged in as a different Linux user, which has its own conda install, so the environment created as `molly` did not exist there.
**Fix:** Recreated the environment as `molly_k` and added `unzip` and `git` to it to avoid needing sudo. The tool check then found all eight tools. I now always work as `molly_k`.

## 3. `git remote add` silently never ran
**Symptom:** `git remote add origin https://github.com/<your-github-username>/binf6610-pipeline.git` printed `-bash: your-github-username: No such file or directory`.
**Evidence:** The error names the text inside the angle brackets as if it were a file. Bash reads `<` as input redirection, so it tried to open a file called `your-github-username` and never ran git.
**Cause:** I pasted a placeholder literally instead of replacing it.
**Fix:** Reran the command with my real username (`Mollinak10`). The later push reached the right repository.

## 4. `git push` rejected
**Symptom:** `remote: Invalid username or token. Password authentication is not supported for Git operations.`
**Evidence:** The message says GitHub no longer accepts account passwords over HTTPS. Retrying with a personal access token failed the same way. Nothing appears on screen in the password prompt, and Ctrl+V does not paste in the Ubuntu terminal, so I could not confirm the token actually went in.
**Cause:** GitHub requires a token, and pasting into the hidden prompt was not working.
**Fix:** Installed the GitHub CLI (`conda install -c conda-forge gh`), ran `gh auth login` with browser login, then `gh auth setup-git`. `git push` worked without a password prompt, and the repository page showed my commit.
EOF
cat TROUBLESHOOTING.md

