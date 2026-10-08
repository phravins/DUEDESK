defmodule DueDesk.DocumentsFixtures do
  @moduledoc """
  Test helpers for documents. Files are written to a temporary path and
  stored through `DueDesk.Documents.prepare_upload/2`, as the upload
  forms do.
  """

  import Ecto.Query, only: [from: 2]

  alias DueDesk.{Documents, Repo}
  alias DueDesk.Accounts.Scope
  alias DueDesk.Documents.Storage
  alias DueDesk.Tenancy.CustomerAccount

  @doc "Writes `contents` to a new temporary file and returns its path."
  def tmp_file(contents) do
    dir = Path.join(System.tmp_dir!(), "duedesk_test_files")
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{System.unique_integer([:positive])}.tmp")
    File.write!(path, contents)
    ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)
    path
  end

  @doc "Stores a file and returns the upload to attach."
  def upload_fixture(%Scope{} = scope, name \\ "receipt.pdf", contents \\ "%PDF-1.4 receipt") do
    {:ok, upload} =
      Documents.prepare_upload(scope, %{path: tmp_file(contents), client_name: name})

    upload
  end

  @doc "Attaches one file to the DueItem's current cycle and returns the document."
  def document_fixture(%Scope{} = scope, item, attrs \\ %{}) do
    attrs = Map.new(attrs)
    upload = upload_fixture(scope, attrs[:filename] || "receipt.pdf", attrs[:contents] || "%PDF")

    {:ok, [document]} =
      Documents.attach_documents(scope, item, attrs[:role] || "current", [upload])

    document
  end

  @doc "Whether a file is stored under `key` (local storage)."
  def stored?(key) do
    {:ok, path} = Storage.Local.path(key)
    File.exists?(path)
  end

  @doc "The account's storage counter, read from the database."
  def storage_used(%Scope{} = scope) do
    Repo.one!(
      from a in CustomerAccount,
        where: a.id == ^Scope.account_id!(scope),
        select: a.storage_used_bytes
    )
  end

  @doc "Sets the account's storage counter directly."
  def put_storage_used(%Scope{} = scope, bytes) do
    Repo.update_all(from(a in CustomerAccount, where: a.id == ^Scope.account_id!(scope)),
      set: [storage_used_bytes: bytes]
    )

    scope
  end
end
