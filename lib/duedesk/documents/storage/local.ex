defmodule DueDesk.Documents.Storage.Local do
  @moduledoc """
  Stores documents in a directory on disk, configured as `:root` under
  `DueDesk.Documents.Storage`. Used in development and tests.

  Paths are built only from the key and must stay inside the root.
  """
  @behaviour DueDesk.Documents.Storage

  alias DueDesk.Documents.Document

  @impl true
  def put(key, source_path, _content_type) do
    with {:ok, path} <- path(key),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      File.cp(source_path, path)
    end
  end

  @impl true
  def delete(key) do
    with {:ok, path} <- path(key) do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def download(%Document{storage_key: key}) do
    {:ok, path} = path(key)
    {:file, path}
  end

  @doc "The file path for `key`, or `{:error, :invalid_key}` if it leaves the root."
  def path(key) when is_binary(key) do
    root = root()
    path = Path.expand(key, root)

    if String.starts_with?(path, root <> "/"), do: {:ok, path}, else: {:error, :invalid_key}
  end

  defp root do
    :duedesk
    |> Application.fetch_env!(DueDesk.Documents.Storage)
    |> Keyword.fetch!(:root)
    |> Path.expand()
  end
end
