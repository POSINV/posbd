defmodule Posbd.Businesses.Business do
  use Ecto.Schema
  import Ecto.Changeset

  alias Posbd.Businesses.BusinessTypes

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "businesses" do
    field :name, :string
    field :slug, :string
    field :business_type, :string
    field :country, :string
    field :currency, :string, default: "INR"
    field :timezone, :string, default: "Asia/Kolkata"
    field :language, :string, default: "en"
    field :date_format, :string, default: "%d-%m-%Y"
    field :settings, :map, default: %{}
    field :onboarding_completed_at, :utc_datetime
    field :invoice_prefix, :string, default: "INV-"
    # Atomically incremented by Posbd.Billing when creating an invoice -
    # never cast from client params (see AGENTS.md §33).
    field :next_invoice_number, :integer, default: 1

    # Printed on invoices (see AGENTS.md §16 Invoice Configuration).
    field :address, :string
    field :phone, :string
    field :email, :string
    field :tax_number, :string
    field :invoice_footer, :string
    field :invoice_terms, :string

    # Printer/receipt layout (see AGENTS.md §16): a clinic printing a
    # detailed itemized bill wants a4 with larger text, a clothing shop
    # wants an 80mm thermal receipt - these vary per business, not just
    # per print job, so the business's preference is the default here
    # and the print screen still lets a cashier override it per print.
    field :printer_paper_width, :string, default: "80mm"
    field :printer_header_align, :string, default: "center"
    field :printer_font_size, :string, default: "normal"
    field :default_print_layout, :string, default: "thermal"

    has_many :memberships, Posbd.Businesses.Membership

    timestamps(type: :utc_datetime)
  end

  @paper_widths ~w(58mm 80mm a4 a5 letter)
  @alignments ~w(left center right)
  @font_sizes ~w(small normal large)
  @print_layouts ~w(thermal compact a4)

  @required ~w(name business_type)a
  @optional ~w(country currency timezone language date_format settings invoice_prefix
               address phone email tax_number invoice_footer invoice_terms
               printer_paper_width printer_header_align printer_font_size default_print_layout)a

  def changeset(business, attrs) do
    business
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:business_type, Map.keys(BusinessTypes.templates()),
      message: "is not a supported business type"
    )
    |> validate_length(:name, min: 2, max: 160)
    |> validate_length(:currency, is: 3)
    |> update_change(:currency, &String.upcase/1)
    |> validate_inclusion(:printer_paper_width, @paper_widths)
    |> validate_inclusion(:printer_header_align, @alignments)
    |> validate_inclusion(:printer_font_size, @font_sizes)
    |> validate_inclusion(:default_print_layout, @print_layouts)
    |> put_slug()
    |> unique_constraint(:slug)
  end

  def complete_onboarding_changeset(business) do
    change(business, onboarding_completed_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp put_slug(changeset) do
    case get_change(changeset, :name) do
      nil ->
        changeset

      name ->
        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "-")
          |> String.trim("-")
          |> Kernel.<>("-" <> (:crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)))

        put_change(changeset, :slug, slug)
    end
  end
end
