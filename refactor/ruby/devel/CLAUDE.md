See AGENTS.md and the following:
Please follow these guidelines when contributing software code, which will be predominantly in Bash, Ksh93 and Ruby with development on the up-to-date version of macOS:
* Keep comments minimal; prefer self-documenting code through strings, variable names, etc. over more comments.
* Follow best practices and idiomatic patterns.
* Document public APIs and complex logic.
* Follow software principles such as DRY and YAGNI.
* While Zsh or Bash might be used for testing, administrative scripts will often be in the default Ksh supplied by macOS.
* Likewise, utilities such as awk are the ones supplied by macOS, which often means that GNU extensions are not available.
* Be a partner to architect and engineer a superior product instead of being an aggrandizing, sycophantic "yes man". Provide encouragement and validation where appropriate, but do push back and challenge me where appropriate.
* Provide suggested file names.
* Use long options to commands where supported (i.e., `grep --extended-regexp` instead of `grep -E`).
* You will likely be asked to provide full implementations, so build the conversation accordingly.
* Make explicit when your response is not supported by reliable evidence; let it be known that you are making a guess.
* Shell scripts should be sure to have proper error handling, and in most instances have a main function whose job is to call other functions.
* Ruby code should be in classes namespaced to a module exposing only a minimal public API method which calls private methods.
* Don't use the first person in code comments ("we ask").

Commit message format:
* First line MUST be 50 characters or less.
* Reference issues with `Closes #12345` in commit body if applicable.

PR Hygiene:
* Before any PR, check for existing PRs for the same issue and check if the proposed changes were refused.
* No verbose commentary—keep PR descriptions short.
* Provide only essential context in PR descriptions.
* Do not include lengthy explanations in PR descriptions.
* Must not add verbose AI analysis in PR body.
* Must not include large logs or verbose output in PR body.
* No drive-by formatting or unrelated stanza churn.
* Must not include unrelated refactors or cleanups.
* If AI assisted with the PR, briefly describe how AI was used and what manual verification was performed.
* For CI failures, push incremental commits (do not squash after opening PR).
