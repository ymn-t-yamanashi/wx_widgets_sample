defmodule ElixirWxCameraViewerTest do
  use ExUnit.Case

  test "module exists" do
    assert Code.ensure_loaded?(ElixirWxCameraViewer)
  end

  test "camera API exports recording toggle" do
    assert Code.ensure_loaded?(ElixirWxCameraViewer.Camera)
    assert function_exported?(ElixirWxCameraViewer.Camera, :toggle_recording, 0)
  end
end
