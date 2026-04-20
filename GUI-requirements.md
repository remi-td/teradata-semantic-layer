# Graphical user interface requirements

We need a GUI to expose the semantic layer to business users. The GUI should allow users to explore the semantic layer (visualising it as a graph or tree, ability to expand/collapse nodes, search functionality) and generate queries. The GUI should be web-based and run as a small python server process. 
The GUI should be easy to use and should be visually appealing, and aligned to Teradata branding guidelines (use the `teradata-brand` skill for this purpose).
The GUI should be easy to navigate and should be easy to understand.

## User Stories

1. As a business user, I want to navigate the semantic layer and understand the available datasets, metrics and how they relate. I want to be able to search by term, visualise the details, and from there explore the related concepts.

2. As a data architect, I want to ensure the coherence and completeness of my semantic layer by visualising the full graph of datasets and relationships, and identify missing or incomplete definitions.

3. As a data engineer/analyst I want to generate SQL queries from the semantic layer, validate them using EXPLAIN, and run them against the database to validate the results.

4. As a data engineer/architect I want to be able to import semantic layer definitions (or elements of a semantic layer such as new dimensions/metrics) from a yaml/json payload (that I can write in a large text box in the interface). This text shoud be parsed and validated against the semantic layer schema, and the user should be notified of any errors (eg.valid syntax, dependencies satisfied, etc...).

## Technical guidelines
First of all deeply research the state of the art in terms of semantic layer visualisation tools to understand what great looks like.

The proces should be a lightweight Python web server that can run on a laptop. Use teradatasql package. Expect the database logon string in a DATABASE_URI environment variable, the way this is done for the Teradata MCP Server.

Expose all key functionalities as REST API endpoints.

For user story (4), as much as possible, perform the logic in database (eg. parse the JSON using the native Teradata functions is a stored procedure).

## Packaging

This will mark the end of the first sprint: we have a minimum viable product that can be used to drive value.
To finish, re-organize this project into a proper python package with proper documentation and tests, clear and extensive documentation, a README that carries the gist of the idea (philosophy, key design principles, and quickstart). It should be easy to install: deploy all the structures on a target database and (optionally) run the GUI server.
It should be quick and simple to test and evaluate: loading the sample dataset we used.
CI/CD should be robust: we leverage the testing framework, clearly document how to run the tests to identify regressions and add new ones.
It should be easy for Claude Code to update going forward: the code should be clean, modular, well-documented, and follow best practices for Python development. It should be easy to understand and modify for someone who is not familiar with the project, CLAUDE.md is up to date and sufficient.
