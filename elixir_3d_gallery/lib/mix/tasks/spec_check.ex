defmodule Mix.Tasks.SpecCheck do
  use Mix.Task

  @shortdoc "Validate implementation against configurable spec rules"

  @moduledoc """
  Rule-file driven spec checker.

  Usage:
    mix spec_check
    mix spec_check --rules spec_check_rules.exs
  """

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [rules: :string])
    rules_path = Keyword.get(opts, :rules, "spec_check_rules.exs")

    with {:ok, rules} <- load_rules(rules_path) do
      checks = build_checks(rules)
      {passes, fails} = Enum.split_with(checks, fn {_name, ok?} -> ok? end)

      Enum.each(passes, fn {name, _} -> Mix.shell().info("[PASS] #{name}") end)
      Enum.each(fails, fn {name, _} -> Mix.shell().error("[FAIL] #{name}") end)

      if fails == [] do
        Mix.shell().info("spec_check: 合格")
      else
        Mix.raise("spec_check: 不合格 (#{length(fails)}件)")
      end
    else
      {:error, msg} -> Mix.raise(msg)
    end
  end

  defp load_rules(path) do
    if File.exists?(path) do
      {rules, _binding} = Code.eval_file(path)

      if is_map(rules), do: {:ok, rules}, else: {:error, "ルールファイルは map を返してください: #{path}"}
    else
      {:error, "ルールファイルが見つかりません: #{path}"}
    end
  rescue
    error -> {:error, "ルールファイル読込失敗: #{path} (#{Exception.message(error)})"}
  end

  defp build_checks(rules) do
    spec_path = Map.get(rules, :spec_path, "")
    files = Map.get(rules, :files, %{})
    contains = Map.get(rules, :contains, [])

    spec_text = read_file(spec_path)

    file_texts =
      Enum.into(files, %{}, fn {key, path} ->
        {key, read_file(path)}
      end)

    [{"specファイルが存在", spec_text != nil}] ++
      Enum.map(contains, fn %{name: name, file: file_key, patterns: patterns} ->
        text = Map.get(file_texts, file_key)
        ok? = is_binary(text) and Enum.all?(patterns, &String.contains?(text, &1))
        {name, ok?}
      end)
  end

  defp read_file(path) when is_binary(path) and path != "" do
    case File.read(path) do
      {:ok, text} -> text
      _ -> nil
    end
  end

  defp read_file(_), do: nil
end
