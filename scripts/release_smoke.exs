#!/usr/bin/env elixir

repo_root = Path.expand("..", __DIR__)
project_dir = Path.join(repo_root, "sum_wx")

unless File.dir?(project_dir) do
  IO.puts(:stderr, "[smoke] sum_wx が見つかりません。")
  System.halt(1)
end

run = fn cmd, args ->
  {_, status} = System.cmd(cmd, args, cd: project_dir, into: IO.stream(:stdio, :line), stderr_to_stdout: true)
  status
end

IO.puts("[smoke] format/compile/test を確認します...")
qa_status = run.("mix", ["qa"])
if qa_status != 0, do: System.halt(qa_status)

if System.get_env("DISPLAY") in [nil, ""] do
  IO.puts("[smoke] DISPLAY が未設定のため GUI 起動確認をスキップします。")
  IO.puts("[smoke] GUI起動確認は DISPLAY が使える環境で次を実行してください:")
  IO.puts("        timeout 5s mix run --no-halt")
  System.halt(0)
end

IO.puts("[smoke] GUI起動スモークを実行します（5秒）...")
status = run.("timeout", ["5s", "mix", "run", "--no-halt"])

cond do
  status == 0 ->
    IO.puts("[smoke] GUIスモーク完了")
  status == 124 ->
    IO.puts("[smoke] 5秒起動できたため成功（timeout終了）")
  true ->
    IO.puts(:stderr, "[smoke] GUIスモーク失敗 (exit: #{status})")
    System.halt(status)
end
