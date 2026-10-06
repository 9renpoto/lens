defmodule Lens.Repo.Migrations.AllowRegisteredEarningsIssuers do
  use Ecto.Migration

  def up do
    drop(constraint(:earnings_http_checks, :earnings_http_check_bounds))

    create(
      constraint(:earnings_http_checks, :earnings_http_check_bounds,
        check:
          "char_length(issuer_code) BETWEEN 1 AND 50 AND btrim(issuer_code) <> '' AND kind IN ('pdf','listing') AND requests BETWEEN 0 AND 4 AND (http_status IS NULL OR http_status BETWEEN 100 AND 599) AND (byte_size IS NULL OR byte_size BETWEEN 0 AND CASE WHEN kind = 'pdf' THEN 20971520 ELSE 2097152 END)"
      )
    )
  end

  def down do
    raise Ecto.MigrationError,
          "Cannot restore the fixed issuer whitelist after registering other issuers; restore a coordinated backup instead"
  end
end
