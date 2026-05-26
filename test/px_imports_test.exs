defmodule PxImportsTest do
  use ExUnit.Case

  test "PxImports module loads" do
    assert Code.ensure_loaded?(PxImports)
  end
end
