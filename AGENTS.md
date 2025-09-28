# StorageEx Monorepo

This is an Elixir monorepo containing multiple packages for file storage abstraction, similar to Rails ActiveStorage.

## Project Structure

This is a monorepo with multiple Elixir packages located in the `packages/` directory:
- `storage_ex` - Core storage abstraction library
- `storage_ex_s3` - Amazon S3 storage adapter
- `storage_ex_ecto` - Ecto integration for attachments

Each package is a separate Mix project with its own dependencies and configuration.

## Running Commands

**DO NOT run mix commands from the root directory.** Always run commands from within a specific package directory.

### Using Make (Recommended)

The Makefile provides convenient commands for working with all packages or specific ones:

**All packages:**
- `make test` - Run tests in all packages
- `make compile` - Compile all packages
- `make deps` - Fetch dependencies for all packages
- `make lint` - Run Credo linter on all packages
- `make lint-strict` - Run Credo with strict mode on all packages
- `make format` - Run mix format on all packages
- `make dialyzer` - Run Dialyzer type checker on all packages
- `make check` - Run full CI check (format, lint, dialyzer, test)
- `make clean` - Clean all packages
- `make reset` - Clean, fetch deps, and compile all packages

**Single package:**
- `make storage_ex.test` - Run tests for storage_ex package
- `make storage_ex.compile` - Compile storage_ex package
- `make storage_ex.check` - Run full check for storage_ex package
- Replace `storage_ex` with `storage_ex_s3` or `storage_ex_ecto` for other packages

### Manual Commands

If you need to run mix commands manually, always change to the package directory first:

```bash
cd packages/storage_ex
mix test
mix test path/to/test.exs:line_number
```

## Testing

- To run tests for a specific package: `make storage_ex.test`
- To run all tests: `make test`
- To run a specific test file: `make storage_ex.test packages/storage_ex/test/storage_ex_test.exs`
- To run a specific test file at a line: `make storage_ex.test packages/storage_ex/test/storage_ex_test.exs:10`

## Code Quality

- Always run `make format` before committing
- Run `make lint-strict` to check for code quality issues
- Run `make dialyzer` to check types
- Run `make check` to run all quality checks

## Development Workflow

1. Make changes to code in the appropriate package
2. Run tests: `make <package>.test`
3. Format code: `make format`
4. Check quality: `make check`
5. Commit changes
