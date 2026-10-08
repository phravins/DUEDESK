defmodule DueDeskWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import DueDeskWeb.CoreComponents

  defp field(errors) do
    form = to_form(%{"email" => "nope"}, as: :user, errors: errors)
    form[:email]
  end

  defp render_input(attrs) do
    assigns = %{attrs: attrs}

    ~H"""
    <.input {@attrs} />
    """
    |> rendered_to_string()
    |> LazyHTML.from_fragment()
  end

  defp attr_of(doc, selector, name),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  describe "input/1" do
    test "keeps one message line whether or not there is an error" do
      clean = render_input(%{field: field([]), type: "email", label: "Email"})
      assert LazyHTML.query(clean, "#user_email-message") |> Enum.count() == 1
      assert LazyHTML.text(LazyHTML.query(clean, "#user_email-message")) =~ ~r/^\s*$/
      assert attr_of(clean, "input#user_email", "aria-invalid") == []

      errors = [email: {"is invalid", []}, email: {"is taken", []}]
      invalid = render_input(%{field: field(errors), type: "email", label: "Email"})
      message = LazyHTML.query(invalid, "#user_email-message")

      assert Enum.count(message) == 1
      assert LazyHTML.text(message) =~ "is invalid"
      refute LazyHTML.text(message) =~ "is taken"
      assert attr_of(invalid, "input#user_email", "aria-invalid") == ["true"]
      assert attr_of(invalid, "input#user_email", "aria-describedby") == ["user_email-message"]
    end

    test "an error takes the hint's place without removing it" do
      doc =
        render_input(%{
          field: field(email: {"is invalid", []}),
          label: "Email",
          hint: "Work email"
        })

      assert LazyHTML.query(doc, "#user_email-message .invisible") |> LazyHTML.text() =~
               "Work email"
    end

    test "typed fields validate on blur unless told otherwise" do
      assert attr_of(render_input(%{field: field([])}), "input", "phx-debounce") == ["blur"]

      assert attr_of(
               render_input(%{field: field([]), "phx-debounce": "300"}),
               "input",
               "phx-debounce"
             ) ==
               ["300"]

      assert attr_of(render_input(%{field: field([]), type: "search"}), "input", "phx-debounce") ==
               []

      assert attr_of(render_input(%{field: field([]), type: "date"}), "input", "phx-debounce") ==
               []
    end

    test "compact inputs have no message line" do
      doc = render_input(%{field: field([]), messages: false})
      assert LazyHTML.query(doc, "#user_email-message") |> Enum.count() == 0
    end
  end

  describe "button/1" do
    test "a loading button keeps its label and shows a spinner instead of new text" do
      assigns = %{}

      doc =
        ~H"""
        <.button id="save" phx-disable-with="Saving...">Save</.button>
        """
        |> rendered_to_string()
        |> LazyHTML.from_fragment()

      assert attr_of(doc, "#save", "phx-disable-with") == []
      assert LazyHTML.text(LazyHTML.query(doc, "#save")) =~ "Save"
      refute LazyHTML.text(LazyHTML.query(doc, "#save")) =~ "Saving"
      assert LazyHTML.query(doc, "#save .animate-spin") |> Enum.count() == 1
    end
  end
end
