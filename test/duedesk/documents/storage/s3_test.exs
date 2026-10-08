defmodule DueDesk.Documents.Storage.S3Test do
  use ExUnit.Case, async: true

  import DueDesk.DocumentsFixtures, only: [tmp_file: 1]

  alias DueDesk.Documents.Document
  alias DueDesk.Documents.Storage.S3

  @secret "test-secret-access-key-not-real"

  defp config do
    [
      bucket: "duedesk-docs",
      region: "auto",
      endpoint: "https://example.r2.cloudflarestorage.com",
      access_key_id: "test-access-key",
      secret_access_key: @secret,
      req_options: [plug: {Req.Test, S3}]
    ]
  end

  test "downloads through a signed URL that saves the file as an attachment" do
    document = %Document{
      storage_key: "accounts/a/documents/d/GST-ack.pdf",
      filename: "GST ack.pdf",
      content_type: "application/pdf"
    }

    assert {:redirect, url} = S3.download(document, config(), ~U[2027-03-15 10:00:00Z])

    uri = URI.parse(url)
    query = URI.decode_query(uri.query)

    assert uri.host == "example.r2.cloudflarestorage.com"
    assert uri.path == "/duedesk-docs/accounts/a/documents/d/GST-ack.pdf"
    assert query["X-Amz-Expires"] == "300"
    assert query["X-Amz-Date"] == "20270315T100000Z"
    assert query["X-Amz-Credential"] =~ "test-access-key/20270315/auto/s3/aws4_request"
    assert query["X-Amz-Signature"] =~ ~r/^[0-9a-f]{64}$/
    assert query["response-content-disposition"] =~ ~s(attachment; filename="GST ack.pdf")
    assert query["response-content-type"] == "application/pdf"
    refute url =~ @secret
  end

  test "puts and deletes signed objects" do
    Req.Test.expect(S3, fn conn ->
      assert conn.method == "PUT"
      assert conn.request_path == "/duedesk-docs/accounts/a/documents/d/note.txt"
      assert [auth] = Plug.Conn.get_req_header(conn, "authorization")
      assert auth =~ "AWS4-HMAC-SHA256 Credential=test-access-key/"
      refute auth =~ @secret
      assert Plug.Conn.get_req_header(conn, "content-type") == ["text/plain"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body == "hello"
      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert :ok =
             S3.put("accounts/a/documents/d/note.txt", tmp_file("hello"), "text/plain", config())

    Req.Test.expect(S3, fn conn ->
      assert conn.method == "DELETE"
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert :ok = S3.delete("accounts/a/documents/d/note.txt", config())
  end

  test "a missing object is already deleted; other failures are errors" do
    Req.Test.expect(S3, &Plug.Conn.send_resp(&1, 404, ""))
    assert :ok = S3.delete("k", config())

    Req.Test.expect(S3, &Plug.Conn.send_resp(&1, 403, "denied"))
    assert {:error, {:http_status, 403}} = S3.delete("k", config())

    Req.Test.expect(S3, &Plug.Conn.send_resp(&1, 500, ""))
    assert {:error, {:http_status, 500}} = S3.put("k", tmp_file("x"), "text/plain", config())
  end
end
