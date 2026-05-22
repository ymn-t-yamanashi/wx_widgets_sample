#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <mix_project_dir>" >&2
  exit 1
fi

PROJECT_DIR="$1"
MIX_EXS="$PROJECT_DIR/mix.exs"
APP_FILE="$PROJECT_DIR/lib/$(basename "$PROJECT_DIR").ex"
TEST_FILE="$PROJECT_DIR/test/$(basename "$PROJECT_DIR")_test.exs"
QA_DIR="$PROJECT_DIR/lib/mix/tasks"
QA_FILE="$QA_DIR/qa.ex"

if [ ! -f "$MIX_EXS" ]; then
  echo "Error: mix.exs not found in $PROJECT_DIR" >&2
  exit 1
fi

mkdir -p "$QA_DIR"

cat > "$QA_FILE" <<'EOT'
defmodule Mix.Tasks.Qa do
  use Mix.Task

  @shortdoc "Run quality checks: format, compile, test, and optional credo"

  @moduledoc """
  Runs the standard QA pipeline in order:

  1. `mix format`
  2. `mix compile --warnings-as-errors`
  3. `mix test`
  4. `mix credo` (only when Credo task is available)
  """

  @impl Mix.Task
  def run(_args) do
    run_or_fail("format", [])
    run_or_fail("compile", ["--warnings-as-errors"])
    run_or_fail("test", [])
    run_optional_credo()
  end

  defp run_or_fail(task, args) do
    Mix.shell().info("==> mix #{task} #{Enum.join(args, " ")}")
    Mix.Task.reenable(task)
    Mix.Task.run(task, args)
  rescue
    error ->
      Mix.raise("`mix #{task}` failed: #{Exception.message(error)}")
  end

  defp run_optional_credo do
    if Mix.Task.get("credo") do
      run_or_fail("credo", [])
    else
      Mix.shell().info("==> mix credo (skipped: Credo is not installed)")
    end
  end
end
EOT

if ! grep -q "def cli do" "$MIX_EXS"; then
  awk '
    /^\s*def application do/ && done == 0 {
      print "  def cli do"
      print "    [preferred_envs: [qa: :test]]"
      print "  end"
      print ""
      done = 1
    }
    { print }
  ' "$MIX_EXS" > "$MIX_EXS.tmp"
  mv "$MIX_EXS.tmp" "$MIX_EXS"
fi

if [ -f "$TEST_FILE" ] && [ -f "$APP_FILE" ]; then
  APP_MODULE=$(basename "$PROJECT_DIR" | sed -E 's/(^|_)([a-z])/\U\2/g')
  cat > "$TEST_FILE" <<EOT
defmodule ${APP_MODULE}Test do
  use ExUnit.Case
  doctest ${APP_MODULE}

  test "start function is available" do
    assert is_function(&${APP_MODULE}.start/0)
  end
end
EOT
fi

echo "Harness installed in $PROJECT_DIR"
