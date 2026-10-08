defmodule DueDeskWeb.OrganisationComponents do
  @moduledoc """
  The Organisation form, shared by the Organisation pages and onboarding
  step 4, and the helper that captures declaration evidence.
  """
  use DueDeskWeb, :html

  alias DueDesk.Organisations.{Declaration, Identifier, Organisation}

  @doc """
  The Organisation form. The identifier field follows the chosen type, and
  the declaration is shown when saving needs one.

  The parent LiveView handles `"validate"` and `"save"`.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :id, :string, required: true
  attr :declaration, :boolean, default: true, doc: "show the declaration checkbox"
  slot :actions, required: true

  def organisation_form(assigns) do
    identifier_type = Identifier.identifier_type(assigns.form[:type].value)

    assigns =
      assigns
      |> assign(:identifier_type, identifier_type)
      |> assign(:duplicate?, duplicate?(assigns.form))

    ~H"""
    <.form for={@form} id={@id} phx-change="validate" phx-submit="save">
      <div
        :if={@duplicate?}
        id="duplicate-notice"
        class="mb-5 flex gap-3 rounded-lg border border-rose-200 bg-rose-50/60 p-4 text-sm"
      >
        <.icon name="hero-exclamation-circle-mini" class="mt-px size-5 shrink-0 text-rose-600" />
        <div class="text-rose-900">
          <p class="font-medium">{Organisation.duplicate_message()}</p>
          <p class="mt-1">
            If you are authorised to manage it,
            <.link
              id="duplicate-support-link"
              navigate={~p"/support"}
              class="font-medium underline underline-offset-2 hover:text-rose-700"
            >
              contact support
            </.link>
            and we will help.
          </p>
        </div>
      </div>

      <.input
        field={@form[:name]}
        type="text"
        label="Organisation name"
        placeholder="e.g. Sharma Traders"
        autocomplete="organization"
        required
      />
      <.input
        field={@form[:type]}
        type="select"
        label="Organisation type"
        prompt="Choose a type"
        options={Identifier.type_options()}
        required
      />
      <.input
        field={@form[:identifier]}
        type="text"
        label={Identifier.label(@identifier_type)}
        placeholder={Identifier.example(@identifier_type) || "Choose the type first"}
        hint={identifier_hint(@identifier_type)}
        autocomplete="off"
        required
      />
      <.input
        field={@form[:gstin]}
        type="text"
        label="GSTIN (optional)"
        placeholder="e.g. 27AAPFU0939F1ZV"
        autocomplete="off"
        maxlength="20"
      />

      <div
        :if={@declaration}
        id={"#{@id}-declaration"}
        class="mb-6 rounded-md border border-line bg-[#fafaf9] p-4 [&>div]:mb-0"
      >
        <p class="mb-3 text-sm leading-relaxed text-zinc-700">{Declaration.text()}</p>
        <.input
          field={@form[:declaration_accepted]}
          type="checkbox"
          label="I confirm this declaration"
        />
      </div>

      {render_slot(@actions)}
    </.form>
    """
  end

  defp identifier_hint(nil), do: "The registration number depends on the Organisation type."

  defp identifier_hint("udyam"),
    do: "Proprietorships and Partnerships are identified by their Udyam registration."

  defp identifier_hint("llpin"), do: "The LLP Identification Number issued by the MCA."
  defp identifier_hint("cin"), do: "The 21-character Corporate Identification Number."

  defp duplicate?(form) do
    duplicate = Organisation.duplicate_message()
    Enum.any?(form[:identifier].errors, fn {message, _} -> message == duplicate end)
  end

  @doc """
  The connection details stored with a declaration. Call it from `mount/3`,
  where connect info is available.
  """
  def declaration_meta(socket) do
    ip =
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: address} -> address |> :inet.ntoa() |> to_string()
        _ -> nil
      end

    %{ip: ip, user_agent: Phoenix.LiveView.get_connect_info(socket, :user_agent)}
  end
end
