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
