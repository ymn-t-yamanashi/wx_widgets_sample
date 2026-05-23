defmodule Tetris.GameLoopTest do
  use ExUnit.Case, async: true
  alias Tetris.GameLoop

  test "left wall is respected" do
    state = %{
      board: Tetris.Board.empty(),
      current: %{type: :o, rot: 0, x: 0, y: 0},
      next_bag: [:i],
      score: 0,
      paused: false,
      over: false
    }

    assert GameLoop.apply_action(state, :move_left).current.x == 0
  end

  test "soft drop moves one row" do
    state = %{
      board: Tetris.Board.empty(),
      current: %{type: :o, rot: 0, x: 4, y: 0},
      next_bag: [:i],
      score: 0,
      paused: false,
      over: false
    }

    assert GameLoop.apply_action(state, :soft_drop).current.y == 1
  end

  test "pause toggles" do
    state = %{
      board: Tetris.Board.empty(),
      current: %{type: :o, rot: 0, x: 4, y: 0},
      next_bag: [:i],
      score: 0,
      paused: false,
      over: false
    }

    assert GameLoop.apply_action(state, :toggle_pause).paused
  end

  test "restart resets state" do
    state = %{
      board: Tetris.Board.empty(),
      current: %{type: :o, rot: 0, x: 2, y: 10},
      next_bag: [],
      score: 900,
      paused: false,
      over: false
    }

    reset = GameLoop.apply_action(state, :restart)
    assert reset.score == 0
    assert reset.current.y == 0
  end

  test "right wall is respected" do
    state = %{
      board: Tetris.Board.empty(),
      current: %{type: :o, rot: 0, x: 8, y: 0},
      next_bag: [:i],
      score: 0,
      paused: false,
      over: false
    }

    assert GameLoop.apply_action(state, :move_right).current.x == 8
  end

  test "hard drop lands and locks piece" do
    state = %{
      board: Tetris.Board.empty(),
      current: %{type: :o, rot: 0, x: 4, y: 0},
      next_bag: [:i, :t],
      score: 0,
      paused: false,
      over: false
    }

    next = GameLoop.apply_action(state, :hard_drop)
    assert next.current.type == :i
    assert next.board |> List.last() |> Enum.at(4) == :o
  end

  test "paused state ignores movement inputs" do
    state = %{
      board: Tetris.Board.empty(),
      current: %{type: :o, rot: 0, x: 4, y: 0},
      next_bag: [:i],
      score: 0,
      paused: true,
      over: false
    }

    assert GameLoop.apply_action(state, :move_left).current.x == 4
  end
end
