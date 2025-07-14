Suggested Improvements

Break out a library of common functions

Functions like find_manifest and render_template are self‑contained and could live in a lib/workon.sh file. The CLI script would then source this library. This keeps bin/workon shorter and allows reuse in future subcommands (e.g., a stop command).

Pros: Clear separation between utility functions and CLI argument parsing. Easier unit testing of individual helpers.

Cons: Slightly more files to manage and source correctly.

Subcommand structure for start/stop

The README envisions both start and stop flows. Implementing workon start and workon stop as separate scripts or functions would make each responsibility explicit. bin/workon could dispatch based on the first argument (start defaulting if omitted).

Pros: Each script remains concise and focused on one task; easier to maintain as features grow.

Cons: Users must learn the subcommand style; risk of duplicating option parsing logic unless a shared helper is used.

Stronger modular separation for YAML parsing and launching

Consider a dedicated manifest.sh module responsible for parsing and validating the YAML (using yq and jq). Another launcher.sh could wrap the AwesomeWM interaction. This would isolate quoting and error handling for awesome-client.

Pros: Clear API boundaries; easier to unit test YAML logic without launching apps.

Cons: May feel heavy-weight if the overall project stays relatively small.

Consistent quoting and escaping

The current script manually escapes quotes for awesome-client. Encapsulating this in a helper (launch_resource) would avoid repeated sed commands and centralize the quoting logic.

Extend tests as functionality grows

Tests currently focus on parsing functions and failure cases. Adding tests for the spawn logic (perhaps with mocks for awesome-client) will ensure future refactoring doesn’t break launching.

Error handling improvements

Introduce traps to clean up partial launches if the script exits unexpectedly.

Provide more user-friendly messages for dependency failures (possibly calling bin/check-deps when the main script starts).

Splitting into multiple scripts or modules would align with the architecture shown in the README. A modular approach—entrypoint CLI → parsing library → launcher library—mirrors the conceptual flow and makes each part individually testable. It facilitates incremental addition of features like layouts, session tracking, or alternative window managers.

Recommendation

Begin refactoring by extracting reusable helpers (find_manifest, render_template, quoting utilities) into lib/workon.sh. Keep bin/workon as a thin CLI that parses options and calls start or stop functions sourced from the library. As new features land, evaluate whether separate scripts (bin/workon-start, bin/workon-stop) would further clarify responsibilities.

This modular approach balances maintainability with current simplicity and prepares the project for future growth without imposing too much structure up front.
