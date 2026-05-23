defmodule Mix.Tasks.ReviewRetry do
  use Mix.Task

  @shortdoc "Run review command repeatedly until it passes"

  @moduledoc """
  Repeats an external review command until success or max attempts reached.

  Usage:
    mix review_retry --cmd "<review command>" [--max 5] [--sleep 1]
  """

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [cmd: :string, max: :integer, sleep: :integer])

    cmd = Keyword.get(opts, :cmd)
    max_attempts = Keyword.get(opts, :max, 5)
    sleep_seconds = Keyword.get(opts, :sleep, 1)

    if is_nil(cmd) or cmd == "" do
      Mix.raise("--cmd は必須です")
    end

    retry(cmd, 1, max_attempts, sleep_seconds)
  end

  defp retry(_cmd, attempt, max_attempts, _sleep_seconds) when attempt > max_attempts do
    Mix.raise("レビュー不合格: 最大試行回数に到達しました")
  end

  defp retry(cmd, attempt, max_attempts, sleep_seconds) do
    Mix.shell().info("[review] attempt #{attempt}/#{max_attempts}")
    status = System.shell(cmd, stderr_to_stdout: true) |> elem(1)

    if status == 0 do
      Mix.shell().info("[review] 合格")
      :ok
    else
      Process.sleep(sleep_seconds * 1000)
      retry(cmd, attempt + 1, max_attempts, sleep_seconds)
    end
  end
end
