defmodule DueDeskWeb.DocumentComponents do
  @moduledoc """
  Document uploads and lists, shared by the detail page and the renew
  and complete forms.

  A LiveView calls `allow_documents/1` in mount, renders
  `<.document_dropzone>` inside its form, checks `selection_error/1`
  before saving and stores the files with `consume_documents/1`. Files
  are measured and stored on the server; the browser's size is only used
  for the early storage check.
  """
  use DueDeskWeb, :html

  alias DueDesk.{Billing, Documents}
  alias DueDesk.Billing.Plans
  alias DueDesk.Documents.Document

  ## Socket helpers

  @doc """
  Allows the `:documents` upload (any file type, up to 5 files of 30 MB)
  and assigns the account's storage as `:storage`.
  """
  def allow_documents(socket) do
    socket
    |> Phoenix.LiveView.allow_upload(:documents,
      accept: :any,
      max_entries: Documents.max_files(),
      max_file_size: Documents.max_file_size()
    )
    |> refresh_storage()
  end

  @doc "Reads the account's storage again, after files were added or removed."
  def refresh_storage(socket) do
    Phoenix.Component.assign(socket, :storage, Billing.storage(socket.assigns.current_scope))
  end

  @doc "Removes a file from the selection."
  def cancel_document(socket, ref), do: Phoenix.LiveView.cancel_upload(socket, :documents, ref)

  @doc "Whether any files are selected."
  def documents_selected?(socket), do: socket.assigns.uploads.documents.entries != []

  @doc """
  Whether files are selected and none has an error. An entry can turn
  invalid after the form's change event (for example when it is too
  large), so templates check the entries themselves.
  """
  def uploadable?(upload) do
    upload.entries != [] and upload_errors(upload) == [] and
      Enum.all?(upload.entries, & &1.valid?)
  end

  @doc """
  Why the selected files cannot be saved, or `nil`: a file is too large,
  too many are selected, or they do not fit in the storage left. The
  transaction checks storage again against the locked account row.
  """
  def selection_error(socket) do
    %{uploads: %{documents: upload}, storage: storage, current_scope: scope} = socket.assigns
    selected = upload.entries |> Enum.map(& &1.client_size) |> Enum.sum()

    cond do
      upload_errors(upload) != [] ->
        upload |> upload_errors() |> List.first() |> upload_error()

      Enum.any?(upload.entries, &(not &1.valid?)) ->
        "Remove the files that cannot be uploaded, then try again."

      selected > storage.left ->
        Billing.limit_message(scope, %{
          plan: Billing.plan(scope),
          limit: storage.limit,
          resource: :storage,
          used: storage.used
        })

      true ->
        nil
    end
  end

  @doc """
  Stores the selected files. Returns `{:ok, uploads}` to pass to the
  context, or `{:error, message}` with nothing left stored.
  """
  def consume_documents(socket) do
    scope = socket.assigns.current_scope

    results =
      Phoenix.LiveView.consume_uploaded_entries(socket, :documents, fn %{path: path}, entry ->
        {:ok, Documents.prepare_upload(scope, %{path: path, client_name: entry.client_name})}
      end)

    {stored, failed} = Enum.split_with(results, &match?({:ok, _}, &1))
    uploads = Enum.map(stored, fn {:ok, upload} -> upload end)

    case failed do
      [] ->
        {:ok, uploads}

      [{:error, reason} | _] ->
        Documents.discard_uploads(uploads)
        {:error, prepare_error(reason)}
    end
  end

  defp prepare_error(:empty), do: "This file is empty."
  defp prepare_error(:too_large), do: upload_error(:too_large)
  defp prepare_error(_), do: "The files could not be uploaded. Please try again."

  @doc "The message for a LiveView upload error."
  def upload_error(:too_large),
    do: "This file is larger than #{Plans.format_bytes(Documents.max_file_size())}."

  def upload_error(:too_many_files), do: "Choose up to #{Documents.max_files()} files at a time."
  def upload_error(:not_accepted), do: "This file type cannot be uploaded."
  def upload_error(_), do: "This file could not be uploaded. Please try again."

  @doc """
  The flash message after files were stored: "2 documents uploaded."
  """
  def uploaded_message([_]), do: "Document uploaded."
  def uploaded_message(documents), do: "#{length(documents)} documents uploaded."

  ## Components

  @doc """
  A drop target and file picker for the `:documents` upload, with each
  selected file's name, size, progress and errors. Place it inside the
  form that submits the files.
  """
  attr :upload, :any, required: true
  attr :storage, :map, required: true
  attr :hint, :string, default: nil
  attr :error, :string, default: nil

  def document_dropzone(assigns) do
    ~H"""
    <div id="document-dropzone" class="space-y-3">
      <label
        for={@upload.ref}
        phx-drop-target={@upload.ref}
        class="group flex cursor-pointer flex-col items-center justify-center gap-1.5 rounded-lg border border-dashed border-zinc-300 bg-[#fafaf9] px-4 py-6 text-center transition hover:border-zinc-400 hover:bg-[#f6f6f4] phx-drop-target-active:border-navy phx-drop-target-active:bg-sky-50/60"
      >
        <span class="flex size-9 items-center justify-center rounded-full bg-white shadow-xs ring-1 ring-line transition group-hover:-translate-y-0.5">
          <.icon name="hero-arrow-up-tray" class="size-4 text-zinc-500" />
        </span>
        <span class="text-sm text-ink">
          Drop files here or
          <span class="font-medium text-navy underline-offset-2 group-hover:underline">browse</span>
        </span>
        <span class="text-xs text-muted">
          {@hint || "Any file type"}, up to {Plans.format_bytes(@upload.max_file_size)} each, {@upload.max_entries} at a time.
        </span>
        <.live_file_input upload={@upload} class="sr-only" />
      </label>

      <ul :if={@upload.entries != []} id="document-selection" class="space-y-2">
        <li
          :for={entry <- @upload.entries}
          id={"upload-entry-#{entry.ref}"}
          class={[
            "rounded-md border px-3 py-2.5",
            if(entry.valid?, do: "border-line bg-white", else: "border-rose-200 bg-rose-50/50")
          ]}
        >
          <div class="flex items-center gap-3">
            <.file_icon filename={entry.client_name} />
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm text-ink">{entry.client_name}</p>
              <p class="text-xs text-muted">{Plans.format_bytes(entry.client_size)}</p>
            </div>
            <button
              type="button"
              id={"cancel-upload-#{entry.ref}"}
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              aria-label={"Remove #{entry.client_name}"}
              class="rounded-md p-1 text-zinc-400 transition hover:bg-zinc-100 hover:text-ink"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>
          <div
            :if={entry.valid? and entry.progress > 0}
            class="mt-2 h-1 overflow-hidden rounded-full bg-zinc-100"
          >
            <div
              class="h-full rounded-full bg-navy transition-all duration-300"
              style={"width: #{entry.progress}%"}
            />
          </div>
          <p
            :for={err <- upload_errors(@upload, entry)}
            class="mt-1.5 text-xs text-rose-600"
          >
            {upload_error(err)}
          </p>
        </li>
      </ul>

      <p
        :if={@error}
        id="document-error"
        class="flex items-start gap-2 rounded-md border border-amber-200/70 bg-amber-50/60 px-3 py-2 text-xs text-amber-900"
      >
        <.icon name="hero-exclamation-triangle" class="mt-px size-4 shrink-0 text-amber-500" />
        <span>{@error}</span>
      </p>

      <p id="storage-used" class="text-xs text-muted">
        {Plans.format_bytes(@storage.used)} of {Plans.format_bytes(@storage.limit)} storage used
      </p>
    </div>
    """
  end

  @doc """
  A list of documents with a download link each, and Remove for the ids
  in `removable`. Give `dom_prefix` when the same documents are listed
  twice on a page, so their element ids stay unique.
  """
  attr :id, :string, required: true
  attr :documents, :list, required: true
  attr :tz, :string, required: true
  attr :removable, :any, default: MapSet.new()
  attr :empty, :string, default: nil
  attr :compact, :boolean, default: false
  attr :dom_prefix, :string, default: ""

  def document_list(assigns) do
    ~H"""
    <ul id={@id} class={["divide-y divide-line", @compact && "text-xs"]}>
      <li :if={@documents == [] and @empty} class="py-2 text-sm text-muted">{@empty}</li>
      <li
        :for={doc <- @documents}
        id={"#{@dom_prefix}document-#{doc.id}"}
        class={["group flex items-center gap-3", if(@compact, do: "py-1.5", else: "py-2.5")]}
      >
        <.file_icon :if={not @compact} filename={doc.filename} />
        <.icon :if={@compact} name="hero-paper-clip" class="size-3.5 shrink-0 text-zinc-400" />
        <div class="min-w-0 flex-1">
          <a
            href={~p"/documents/#{doc.id}/download"}
            id={"#{@dom_prefix}download-#{doc.id}"}
            class={[
              "block truncate text-ink underline-offset-2 transition hover:text-navy hover:underline",
              if(@compact, do: "text-xs", else: "text-sm font-medium")
            ]}
            title={"Download #{doc.filename}"}
          >
            {doc.filename}
          </a>
          <p :if={not @compact} class="text-xs text-muted">
            {Plans.format_bytes(doc.byte_size)} · {uploader(doc)} · {date(
              DateTime.shift_zone!(doc.inserted_at, @tz)
            )}
          </p>
        </div>
        <a
          :if={not @compact}
          href={~p"/documents/#{doc.id}/download"}
          aria-label={"Download #{doc.filename}"}
          class="rounded-md p-1.5 text-zinc-400 transition hover:bg-zinc-100 hover:text-ink"
        >
          <.icon name="hero-arrow-down-tray" class="size-4" />
        </a>
        <button
          :if={MapSet.member?(@removable, doc.id)}
          type="button"
          id={"#{@dom_prefix}remove-document-#{doc.id}"}
          phx-click="remove_document"
          phx-value-id={doc.id}
          data-confirm={"Remove “#{doc.filename}”? The file is deleted and its storage is freed."}
          aria-label={"Remove #{doc.filename}"}
          class="rounded-md p-1.5 text-zinc-400 opacity-100 transition hover:bg-rose-50 hover:text-rose-600 sm:opacity-0 sm:group-hover:opacity-100 sm:focus:opacity-100"
        >
          <.icon name="hero-trash" class="size-4" />
        </button>
      </li>
    </ul>
    """
  end

  defp uploader(%Document{uploaded_by_user: %{name: name}}), do: name
  defp uploader(_doc), do: "A former member"

  attr :filename, :string, required: true

  defp file_icon(assigns) do
    {icon, tone} = file_kind(assigns.filename)
    assigns = assign(assigns, icon: icon, tone: tone)

    ~H"""
    <span class={["flex size-8 shrink-0 items-center justify-center rounded-md", @tone]}>
      <.icon name={@icon} class="size-4" />
    </span>
    """
  end

  defp file_kind(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".pdf" ->
        {"hero-document-text", "bg-rose-50 text-rose-600"}

      ext when ext in ~w(.png .jpg .jpeg .gif .webp .heic .svg) ->
        {"hero-photo", "bg-sky-50 text-sky-600"}

      ext when ext in ~w(.xls .xlsx .csv .ods) ->
        {"hero-table-cells", "bg-emerald-50 text-emerald-600"}

      ext when ext in ~w(.doc .docx .odt .rtf .txt) ->
        {"hero-document", "bg-indigo-50 text-indigo-600"}

      ext when ext in ~w(.zip .rar .7z .gz .tar) ->
        {"hero-archive-box", "bg-amber-50 text-amber-600"}

      _ ->
        {"hero-paper-clip", "bg-zinc-100 text-zinc-500"}
    end
  end
end
