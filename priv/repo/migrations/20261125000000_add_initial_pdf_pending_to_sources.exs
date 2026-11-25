defmodule Lens.Repo.Migrations.AddInitialPDFPendingToSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add(:initial_pdf_pending, :boolean, default: false, null: false)
    end
  end
end
