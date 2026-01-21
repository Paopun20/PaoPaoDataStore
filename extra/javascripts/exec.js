document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll(".run-js-btn").forEach(btn => {
        btn.addEventListener("click", (e) => {
            e.preventDefault();
            const code = btn.dataset.js;
            const buttonIdentifier = btn.textContent.trim() || btn.id || btn.className || 'Unknown Button'; // Get a name for the button

            try {
                new Function(code)();
            } catch (err) {
                // --- Enhanced Error Reporting for Dynamic Code ---
                let errorMessage = `Error running code from button: ${buttonIdentifier}\n`;
                errorMessage += `Code executed:\n${code}\n`; // Include the dynamic code
                errorMessage += `--- Error Details ---\n`;
                errorMessage += `${err.name}: ${err.message}\n`;

                // Basic location info if available (often points to new Function call site, not inside the dynamic code)
                if (err.fileName) {
                    errorMessage += `File: ${err.fileName}\n`;
                }
                if (err.lineNumber) {
                    errorMessage += `Line (in main script): ${err.lineNumber}\n`;
                }
                if (err.columnNumber) {
                    errorMessage += `Column: ${err.columnNumber}\n`;
                }

                // More detailed stack trace (if available) - can sometimes hint at the dynamic code's context
                if (err.stack) {
                    errorMessage += `\nStack Trace:\n${err.stack}`;
                }

                console.error("Error running button JS:", err, "\nCode was:", code);
                alert(errorMessage);
                // --- End Enhanced Error Reporting ---
            }
        });
    });
});