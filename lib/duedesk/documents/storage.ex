defmodule DueDesk.Documents.Storage do
  @moduledoc """
  Where document files live. The adapter is configured under
  `config :duedesk, DueDesk.Documents.Storage, adapter: ...`:

    * `DueDesk.Documents.Storage.Local` — a directory on disk (dev, test);
    * `DueDesk.Documents.Storage.S3` — a private S3 or R2 bucket (prod).

  Keys are built by `DueDesk.Documents` only, never from user input
  directly.
  """

  alias DueDesk.Documents.Document

  @doc "Stores the file at `source_path` under `key`."
  @callback put(key :: String.t(), source_path :: Path.t(), content_type :: String.t()) ::
              :ok | {:error, term()}

  @doc "Removes the object at `key`. Removing a missing object is not an error."
  @callback delete(key :: String.t()) :: :ok | {:error, term()}

  @doc "How to hand the file to the browser: a local path or a short-lived URL."
  @callback download(Document.t()) :: {:file, Path.t()} | {:redirect, String.t()}

  def put(key, source_path, content_type), do: adapter().put(key, source_path, content_type)
  def delete(key), do: adapter().delete(key)
  def download(%Document{} = document), do: adapter().download(document)

  defp adapter do
    :duedesk
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:adapter)
  end

  @doc """
  The `Content-Disposition` value for a download: always an attachment,
  so a file is never rendered in the browser.
  """
  def attachment_disposition(filename) do
    ascii =
      filename
      |> String.replace(~r/[^A-Za-z0-9._ -]/u, "_")
      |> String.slice(0, 150)

    ~s(attachment; filename="#{ascii}"; filename*=UTF-8''#{URI.encode(filename, &URI.char_unreserved?/1)})
  end
end
