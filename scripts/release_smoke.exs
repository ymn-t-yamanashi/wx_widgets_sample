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
  IO.puts("        mix run --no-halt")
  System.halt(0)
end

IO.puts("[smoke] GUI起動スモークを実行します（5秒）...")
mix_exe = System.find_executable("mix") || "mix"
port = Port.open({:spawn_executable, mix_exe}, [:binary, :exit_status, :use_stdio, :stderr_to_stdout, {:args, ["run", "--no-halt"]}, {:cd, project_dir}])

result =
  receive do
    {^port, {:exit_status, status}} -> {:exited, status}
  after
    5_000 -> :alive
  end

case result do
  {:exited, 0} ->
    IO.puts("[smoke] GUIプロセスが終了コード0で終了")

  {:exited, status} ->
    IO.puts(:stderr, "[smoke] GUIスモーク失敗 (exit: #{status})")
    System.halt(status)

  :alive ->
    Port.close(port)
    IO.puts("[smoke] 5秒起動できたため成功")
end
