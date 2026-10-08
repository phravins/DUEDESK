defmodule DueDesk.Documents.Storage.LocalTest do
  use ExUnit.Case, async: true

  import DueDesk.DocumentsFixtures, only: [tmp_file: 1]

  alias DueDesk.Documents.Document
  alias DueDesk.Documents.Storage.Local

  test "puts, downloads and deletes a file" do
    key = "accounts/a/documents/#{Ecto.UUID.generate()}/note.txt"

    assert :ok = Local.put(key, tmp_file("hello"), "text/plain")
    assert {:file, path} = Local.download(%Document{storage_key: key})
    assert File.read!(path) == "hello"

    assert :ok = Local.delete(key)
    refute File.exists?(path)
    assert :ok = Local.delete(key)
  end

  test "refuses a key that leaves the root" do
    for key <- ["../outside.txt", "accounts/../../outside.txt", "/etc/passwd/../../x", ""] do
      assert {:error, :invalid_key} = Local.path(key)
      assert {:error, :invalid_key} = Local.put(key, tmp_file("x"), "text/plain")
      assert {:error, :invalid_key} = Local.delete(key)
    end
  end
end
