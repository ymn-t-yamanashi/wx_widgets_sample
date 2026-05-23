defmodule Tetris.GameLoop do
  use GenServer
  alias Tetris.{Board, Piece}

  @tick_ms 450

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def state, do: GenServer.call(__MODULE__, :state)
  def action(a), do: GenServer.cast(__MODULE__, {:action, a})

  def init(_) do
    s = new_state()
    schedule_tick()
    {:ok, s}
  end

  def handle_call(:state, _from, state), do: {:reply, state, state}

  def handle_cast({:action, :quit}, state), do: {:stop, :normal, state}
  def handle_cast({:action, action}, state), do: {:noreply, apply_action(state, action)}

  def handle_info(:tick, state) do
    schedule_tick()
    {:noreply, if(state.paused or state.over, do: state, else: gravity_step(state))}
  end

  def apply_action(state, :noop), do: state
  def apply_action(state, :toggle_pause), do: %{state | paused: !state.paused}
  def apply_action(_state, :restart), do: new_state()
  def apply_action(state, _) when state.paused or state.over, do: state

  def apply_action(state, :move_left), do: try_move(state, -1, 0)
  def apply_action(state, :move_right), do: try_move(state, 1, 0)
  def apply_action(state, :soft_drop), do: gravity_step(state)
  def apply_action(state, :rotate_cw), do: try_rotate(state, 1)
  def apply_action(state, :rotate_ccw), do: try_rotate(state, -1)
  def apply_action(state, :hard_drop), do: hard_drop(state)

  defp new_state do
    bag = shuffled_bag()
    {piece, rest} = spawn_piece(bag)
    %{board: Board.empty(), current: piece, next_bag: rest, score: 0, paused: false, over: false}
  end

  defp shuffled_bag, do: Enum.shuffle(Piece.types())

  defp spawn_piece([]), do: spawn_piece(shuffled_bag())
  defp spawn_piece([type | rest]), do: {%{type: type, rot: 0, x: 4, y: 0}, rest}

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)

  defp try_move(state, dx, dy) do
    candidate = %{state.current | x: state.current.x + dx, y: state.current.y + dy}
    if Board.fits?(state.board, candidate), do: %{state | current: candidate}, else: state
  end

  defp try_rotate(state, dr) do
    candidate = %{state.current | rot: rem(state.current.rot + dr + 4, 4)}
    if Board.fits?(state.board, candidate), do: %{state | current: candidate}, else: state
  end

  defp gravity_step(state) do
    moved = %{state.current | y: state.current.y + 1}
    if Board.fits?(state.board, moved), do: %{state | current: moved}, else: lock_and_spawn(state)
  end

  defp hard_drop(state) do
    final =
      Stream.iterate(state.current, &%{&1 | y: &1.y + 1})
      |> Enum.reduce_while(state.current, fn p, last ->
        if Board.fits?(state.board, p), do: {:cont, p}, else: {:halt, last}
      end)

    lock_and_spawn(%{state | current: final})
  end

  defp lock_and_spawn(state) do
    board = Board.place(state.board, state.current)
    {board2, lines} = Board.clear_lines(board)
    score = state.score + lines * 100
    {next_piece, rest} = spawn_piece(state.next_bag)

    if Board.fits?(board2, next_piece) do
      %{state | board: board2, current: next_piece, next_bag: rest, score: score}
    else
      %{state | board: board2, score: score, over: true}
    end
  end
end
