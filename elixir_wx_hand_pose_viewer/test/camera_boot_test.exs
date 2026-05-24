defmodule ElixirWxHandPoseViewer.CameraBootTest do
  use ExUnit.Case, async: false

  test "camera server starts and responds without camera" do
    {:ok, pid} =
      start_supervised(
        {ElixirWxHandPoseViewer.Camera, [device: 99, width: 320, height: 240, fps: 15]}
      )

    assert Process.alive?(pid)

    # In CI/headless env this may be error while opening camera, but process must stay alive.
    reply = ElixirWxHandPoseViewer.Camera.latest_frame()
    assert match?({:ok, _}, reply) or match?({:error, _}, reply)
  end

  test "toggle pause works" do
    {:ok, _pid} =
      start_supervised(
        {ElixirWxHandPoseViewer.Camera, [device: 99, width: 320, height: 240, fps: 15]}
      )

    assert {:ok, true} = ElixirWxHandPoseViewer.Camera.toggle_pause()
    assert {:ok, false} = ElixirWxHandPoseViewer.Camera.toggle_pause()
  end
end
