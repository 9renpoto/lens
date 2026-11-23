defmodule Lens.Repo.Migrations.AddEarningsIssuerToSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add(
        :earnings_issuer_id,
        references(:analysis_targets, type: :binary_id, on_delete: :restrict)
      )
    end
  end
end
