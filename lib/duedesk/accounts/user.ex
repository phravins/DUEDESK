defmodule DueDesk.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :name, :string
    field :email, :string
    field :mobile_number, :string
    field :mobile_verified_at, :utc_datetime
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for public sign up: name, email, mobile and password.

  ## Options

    * `:validate_unique` - Set to false to skip the email uniqueness check,
      useful for live validation. Defaults to `true`.
    * `:hash_password` - Set to false to keep the plain password on the
      changeset, useful for live validation. Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:name, :email, :mobile_number, :password])
    |> validate_name()
    |> validate_mobile_number(required: true)
    |> validate_email(opts)
    |> validate_password(opts)
  end

  @doc """
  A user changeset for editing the profile (name and mobile).
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :mobile_number])
    |> validate_name()
    |> validate_mobile_number(required: true)
  end

  defp validate_name(changeset) do
    changeset
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 120)
  end

  @doc """
  Validates and normalises an Indian mobile number on `field`.

  Accepts formats like `98765 43210`, `09876543210` and `+91 98765 43210`
  and stores them as `+919876543210`.
  """
  def validate_mobile_number(changeset, opts \\ []) do
    field = Keyword.get(opts, :field, :mobile_number)

    changeset =
      if Keyword.get(opts, :required, false),
        do: validate_required(changeset, [field], message: "enter a mobile number"),
        else: changeset

    case get_change(changeset, field) do
      nil ->
        changeset

      raw ->
        case normalize_mobile(raw) do
          {:ok, normalized} ->
            put_change(changeset, field, normalized)

          :error ->
            add_error(changeset, field, "must be a 10-digit Indian mobile number")
        end
    end
  end

  @doc false
  def normalize_mobile(raw) when is_binary(raw) do
    digits = String.replace(raw, ~r/[\s\-()]/, "")

    digits =
      cond do
        String.starts_with?(digits, "+91") ->
          String.slice(digits, 3..-1//1)

        String.starts_with?(digits, "91") and byte_size(digits) == 12 ->
          String.slice(digits, 2..-1//1)

        String.starts_with?(digits, "0") and byte_size(digits) == 11 ->
          String.slice(digits, 1..-1//1)

        true ->
          digits
      end

    if Regex.match?(~r/^[6-9]\d{9}$/, digits), do: {:ok, "+91" <> digits}, else: :error
  end

  @doc """
  A user changeset for changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> validate_email_changed()
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> update_change(:email, &String.trim/1)
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$/,
        message: "must be a valid email address"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, DueDesk.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 10, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%DueDesk.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
