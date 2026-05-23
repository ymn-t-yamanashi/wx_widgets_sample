#!/usr/bin/env elixir

repo_root = Path.expand("..", __DIR__)

{_out, status} = System.cmd("git", ["-C", repo_root, "config", "core.hooksPath", ".githooks"], stderr_to_stdout: true)

if status == 0 do
  IO.puts("Git hooks path を .githooks に設定しました。")
  IO.puts("以後、コミット時に pre-commit で mix qa が実行されます。")
else
  IO.puts(:stderr, "Git hooks path の設定に失敗しました。")
  System.halt(status)
end
