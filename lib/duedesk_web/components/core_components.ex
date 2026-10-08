defmodule DueDeskWeb.CoreComponents do
  @moduledoc """
  Core UI building blocks: flash notices, buttons, form inputs and icons.
  """
  use Phoenix.Component
  use Gettext, backend: DueDeskWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders a flash notice.
  """
  attr :id, :string
  attr :flash, :map, default: %{}
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error]
  attr :rest, :global

  slot :inner_block

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="pointer-events-auto w-full cursor-pointer"
      {@rest}
    >
      <div class="flex items-start gap-3 rounded-lg border border-line bg-white p-3.5 shadow-float">
        <span class={[
          "flex size-7 shrink-0 items-center justify-center rounded-full",
          @kind == :info && "bg-emerald-50 text-emerald-600",
          @kind == :error && "bg-rose-50 text-rose-600"
        ]}>
          <.icon :if={@kind == :info} name="hero-check-mini" class="size-4" />
          <.icon :if={@kind == :error} name="hero-exclamation-triangle-mini" class="size-4" />
        </span>
        <div class="min-w-0 flex-1 pt-0.5 text-sm leading-5">
          <p :if={@title} class="font-semibold text-ink">{@title}</p>
          <p class="text-zinc-600">{msg}</p>
        </div>
        <button
          type="button"
          class="rounded-md p-1 text-zinc-400 transition hover:bg-zinc-100 hover:text-zinc-700"
          aria-label={gettext("close")}
        >
          <.icon name="hero-x-mark-mini" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  @button_variants %{
    "primary" => "bg-navy text-white shadow-xs hover:bg-navy-hover",
    "navy" => "bg-navy text-white shadow-xs hover:bg-navy-hover",
    "secondary" => "bg-[#efefed] text-ink hover:bg-[#e6e6e3]",
    "outline" => "border border-line bg-white text-ink shadow-xs hover:bg-zinc-50",
    "ghost" => "text-zinc-600 hover:bg-zinc-100 hover:text-ink",
    "danger" => "bg-rose-600 text-white shadow-xs hover:bg-rose-700"
  }

  @button_sizes %{
    "sm" => "h-8 px-3 text-[13px]",
    "md" => "h-9 px-3.5 text-sm",
    "lg" => "h-10 px-4 text-sm"
  }

  @doc """
  Renders a button, or a link styled as one when `navigate`, `patch`
  or `href` is given.

      <.button>Save</.button>
      <.button variant="secondary" navigate={~p"/dashboard"}>Cancel</.button>
  """
  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type form)

  attr :class, :any, default: nil
  attr :variant, :string, default: "primary", values: Map.keys(@button_variants)
  attr :size, :string, default: "md", values: Map.keys(@button_sizes)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns, :classes, [
        "inline-flex items-center justify-center gap-1.5 rounded-md font-medium whitespace-nowrap",
        "transition duration-150 active:scale-[0.98] cursor-pointer",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand",
        "disabled:pointer-events-none disabled:opacity-60 phx-submit-loading:opacity-70",
        Map.fetch!(@button_variants, assigns.variant),
        Map.fetch!(@button_sizes, assigns.size),
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@classes} {@rest}>{render_slot(@inner_block)}</.link>
      """
    else
      ~H"""
      <button class={@classes} {@rest}>{render_slot(@inner_block)}</button>
      """
    end
  end

  @doc """
  Renders a labelled form input with its errors.

  Pass a `Phoenix.HTML.FormField` as `field`, or every attribute explicitly.
  `icon` adds a leading hero icon; password inputs get a show/hide toggle.
  Setting `class` replaces the default input classes.

      <.input field={@form[:email]} type="email" label="Email" icon="hero-envelope" />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :icon, :string, default: nil
  attr :hint, :string, default: nil

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField
  attr :errors, :list, default: []
  attr :checked, :boolean
  attr :prompt, :string, default: nil
  attr :options, :list
  attr :multiple, :boolean, default: false
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-4">
      <label for={@id} class="inline-flex cursor-pointer items-center gap-2.5 text-sm text-zinc-700">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "size-4 rounded border-zinc-300 accent-navy"}
          {@rest}
        />
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-4">
      <.label :if={@label} for={@id}>{@label}</.label>
      <div class="relative">
        <select
          id={@id}
          name={@name}
          class={[@class || [field_class(), "appearance-none pr-10"], @errors != [] && error_class()]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
        <.icon
          name="hero-chevron-up-down-mini"
          class="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-zinc-400"
        />
      </div>
      <p :if={@hint} class="mt-1.5 text-xs text-zinc-500">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-4">
      <.label :if={@label} for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[@class || [field_class(), "h-auto min-h-28 py-3"], @errors != [] && error_class()]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <p :if={@hint} class="mt-1.5 text-xs text-zinc-500">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="mb-4">
      <.label :if={@label} for={@id}>{@label}</.label>
      <div class="relative">
        <.icon
          :if={@icon}
          name={@icon}
          class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-zinc-400"
        />
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || [field_class(), @icon && "pl-9", @type == "password" && "pr-10"],
            @errors != [] && error_class()
          ]}
          {@rest}
        />
        <button
          :if={@type == "password"}
          type="button"
          class="absolute right-1 top-1/2 flex size-8 -translate-y-1/2 items-center justify-center rounded-md text-zinc-400 transition hover:text-zinc-700"
          phx-click={toggle_password(@id)}
          aria-label="Show or hide password"
        >
          <span id={"#{@id}-show"} class="leading-none"><.icon name="hero-eye" class="size-4" /></span>
          <span id={"#{@id}-hide"} class="hidden leading-none"><.icon
            name="hero-eye-slash"
            class="size-4"
          /></span>
        </button>
      </div>
      <p :if={@hint} class="mt-1.5 text-xs text-zinc-500">{@hint}</p>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  attr :for, :string, default: nil
  slot :inner_block, required: true

  defp label(assigns) do
    ~H"""
    <label for={@for} class="mb-1.5 block text-[13px] font-medium text-zinc-600">
      {render_slot(@inner_block)}
    </label>
    """
  end

  slot :inner_block, required: true

  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex items-center gap-1.5 text-xs text-rose-600">
      <.icon name="hero-exclamation-circle-mini" class="size-4 shrink-0" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  # Filled grey fields in the app; bordered white fields on auth pages.
  defp field_class do
    [
      "block h-10 w-full rounded-md border border-transparent bg-field px-3 text-sm text-ink",
      "placeholder:text-zinc-400 transition duration-150 hover:bg-[#ededeb]",
      "focus:border-zinc-300 focus:bg-white focus:outline-none focus:ring-3 focus:ring-zinc-900/5",
      "in-[.auth-shell]:border-zinc-300 in-[.auth-shell]:bg-white in-[.auth-shell]:shadow-xs",
      "in-[.auth-shell]:hover:border-zinc-400 in-[.auth-shell]:focus:border-zinc-500",
      "read-only:text-zinc-500 in-[.auth-shell]:read-only:bg-zinc-50"
    ]
  end

  defp error_class, do: "border-rose-300 in-[.auth-shell]:border-rose-300 focus:border-rose-400"

  defp toggle_password(id) do
    {"type", "text", "password"}
    |> JS.toggle_attribute(to: "##{id}")
    |> JS.toggle_class("hidden", to: "##{id}-show, ##{id}-hide")
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com), e.g. `<.icon name="hero-x-mark" />`.
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-out duration-200", "opacity-0 -translate-y-1 scale-[0.98]",
         "opacity-100 translate-y-0 scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 150,
      transition:
        {"transition-all ease-in duration-150", "opacity-100 translate-y-0 scale-100",
         "opacity-0 -translate-y-1 scale-[0.98]"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(DueDeskWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(DueDeskWeb.Gettext, "errors", msg, opts)
    end
  end
end
