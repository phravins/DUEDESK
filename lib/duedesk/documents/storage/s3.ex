defmodule DueDesk.Documents.Storage.S3 do
  @moduledoc """
  Stores documents in a private S3-compatible bucket (AWS S3 or
  Cloudflare R2), signed with AWS Signature Version 4 through `Req`.

  Configured in `config/runtime.exs` from `S3_BUCKET`, `S3_REGION`,
  `S3_ENDPOINT`, `S3_ACCESS_KEY_ID` and `S3_SECRET_ACCESS_KEY`. Objects
  are addressed path-style (`endpoint/bucket/key`). Uploads are streamed
  from disk; downloads are short-lived signed URLs that always save the
  file as an attachment. Keys and secrets are never logged.
  """
  @behaviour DueDesk.Documents.Storage

  alias DueDesk.Documents.{Document, Storage}

  @chunk 64 * 1024
  @download_seconds 300

  @impl true
  def put(key, source_path, content_type), do: put(key, source_path, content_type, config())

  def put(key, source_path, content_type, config) do
    %{size: size} = File.stat!(source_path)

    config
    |> req()
    |> Req.put(
      url: object_url(config, key),
      headers: [content_type: content_type, content_length: size],
      body: File.stream!(source_path, @chunk)
    )
    |> result()
  end

  @impl true
  def delete(key), do: delete(key, config())

  def delete(key, config) do
    case config |> req() |> Req.delete(url: object_url(config, key)) do
      {:ok, %{status: 404}} -> :ok
      other -> result(other)
    end
  end

  @impl true
  def download(%Document{} = document), do: download(document, config(), DateTime.utc_now())

  def download(%Document{} = document, config, %DateTime{} = now) do
    url =
      Req.Utils.aws_sigv4_url(
        access_key_id: config[:access_key_id],
        secret_access_key: config[:secret_access_key],
        region: config[:region],
        service: "s3",
        datetime: now,
        method: :get,
        url: object_url(config, document.storage_key),
        expires: @download_seconds,
        query: [
          {"response-content-disposition", Storage.attachment_disposition(document.filename)},
          {"response-content-type", document.content_type}
        ]
      )

    {:redirect, URI.to_string(url)}
  end

  defp req(config) do
    Req.new(
      aws_sigv4: [
        access_key_id: config[:access_key_id],
        secret_access_key: config[:secret_access_key],
        region: config[:region],
        service: :s3
      ],
      retry: false
    )
    |> Req.merge(Keyword.get(config, :req_options, []))
  end

  defp result({:ok, %Req.Response{status: status}}) when status in 200..299, do: :ok
  defp result({:ok, %Req.Response{status: status}}), do: {:error, {:http_status, status}}
  defp result({:error, exception}), do: {:error, exception}

  defp object_url(config, key) do
    endpoint = config[:endpoint] || "https://s3.#{config[:region]}.amazonaws.com"
    "#{String.trim_trailing(endpoint, "/")}/#{config[:bucket]}/#{key}"
  end

  defp config, do: Application.fetch_env!(:duedesk, __MODULE__)
end
