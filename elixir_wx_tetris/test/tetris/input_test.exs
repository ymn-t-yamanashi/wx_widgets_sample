defmodule Tetris.InputTest do
  use ExUnit.Case, async: true
  alias Tetris.Input

  test "key mapping" do
    assert Input.to_action(%{key_code: 314}) == :move_left
    assert Input.to_action(%{key_code: 316}) == :move_right
    assert Input.to_action(%{key_code: 317}) == :soft_drop
    assert Input.to_action(%{key_code: 315}) == :rotate_cw
    assert Input.to_action(%{key_code: 32}) == :hard_drop
    assert Input.to_action(%{key_code: 27}) == :quit
  end

  test "case insensitive letters" do
    assert Input.to_action(%{unicode_key: ?x}) == :rotate_cw
    assert Input.to_action(%{unicode_key: ?X}) == :rotate_cw
    assert Input.to_action(%{unicode_key: ?z}) == :rotate_ccw
    assert Input.to_action(%{unicode_key: ?Z}) == :rotate_ccw
    assert Input.to_action(%{unicode_key: ?p}) == :toggle_pause
    assert Input.to_action(%{unicode_key: ?R}) == :restart
  end

  test "unknown key is noop" do
    assert Input.to_action(%{key_code: 999}) == :noop
  end
end
