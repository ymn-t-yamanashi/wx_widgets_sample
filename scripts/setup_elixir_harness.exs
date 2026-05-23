#!/usr/bin/env elixir

args = System.argv()

if length(args) != 1 do
  IO.puts(:stderr, "Usage: #{Path.basename(__ENV__.file)} <mix_project_dir>")
  System.halt(1)
end

project_dir = hd(args)
mix_exs = Path.join(project_dir, "mix.exs")
basename = Path.basename(project_dir)
app_file = Path.join([project_dir, "lib", "#{basename}.ex"])
test_file = Path.join([project_dir, "test", "#{basename}_test.exs"])
qa_dir = Path.join([project_dir, "lib", "mix", "tasks"])
qa_file = Path.join(qa_dir, "qa.ex")

unless File.exists?(mix_exs) do
  IO.puts(:stderr, "Error: mix.exs not found in #{project_dir}")
  System.halt(1)
end

File.mkdir_p!(qa_dir)

qa_source = ~S'''
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
'''

if File.exists?(qa_file) do
  IO.puts(:stderr, "Error: #{qa_file} が既に存在するため上書きしません。")
  System.halt(1)
else
  File.write!(qa_file, qa_source)
end

mix_content = File.read!(mix_exs)
unless String.contains?(mix_content, "qa: :test") do
  insert = "  def cli do\n    [preferred_envs: [qa: :test]]\n  end\n\n"
  updated =
    if String.contains?(mix_content, "def cli do") do
      IO.puts(:stderr, "Error: 既存の def cli do があるため自動更新しません。qa: :test を手動で追加してください。")
      System.halt(1)
    else
      String.replace(
        mix_content,
        ~r/^\s*def application do/m,
        insert <> "  def application do",
        global: false
      )
    end

  if updated == mix_content do
    IO.puts(:stderr, "Error: mix.exs へ qa: :test を安全に挿入できませんでした")
    System.halt(1)
  end

  File.write!(mix_exs, updated)
end

if not File.exists?(test_file) and File.exists?(app_file) do
  app_module =
    basename
    |> String.split("_")
    |> Enum.map_join(&String.capitalize/1)

  test_source = """
defmodule #{app_module}Test do
  use ExUnit.Case
  doctest #{app_module}

  test "start function is available" do
    assert is_function(&#{app_module}.start/0)
  end
end
"""

  File.write!(test_file, test_source)
end

IO.puts("Harness installed in #{project_dir}")
