defmodule DueDeskWeb.DocumentController do
  @moduledoc """
  Downloads a document. Files are always sent as attachments, never shown
  in the browser; from S3 or R2 the browser is sent to a short-lived
  signed URL that does the same.
  """
  use DueDeskWeb, :controller

  alias DueDesk.Documents
  alias DueDesk.Documents.Storage

  def download(conn, %{"id" => id}) do
    with {:ok, document} <- Documents.get_document(conn.assigns.current_scope, id) do
      case Storage.download(document) do
        {:file, path} ->
          conn
          |> put_resp_header("cache-control", "private, no-store")
          |> put_resp_header("x-content-type-options", "nosniff")
          |> send_download({:file, path},
            filename: document.filename,
            content_type: document.content_type,
            disposition: :attachment
          )

        {:redirect, url} ->
          conn
          |> put_resp_header("cache-control", "private, no-store")
          |> redirect(external: url)
      end
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "This DueItem is not available to your account access.")
        |> redirect(to: ~p"/due-items")
    end
  end
end
