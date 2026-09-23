defmodule Posbd.Repo.Migrations.AddPrinterSettingsToBusinesses do
  use Ecto.Migration

  def change do
    alter table(:businesses) do
      # Thermal rolls come in two widths (58mm/80mm); "a4"/"a5" print a
      # full-page invoice instead. A clinic/medical business might want a4
      # with larger text for a detailed itemized bill, where a clothing
      # shop wants an 80mm receipt - these are per-business, not global.
      add :printer_paper_width, :string, null: false, default: "80mm"
      add :printer_header_align, :string, null: false, default: "center"
      add :printer_font_size, :string, null: false, default: "normal"
      add :default_print_layout, :string, null: false, default: "thermal"
    end
  end
end
